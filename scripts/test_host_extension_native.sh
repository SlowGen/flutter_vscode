#!/usr/bin/env bash
set -euo pipefail

# The pinned Extension Host gate, natively on the host OS.
#
# The container gate proves Linux; every live-only webview bug this project
# has found was found by hand on desktop. Same driver, same pinned VS Code,
# same contract verification -- no container, no xvfb. On macOS the
# @vscode/test-electron download resolves the darwin build and the Electron
# window runs headed.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
HARNESS="${REPO_ROOT}/packages/flutter_vscode/tool/extension_host_test"
TEMP_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/flutter-vscode-host-native.XXXXXX")"
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

(cd "${HARNESS}" && npm ci --no-audit --no-fund)

node --test \
  "${HARNESS}/bootstrap_lifecycle.test.cjs" \
  "${HARNESS}/host_contract.test.cjs"

VSCODE_TEST_CACHE_PATH="${CACHE_ROOT}" node "${HARNESS}/run.cjs"
