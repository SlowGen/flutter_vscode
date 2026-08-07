#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
HARNESS="${REPO_ROOT}/packages/flutter_vscode/tool/extension_host_test"
IMAGE_NAME="flutter-vscode-host-test:local"
EXTENSION_ROOT="${REPO_ROOT}/extensions/pubspec_lens"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-vscode-pubspec-lens.XXXXXX")"
TEMP_ROOT="$(cd "${TEMP_ROOT}" && pwd -P)"
CACHE_ROOT="${FLUTTER_VSCODE_TEST_CACHE:-${TEMP_ROOT}/vscode-test-cache}"
WORKSPACE="${TEMP_ROOT}/workspace"

cleanup() {
  # Best-effort: a containerized VS Code writes its cache as root, so
  # the runner user may be unable to delete it. The next invocation
  # mktemps a fresh root either way, and a failing rm inside an EXIT
  # trap must not overwrite a green gate's exit status.
  rm -rf "${TEMP_ROOT}" 2>/dev/null ||
    echo "[cleanup] left ${TEMP_ROOT} behind (container-owned files)" >&2
}
trap cleanup EXIT

mkdir -p "${CACHE_ROOT}"
mkdir -p "${WORKSPACE}/vendor/local_dep"

# One pin of each verdict, plus a skipped path dependency. The
# driver's fake registry answers current_pkg and behind_pkg with
# 1.2.3 and old_pkg with 2.0.0, so: current_pkg ^1.2.3 has nothing to
# suggest (silent), behind_pkg ^1.2.0 admits 1.2.3 but trails it (lens
# only), and old_pkg ^0.9.0 excludes 2.0.0 (lens and diagnostic).
cat > "${WORKSPACE}/pubspec.yaml" <<'EOF'
name: lens_workspace
environment:
  sdk: ^3.12.0

dependencies:
  current_pkg: ^1.2.3
  behind_pkg: ^1.2.0
  old_pkg: ^0.9.0
  local_dep:
    path: ./vendor/local_dep
EOF
cat > "${WORKSPACE}/vendor/local_dep/pubspec.yaml" <<'EOF'
name: local_dep
environment:
  sdk: ^3.12.0
EOF

(
  cd "${EXTENSION_ROOT}"
  dart "${REPO_ROOT}/packages/flutter_vscode/bin/flutter_vscode.dart" build
  dart "${REPO_ROOT}/packages/flutter_vscode/bin/flutter_vscode.dart" package
)

if [[ "${FLUTTER_VSCODE_GATE_NATIVE:-0}" == "1" ]]; then
  # Same driver, same pinned VS Code, natively on the host OS — the
  # desktop platform Extension Authors actually develop on.
  (cd "${HARNESS}" && npm ci --no-audit --no-fund)
  VSCODE_TEST_CACHE_PATH="${CACHE_ROOT}" \
    FLUTTER_VSCODE_PUBSPEC_LENS_PROJECT="${EXTENSION_ROOT}" \
    FLUTTER_VSCODE_PUBSPEC_LENS_WORKSPACE="${WORKSPACE}" \
    node "${HARNESS}/run_pubspec_lens.cjs"
else
  docker build \
    --file "${HARNESS}/Dockerfile" \
    --tag "${IMAGE_NAME}" \
    "${REPO_ROOT}"

  docker run --rm --init --shm-size=1g \
    --volume "${REPO_ROOT}:/workspace:ro" \
    --volume "${WORKSPACE}:/pubspec-workspace" \
    --volume "${CACHE_ROOT}:/vscode-test-cache" \
    --env VSCODE_TEST_CACHE_PATH=/vscode-test-cache \
    --env FLUTTER_VSCODE_PUBSPEC_LENS_PROJECT=/workspace/extensions/pubspec_lens \
    --env FLUTTER_VSCODE_PUBSPEC_LENS_WORKSPACE=/pubspec-workspace \
    --workdir /test-run \
    "${IMAGE_NAME}" \
    xvfb-run -a node /workspace/packages/flutter_vscode/tool/extension_host_test/run_pubspec_lens.cjs
fi
