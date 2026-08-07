'use strict';

const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {
  contractArtifactPath,
  repositoryRoot,
  verifyHostContractSourceFiles,
} = require('./host_contract.cjs');

const contractId = 'checkpoint4ExtensionHost';
const contract = {
  schemaVersion: 1,
  id: contractId,
  boundary: 'vscodeExtensionHost',
};
const canonicalArtifactPath = contractArtifactPath;
const canonicalSourcePaths = Object.fromEntries(
  Object.entries(JSON.parse(
    fs.readFileSync(canonicalArtifactPath, 'utf8'),
  ).sources).map(([sourceId, receipt]) => [sourceId, receipt.path]),
);

function sha256(bytes) {
  return crypto.createHash('sha256').update(bytes).digest('hex');
}

function createCanonicalRepository() {
  const repositoryRoot = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-host-source-test-'),
  );
  const sources = {};
  const definitionPath =
    'packages/dart_vscode/tool/bindings/host-contract-sources.json';
  for (const [sourceId, sourcePath] of Object.entries(canonicalSourcePaths)) {
    // The definition is itself receipted, so the synthetic tree needs the real
    // JSON there rather than a placeholder: the verifier parses it.
    const sourceBytes = sourcePath === definitionPath
      ? `${JSON.stringify({schemaVersion: 1, sources: canonicalSourcePaths}, null, 2)}\n`
      : `${sourceId}\n`;
    const sourceFile = path.join(repositoryRoot, ...sourcePath.split('/'));
    fs.mkdirSync(path.dirname(sourceFile), {recursive: true});
    fs.writeFileSync(sourceFile, sourceBytes);
    sources[sourceId] = {path: sourcePath, sha256: sha256(sourceBytes)};
  }
  return {repositoryRoot, contract: {...contract, sources}};
}

test('the verifier module owns the evidence paths', () => {
  // Eight hand-built spellings of these paths across two languages broke
  // twice in one week; every .cjs reader must cross this one seam instead.
  const owner = require('./host_contract.cjs');
  assert.equal(typeof owner.repositoryRoot, 'string');
  assert.equal(typeof owner.hostContractSourcesPath, 'string');
  assert.equal(typeof owner.contractArtifactPath, 'string');
  assert.ok(path.isAbsolute(owner.hostContractSourcesPath));
  assert.ok(path.isAbsolute(owner.contractArtifactPath));
  assert.ok(fs.existsSync(owner.hostContractSourcesPath));
  assert.ok(fs.existsSync(owner.contractArtifactPath));
  const sources = JSON.parse(
    fs.readFileSync(owner.hostContractSourcesPath, 'utf8'),
  ).sources;
  assert.equal(
    path.join(owner.repositoryRoot, sources.hostContractSources),
    owner.hostContractSourcesPath,
    'the sources definition must receipt itself at the exported path',
  );
});

test('Host Contract source receipts reject a canonical source rebound', () => {
  const artifact = JSON.parse(
    fs.readFileSync(contractArtifactPath, 'utf8'),
  );
  for (const receipt of Object.values(artifact.sources)) {
    receipt.sha256 = crypto
      .createHash('sha256')
      .update(fs.readFileSync(path.join(repositoryRoot, receipt.path)))
      .digest('hex');
  }
  artifact.sources.bindingGenerator = {...artifact.sources.viewLibrary};

  assert.throws(
    () => verifyHostContractSourceFiles({
      contractId,
      contract: artifact,
      repositoryRoot,
    }),
    /source bindingGenerator path must be packages\/dart_vscode\/tool\/binding_generator\/generator\.dart; found packages\/flutter_vscode\/lib\/view\.dart/,
  );
});

test('Host Contract source receipts reject a missing source', () => {
  const fixture = createCanonicalRepository();
  const runner = fixture.contract.sources.runner;
  fs.rmSync(path.join(fixture.repositoryRoot, runner.path));
  try {
    assert.throws(
      () => verifyHostContractSourceFiles({
        contractId,
        contract: fixture.contract,
        repositoryRoot: fixture.repositoryRoot,
      }),
      /source runner is missing: scripts\/test_host_extension\.sh/,
    );
  } finally {
    fs.rmSync(fixture.repositoryRoot, {recursive: true, force: true});
  }
});

test('Host Contract source receipts reject changed source bytes', () => {
  const fixture = createCanonicalRepository();
  const runner = fixture.contract.sources.runner;
  try {
    fs.writeFileSync(
      path.join(fixture.repositoryRoot, runner.path),
      'changed\n',
    );
    assert.throws(
      () => verifyHostContractSourceFiles({
        contractId,
        contract: fixture.contract,
        repositoryRoot: fixture.repositoryRoot,
      }),
      /source runner SHA-256 mismatch: scripts\/test_host_extension\.sh/,
    );
  } finally {
    fs.rmSync(fixture.repositoryRoot, {recursive: true, force: true});
  }
});

test('Host Contract source receipts reject paths outside the repository', () => {
  const fixture = createCanonicalRepository();
  fixture.contract.sources.runner = {
    path: '../outside.cjs',
    sha256: sha256('trusted source\n'),
  };
  try {
    assert.throws(
      () => verifyHostContractSourceFiles({
        contractId,
        contract: fixture.contract,
        repositoryRoot: fixture.repositoryRoot,
      }),
      /source runner path must be scripts\/test_host_extension\.sh; found \.\.\/outside\.cjs/,
    );
  } finally {
    fs.rmSync(fixture.repositoryRoot, {recursive: true, force: true});
  }
});

test('launcher verifies source receipts before starting the Extension Host', () => {
  const launcher = fs.readFileSync(path.join(__dirname, 'run.cjs'), 'utf8');
  const preflight = launcher.indexOf('verifyHostContractSourceFiles({');
  const launch = launcher.indexOf('await runTests({');

  assert.notEqual(preflight, -1);
  assert.notEqual(launch, -1);
  assert.ok(preflight < launch);
});

test('source verification reports the exact receipt count', () => {
  const fixture = createCanonicalRepository();
  try {
    assert.deepEqual(
      verifyHostContractSourceFiles({
        contractId,
        contract: fixture.contract,
        repositoryRoot: fixture.repositoryRoot,
      }),
      {sourceCount: Object.keys(canonicalSourcePaths).length},
    );
  } finally {
    fs.rmSync(fixture.repositoryRoot, {recursive: true, force: true});
  }
});
