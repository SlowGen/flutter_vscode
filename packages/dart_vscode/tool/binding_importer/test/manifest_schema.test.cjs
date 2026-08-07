const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const test = require('node:test');

const {
  extractManifestSchemaProjection,
} = require('../src/manifest_schema.cjs');

test('extracts the pinned manifest overlay fields used by the walking slice', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/extension-manifest-schema.ts',
  );

  assert.deepEqual(
    extractManifestSchemaProjection(
      fs.readFileSync(inputPath, 'utf8'),
      inputPath,
    ),
    {
      schemaUri: 'vscode://schemas/vscode-extensions',
      standalone: false,
      properties: {
        activationEvents: {
          type: 'array',
          items: {type: 'string'},
        },
        contributes: {type: 'object'},
        displayName: {type: 'string'},
        engines: {
          type: 'object',
          properties: {
            vscode: {type: 'string'},
          },
        },
        publisher: {type: 'string'},
      },
    },
  );
});

test('fails closed when a required manifest schema path changes shape', () => {
  const source = `
    const schemaId = 'vscode://schemas/vscode-extensions';
    export const schema = {
      properties: {
        publisher: { type: 'number' },
        displayName: { type: 'string' },
        engines: {
          type: 'object',
          properties: { vscode: { type: 'string' } },
        },
        activationEvents: {
          type: 'array',
          items: { type: 'string' },
        },
        contributes: { type: 'object', properties: {} },
      },
    };
  `;

  assert.throws(
    () => extractManifestSchemaProjection(source, 'changed-schema.ts'),
    (error) => {
      assert.equal(error.code, 'MANIFEST_SCHEMA_UNSUPPORTED');
      assert.match(error.message, /changed-schema\.ts/);
      assert.match(error.message, /publisher\.type/);
      assert.match(error.message, /expected string/);
      return true;
    },
  );
});

test('fails closed when an unprojected root schema constraint appears', () => {
  const inputPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/extension-manifest-schema.ts',
  );
  const source = fs.readFileSync(inputPath, 'utf8');
  const changed = source.replace(
    'export const schema: IJSONSchema = {\n',
    "export const schema: IJSONSchema = {\n\trequired: ['futureRequiredField'],\n",
  );
  assert.notEqual(changed, source);

  assert.throws(
    () => extractManifestSchemaProjection(changed, 'changed-schema.ts'),
    (error) => {
      assert.equal(error.code, 'MANIFEST_SCHEMA_UNSUPPORTED');
      assert.match(error.message, /changed-schema\.ts/);
      assert.match(error.message, /schema\.required/);
      return true;
    },
  );
});
