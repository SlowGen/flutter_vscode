'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

// This module owns the evidence paths for every .cjs reader: the one
// receipt-path definition is read rather than transcribed, and the
// artifact and repository-root resolutions are exported so no caller
// hand-builds them again.
const REPOSITORY_ROOT = path.resolve(__dirname, '../../../..');
const HOST_CONTRACT_SOURCES_PATH =
  'packages/dart_vscode/tool/bindings/host-contract-sources.json';
const CONTRACT_ARTIFACT_PATH =
  'packages/dart_vscode/tool/bindings/contracts/' +
  'checkpoint4-extension-host.json';

function readCanonicalSourcePaths(repositoryRoot) {
  const file = path.join(repositoryRoot, HOST_CONTRACT_SOURCES_PATH);
  return JSON.parse(fs.readFileSync(file, 'utf8')).sources;
}

function verifyHostContractSourceFiles({contractId, contract, repositoryRoot}) {
  const sources = contract?.sources;
  if (
    contract?.schemaVersion !== 1 ||
    contract.id !== contractId ||
    contract.boundary !== 'vscodeExtensionHost' ||
    sources === null ||
    typeof sources !== 'object' ||
    Array.isArray(sources) ||
    Object.keys(sources).length === 0
  ) {
    throw new Error(`Host Contract ${contractId} source schema is invalid.`);
  }

  const canonicalSourcePaths = readCanonicalSourcePaths(repositoryRoot);
  const sourceIds = Object.keys(sources).sort();
  const canonicalSourceIds = Object.keys(canonicalSourcePaths).sort();
  if (JSON.stringify(sourceIds) !== JSON.stringify(canonicalSourceIds)) {
    throw new Error(
      `Host Contract ${contractId} source keys must be exactly ` +
      `[${canonicalSourceIds.join(', ')}]; found [${sourceIds.join(', ')}].`,
    );
  }

  const realRepositoryRoot = fs.realpathSync(repositoryRoot);
  if (!fs.statSync(realRepositoryRoot).isDirectory()) {
    throw new Error(
      `Host Contract ${contractId} repository root is not a directory.`,
    );
  }

  for (const [sourceId, receipt] of Object.entries(sources)) {
    if (
      receipt === null ||
      typeof receipt !== 'object' ||
      Array.isArray(receipt) ||
      Object.keys(receipt).sort().join(',') !== 'path,sha256' ||
      typeof receipt.path !== 'string' ||
      receipt.path.length === 0 ||
      typeof receipt.sha256 !== 'string' ||
      !/^[0-9a-f]{64}$/.test(receipt.sha256)
    ) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} receipt is invalid.`,
      );
    }
    const canonicalPath = canonicalSourcePaths[sourceId];
    if (receipt.path !== canonicalPath) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} path must be ` +
        `${canonicalPath}; found ${receipt.path}.`,
      );
    }
    const segments = receipt.path.split('/');
    if (
      path.posix.isAbsolute(receipt.path) ||
      receipt.path.includes('\\') ||
      path.posix.normalize(receipt.path) !== receipt.path ||
      segments.some((segment) =>
        segment.length === 0 || segment === '.' || segment === '..')
    ) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} path escapes ` +
        `repository: ${receipt.path}`,
      );
    }
    const sourcePath = path.resolve(realRepositoryRoot, ...segments);
    const relativeSourcePath = path.relative(realRepositoryRoot, sourcePath);
    if (
      path.isAbsolute(relativeSourcePath) ||
      relativeSourcePath === '..' ||
      relativeSourcePath.startsWith(`..${path.sep}`)
    ) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} path escapes ` +
        `repository: ${receipt.path}`,
      );
    }
    if (!fs.existsSync(sourcePath)) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} is missing: ` +
        receipt.path,
      );
    }
    const realSourcePath = fs.realpathSync(sourcePath);
    const relativeRealSourcePath = path.relative(
      realRepositoryRoot,
      realSourcePath,
    );
    if (
      path.isAbsolute(relativeRealSourcePath) ||
      relativeRealSourcePath === '..' ||
      relativeRealSourcePath.startsWith(`..${path.sep}`)
    ) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} path escapes ` +
        `repository: ${receipt.path}`,
      );
    }
    if (!fs.statSync(realSourcePath).isFile()) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} is not a file: ` +
        receipt.path,
      );
    }
    const actualSha256 = crypto
      .createHash('sha256')
      .update(fs.readFileSync(realSourcePath))
      .digest('hex');
    if (actualSha256 !== receipt.sha256) {
      throw new Error(
        `Host Contract ${contractId} source ${sourceId} SHA-256 mismatch: ` +
        receipt.path,
      );
    }
  }

  return {sourceCount: Object.keys(sources).length};
}

module.exports = {
  verifyHostContractSourceFiles,
  repositoryRoot: REPOSITORY_ROOT,
  hostContractSourcesPath: path.join(
    REPOSITORY_ROOT,
    ...HOST_CONTRACT_SOURCES_PATH.split('/'),
  ),
  contractArtifactPath: path.join(
    REPOSITORY_ROOT,
    ...CONTRACT_ARTIFACT_PATH.split('/'),
  ),
};
