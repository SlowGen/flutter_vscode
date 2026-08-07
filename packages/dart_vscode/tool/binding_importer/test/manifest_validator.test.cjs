const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  extractManifestValidatorProjection,
} = require('../src/manifest_validator.cjs');

test('extracts validator predicates used by generated walking-slice manifests', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/extension-validator.ts',
  );

  assert.deepEqual(
    extractManifestValidatorProjection(
      fs.readFileSync(inputPath, 'utf8'),
      inputPath,
    ),
    {
      generatedManifestRules: [
        {path: 'publisher', presence: 'optional', type: 'string'},
        {path: 'name', presence: 'required', type: 'string'},
        {path: 'version', presence: 'required', type: 'string'},
        {path: 'engines', presence: 'required', type: 'object'},
        {path: 'engines.vscode', presence: 'required', type: 'string'},
        {
          path: 'activationEvents',
          presence: 'optional',
          type: 'string[]',
          requiresAny: ['main', 'browser'],
        },
        {path: 'main', presence: 'optional', type: 'string'},
      ],
      versionPredicate: 'semver.valid',
      engineVersionSyntax: {
        source: '^(\\^|>=)?((\\d+)|x)\\.((\\d+)|x)\\.((\\d+)|x)(\\-.*)?$',
        flags: '',
      },
      validatorBodySha256:
        'a7df6554afff3fa5c5e021f793fc8a4662fc641ade451565a8ff59929cf5a171',
      projectionLimits: {
        remainingValidatorBranches:
          'integrityPinnedByValidatorBodySha256',
        semverValidImplementation: 'unprojectedExternal',
      },
    },
  );
});

test('fails closed when a projected validator predicate changes', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/extension-validator.ts',
  );
  const source = fs.readFileSync(inputPath, 'utf8');
  const changed = source.replace(
    "typeof extensionManifest.name !== 'string'",
    "typeof extensionManifest.name !== 'number'",
  );
  assert.notEqual(changed, source);

  assert.throws(
    () => extractManifestValidatorProjection(changed, 'changed-validator.ts'),
    (error) => {
      assert.equal(error.code, 'MANIFEST_VALIDATOR_UNSUPPORTED');
      assert.match(error.message, /changed-validator\.ts/);
      assert.match(error.message, /validateExtensionManifest\.name/);
      return true;
    },
  );
});

test('records unprojected validator behavior as integrity-only evidence', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/extension-validator.ts',
  );
  const projection = extractManifestValidatorProjection(
    fs.readFileSync(inputPath, 'utf8'),
    inputPath,
  );

  assert.deepEqual(projection.projectionLimits, {
    remainingValidatorBranches: 'integrityPinnedByValidatorBodySha256',
    semverValidImplementation: 'unprojectedExternal',
  });
  assert.match(projection.validatorBodySha256, /^[a-f0-9]{64}$/);
});

test('an added unprojected validator condition changes the integrity pin', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/extension-validator.ts',
  );
  const source = fs.readFileSync(inputPath, 'utf8');
  const changed = source.replace(
    "\tif (typeof extensionManifest.name !== 'string') {",
    "\tif (extensionManifest.name?.length === 0) { return validations; }\n" +
      "\tif (typeof extensionManifest.name !== 'string') {",
  );
  assert.notEqual(changed, source);

  const originalProjection = extractManifestValidatorProjection(
    source,
    inputPath,
  );
  const changedProjection = extractManifestValidatorProjection(
    changed,
    'changed-validator.ts',
  );

  assert.notEqual(
    changedProjection.validatorBodySha256,
    originalProjection.validatorBodySha256,
  );
});
