#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
IMAGE_NAME="flutter-vscode-host-test:local"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-vscode-host-test.XXXXXX")"
TEMP_ROOT="$(cd "${TEMP_ROOT}" && pwd -P)"
CACHE_ROOT="${TEMP_ROOT}/vscode-test-cache"

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

"${REPO_ROOT}/scripts/build_host_fixture.sh"

docker build \
  --file "${REPO_ROOT}/packages/flutter_vscode/tool/extension_host_test/Dockerfile" \
  --tag "${IMAGE_NAME}" \
  "${REPO_ROOT}"

docker run --rm --init --shm-size=1g \
  --volume "${REPO_ROOT}:/workspace:ro" \
  --volume "${CACHE_ROOT}:/vscode-test-cache" \
  --env VSCODE_TEST_CACHE_PATH=/vscode-test-cache \
  --workdir /test-run \
  "${IMAGE_NAME}" \
  sh -c \
  'node --test /workspace/packages/flutter_vscode/tool/extension_host_test/bootstrap_lifecycle.test.cjs \
    /workspace/packages/flutter_vscode/tool/extension_host_test/host_contract.test.cjs &&
   xvfb-run -a node /workspace/packages/flutter_vscode/tool/extension_host_test/run.cjs'
