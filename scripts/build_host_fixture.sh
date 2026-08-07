#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
FIXTURE_ROOT="${REPO_ROOT}/packages/flutter_vscode/test/fixtures/host_extension"

flutter pub get --enforce-lockfile --no-example --directory="${REPO_ROOT}"

(
  cd "${FIXTURE_ROOT}"
  dart "${REPO_ROOT}/packages/flutter_vscode/bin/flutter_vscode.dart" build
)
