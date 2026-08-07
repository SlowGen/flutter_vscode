#!/usr/bin/env bash
set -euo pipefail

# Runs this repository's GitHub Actions workflow locally: every job on the
# platform it declares -- ubuntu jobs in a runner-like Docker container,
# the macOS job natively when this host is macOS. The workflow YAML is the
# one authority on what CI runs; this script exists so a maintainer can
# prove it green before asking anyone to approve an Actions run.
#
# The heavy lifting (YAML parsing, per-job platform dispatch, the shared
# pub cache a runner's single filesystem implies) lives in the gate-tagged
# test this script invokes; keeping it in the standard test framework
# keeps it analyzed, formatted, and debuggable like everything else.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."

cd "${REPO_ROOT}/packages/flutter_vscode"
exec flutter test --tags gate test/ci_workflow_test.dart "$@"
