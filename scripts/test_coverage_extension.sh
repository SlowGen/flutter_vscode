#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
HARNESS="${REPO_ROOT}/packages/flutter_vscode/tool/extension_host_test"
IMAGE_NAME="flutter-vscode-host-test:local"
EXTENSION_ROOT="${REPO_ROOT}/extensions/coverage_treemap"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-vscode-coverage-ext.XXXXXX")"
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
mkdir -p "${WORKSPACE}/coverage" "${WORKSPACE}/lib/src"

# A known tracefile: 6 instrumented lines, 3 executed.
cat > "${WORKSPACE}/coverage/lcov.info" <<'EOF'
SF:lib/main.dart
DA:1,4
DA:2,0
DA:3,1
LF:3
LH:2
end_of_record
SF:lib/src/util.dart
DA:1,0
DA:2,0
DA:3,5
LF:3
LH:1
end_of_record
EOF
printf 'void main() {}\n' > "${WORKSPACE}/lib/main.dart"
printf 'int util() => 0;\n' > "${WORKSPACE}/lib/src/util.dart"

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
    FLUTTER_VSCODE_COVERAGE_PROJECT="${EXTENSION_ROOT}" \
    FLUTTER_VSCODE_COVERAGE_WORKSPACE="${WORKSPACE}" \
    node "${HARNESS}/run_coverage_extension.cjs"
else
  docker build \
    --file "${HARNESS}/Dockerfile" \
    --tag "${IMAGE_NAME}" \
    "${REPO_ROOT}"

  docker run --rm --init --shm-size=1g \
    --volume "${REPO_ROOT}:/workspace:ro" \
    --volume "${WORKSPACE}:/coverage-workspace" \
    --volume "${CACHE_ROOT}:/vscode-test-cache" \
    --env VSCODE_TEST_CACHE_PATH=/vscode-test-cache \
    --env FLUTTER_VSCODE_COVERAGE_PROJECT=/workspace/extensions/coverage_treemap \
    --env FLUTTER_VSCODE_COVERAGE_WORKSPACE=/coverage-workspace \
    --workdir /test-run \
    "${IMAGE_NAME}" \
    xvfb-run -a node /workspace/packages/flutter_vscode/tool/extension_host_test/run_coverage_extension.cjs
fi
