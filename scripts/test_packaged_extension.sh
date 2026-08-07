#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
IMAGE_NAME="flutter-vscode-host-test:local"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-vscode-packaged-cli.XXXXXX")"
TEMP_ROOT="$(cd "${TEMP_ROOT}" && pwd -P)"
CACHE_ROOT="${TEMP_ROOT}/vscode-test-cache"
PUB_CACHE_ROOT="${TEMP_ROOT}/pub-cache"
PACKAGE_COPY="${TEMP_ROOT}/package"
WORKSPACE="${TEMP_ROOT}/workspace"
PROJECT_ROOT="${WORKSPACE}/activated_extension"
VIEW_FIXTURE_ROOT="${TEMP_ROOT}/host-extension-fixture"
LAYER_COPY="${TEMP_ROOT}/dart_vscode"

cleanup() {
  # Best-effort: a containerized VS Code writes its cache as root, so
  # the runner user may be unable to delete it. The next invocation
  # mktemps a fresh root either way, and a failing rm inside an EXIT
  # trap must not overwrite a green gate's exit status.
  rm -rf "${TEMP_ROOT}" 2>/dev/null ||
    echo "[cleanup] left ${TEMP_ROOT} behind (container-owned files)" >&2
}
trap cleanup EXIT

mkdir -p "${PACKAGE_COPY}"
mkdir -p "${WORKSPACE}"
mkdir -p "${VIEW_FIXTURE_ROOT}"
mkdir -p "${CACHE_ROOT}"
# Stage the framework from pub's actual archive selection: the file list
# comes from `dart pub publish --dry-run` itself, so the installed E2E
# exercises exactly what a published package would contain.
PACKAGE_LIST="${TEMP_ROOT}/pub-archive-files.txt"
# The published package is a workspace member; its archive is listed and
# copied relative to the package, not the repository root.
PACKAGE_ROOT="${REPO_ROOT}/packages/flutter_vscode"
(cd "${PACKAGE_ROOT}" && dart tool/pub_archive_list.dart) > "${PACKAGE_LIST}"
grep -qx "pubspec.yaml" "${PACKAGE_LIST}"
grep -qx "bin/flutter_vscode.dart" "${PACKAGE_LIST}"
while IFS= read -r archived_file; do
  mkdir -p "${PACKAGE_COPY}/$(dirname "${archived_file}")"
  cp "${PACKAGE_ROOT}/${archived_file}" "${PACKAGE_COPY}/${archived_file}"
done < "${PACKAGE_LIST}"
(
  cd "${REPO_ROOT}/packages/flutter_vscode/test/fixtures/host_extension"
  tar cf - \
    --exclude=.dart_tool \
    --exclude=build \
    --exclude=node_modules \
    --exclude=out \
    .
) | (cd "${VIEW_FIXTURE_ROOT}" && tar xf -)

# In the checkout the fixture is a member of the repository's pub workspace.
# The copy stands alone the way an Extension Author's project does, so drop the
# workspace opt-in: outside its workspace root pub rejects it outright.
find "${VIEW_FIXTURE_ROOT}" -name pubspec.yaml -print0 | while IFS= read -r -d '' manifest; do
  sed -i.bak '/^resolution: workspace$/d' "${manifest}"
  rm -f "${manifest}.bak"
done

sed -i.bak '/^resolution: workspace$/d' "${PACKAGE_COPY}/pubspec.yaml"
rm -f "${PACKAGE_COPY}/pubspec.yaml.bak"

# `dart_vscode` carries the generated VS Code API and is not published yet, so
# nothing here can resolve it from pub.dev. Stage it beside the package from
# pub's own archive selection — the same mechanism as PACKAGE_COPY — so the
# E2E installs exactly what the published archive would contain; this goes
# away when the two packages ship together.
mkdir -p "${LAYER_COPY}"
LAYER_LIST="${TEMP_ROOT}/dart-vscode-archive-files.txt"
LAYER_ROOT="${REPO_ROOT}/packages/dart_vscode"
(cd "${LAYER_ROOT}" && dart "${PACKAGE_ROOT}/tool/pub_archive_list.dart") \
  > "${LAYER_LIST}"
grep -qx "pubspec.yaml" "${LAYER_LIST}"
while IFS= read -r archived_file; do
  mkdir -p "${LAYER_COPY}/$(dirname "${archived_file}")"
  cp "${LAYER_ROOT}/${archived_file}" "${LAYER_COPY}/${archived_file}"
done < "${LAYER_LIST}"
test ! -e "${LAYER_COPY}/tool"
test ! -e "${LAYER_COPY}/test"
sed -i.bak '/^resolution: workspace$/d' "${LAYER_COPY}/pubspec.yaml"
rm -f "${LAYER_COPY}/pubspec.yaml.bak"
printf '\ndependency_overrides:\n  dart_vscode:\n    path: %s\n' \
  "${LAYER_COPY}" >> "${PACKAGE_COPY}/pubspec.yaml"

# Each package inside the copied fixture is its own resolution root -- the CLI
# runs `pub get` in host/ -- so every one that names the layer needs the same
# override until it is published.
while IFS= read -r manifest; do
  if grep -q '^  dart_vscode:' "${manifest}"; then
    printf '\ndependency_overrides:\n  dart_vscode:\n    path: %s\n' \
      "${LAYER_COPY}" >> "${manifest}"
  fi
done < <(find "${VIEW_FIXTURE_ROOT}" -name pubspec.yaml)

# Binding generation is a dart_vscode maintainer operation: the published
# flutter_vscode archive must carry no generator, IR, or pinned inputs.
test ! -e "${PACKAGE_COPY}/tool/binding_generator"
test ! -e "${PACKAGE_COPY}/tool/bindings"
test -f "${PACKAGE_COPY}/lib/src/cli/check_host_imports.dart"
test ! -e "${PACKAGE_COPY}/tool/check_host_imports.dart"
test ! -e "${PACKAGE_COPY}/test"
test ! -e "${PACKAGE_COPY}/specs"

# The repository fixture normally reaches flutter_vscode by walking back to the
# checkout root. Keep the copied fixture outside the staged package, but bind
# its dependency to the pristine pub-filtered package under test.
PUB_CACHE="${PUB_CACHE_ROOT}" dart pub add \
  --directory="${VIEW_FIXTURE_ROOT}/views/main" \
  --no-precompile \
  "override:flutter_vscode@{path: ${PACKAGE_COPY}}" \
  "override:dart_vscode@{path: ${LAYER_COPY}}"

PUB_CACHE="${PUB_CACHE_ROOT}" dart pub global activate \
  --source path "${PACKAGE_COPY}"
CLI="${PUB_CACHE_ROOT}/bin/flutter_vscode"

(
  cd "${WORKSPACE}"
  PUB_CACHE="${PUB_CACHE_ROOT}" "${CLI}" create activated_extension
  cd "${PROJECT_ROOT}"
  PUB_CACHE="${PUB_CACHE_ROOT}" "${CLI}" build
  PUB_CACHE="${PUB_CACHE_ROOT}" "${CLI}" package
)

(
  cd "${VIEW_FIXTURE_ROOT}"
  PUB_CACHE="${PUB_CACHE_ROOT}" "${CLI}" build
  PUB_CACHE="${PUB_CACHE_ROOT}" "${CLI}" package
)

HARNESS="${REPO_ROOT}/packages/flutter_vscode/tool/extension_host_test"
if [[ "${FLUTTER_VSCODE_GATE_NATIVE:-0}" == "1" ]]; then
  # Same driver, same pinned VS Code, natively on the host OS — the
  # desktop platform Extension Authors actually develop on.
  (cd "${HARNESS}" && npm ci --no-audit --no-fund)
else
  docker build \
    --file "${HARNESS}/Dockerfile" \
    --tag "${IMAGE_NAME}" \
    "${REPO_ROOT}"
fi

run_packaged_project() {
  local project_root="$1"
  local command_result="$2"
  local require_view="$3"

  if [[ "${FLUTTER_VSCODE_GATE_NATIVE:-0}" == "1" ]]; then
    VSCODE_TEST_CACHE_PATH="${CACHE_ROOT}" \
      FLUTTER_VSCODE_PACKAGED_PROJECT="${project_root}" \
      FLUTTER_VSCODE_PACKAGED_COMMAND_RESULT="${command_result}" \
      FLUTTER_VSCODE_PACKAGED_REQUIRE_VIEW="${require_view}" \
      node "${HARNESS}/run_packaged.cjs"
    return
  fi

  docker run --rm --init --shm-size=1g \
    --volume "${REPO_ROOT}:/workspace:ro" \
    --volume "${project_root}:/packaged-project:ro" \
    --volume "${CACHE_ROOT}:/vscode-test-cache" \
    --env VSCODE_TEST_CACHE_PATH=/vscode-test-cache \
    --env FLUTTER_VSCODE_PACKAGED_PROJECT=/packaged-project \
    --env FLUTTER_VSCODE_PACKAGED_COMMAND_RESULT="${command_result}" \
    --env FLUTTER_VSCODE_PACKAGED_REQUIRE_VIEW="${require_view}" \
    --workdir /test-run \
    "${IMAGE_NAME}" \
    xvfb-run -a node /workspace/packages/flutter_vscode/tool/extension_host_test/run_packaged.cjs
}

run_packaged_project "${PROJECT_ROOT}" "Hello from Dart" 0
run_packaged_project "${VIEW_FIXTURE_ROOT}" "pong from Dart" 1
