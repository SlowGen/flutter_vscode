#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}/.."
IMAGE_NAME="flutter-vscode-binding-importer-test:local"

docker build \
  --file "${REPO_ROOT}/packages/dart_vscode/tool/binding_importer/Dockerfile" \
  --tag "${IMAGE_NAME}" \
  "${REPO_ROOT}"

docker run --rm --init \
  --volume "${REPO_ROOT}:/workspace:ro" \
  --workdir /workspace \
  "${IMAGE_NAME}"
