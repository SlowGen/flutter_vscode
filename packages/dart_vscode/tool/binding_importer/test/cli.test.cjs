const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const test = require('node:test');

function materializeRepositoryPins(directory) {
  const sourcePinsPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/pins.json',
  );
  const sourceDirectory = path.dirname(sourcePinsPath);
  const pins = JSON.parse(fs.readFileSync(sourcePinsPath, 'utf8'));
  for (const input of pins.inputs) {
    fs.copyFileSync(
      path.resolve(sourceDirectory, input.path),
      path.join(directory, input.path),
    );
  }
  return pins;
}

test('CLI emits byte-identical canonical IR from verified pinned inputs', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-ir-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pinsPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/pins.json',
  );
  const firstPath = path.join(directory, 'first.json');
  const secondPath = path.join(directory, 'second.json');

  for (const outputPath of [firstPath, secondPath]) {
    const result = spawnSync(
      process.execPath,
      [
        path.resolve(__dirname, '../src/cli.cjs'),
        '--pins',
        pinsPath,
        '--output',
        outputPath,
      ],
      {encoding: 'utf8'},
    );
    assert.equal(result.status, 0, result.stderr);
  }

  const first = fs.readFileSync(firstPath, 'utf8');
  const second = fs.readFileSync(secondPath, 'utf8');
  assert.equal(first, second);
  assert.equal(first.endsWith('\n'), true);
  const ir = JSON.parse(first);
  assert.deepEqual({
    product: ir.source.product,
    parser: ir.source.parser,
    inputSha256: ir.source.inputSha256,
  }, {
    product: {
      name: 'Visual Studio Code',
      version: '1.129.1',
      commit: '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8',
    },
    parser: {
      name: 'typescript',
      version: '6.0.0-dev.20260416',
    },
    inputSha256:
      'ee11e767c8ab76f6c0de8dc88222796147a6f0bc82f3a1ec644e41b39b52f2cd',
  });
  const pins = JSON.parse(fs.readFileSync(pinsPath, 'utf8'));
  assert.deepEqual(ir.source.inputs, pins.inputs);
  assert.deepEqual(ir.source.manifestSchema, pins.manifestSchema);
  assert.deepEqual(ir.source.contributionSchemas, pins.contributionSchemas);
  assert.deepEqual(ir.manifestSchema, {
    inputSha256:
      'feddc98984b755a95644674910aa8c671e3259f137698c581ec7e2837cb058aa',
    schemaUri: 'vscode://schemas/vscode-extensions',
    standalone: false,
    properties: {
      activationEvents: {type: 'array', items: {type: 'string'}},
      contributes: {type: 'object'},
      displayName: {type: 'string'},
      engines: {
        type: 'object',
        properties: {vscode: {type: 'string'}},
      },
      publisher: {type: 'string'},
    },
  });
  assert.deepEqual(ir.manifestValidator, {
    inputSha256:
      'e8ae92aa491ab138b6f625acbbcbd7c53ff187098066ff13aebb64615202dde1',
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
  });
  assert.deepEqual(ir.contributionSchemas.commands, {
    inputSha256:
      'a85c943ae42b2cdef0403070f78cfb9dbe7bcdc1fce7c57bf9ca2234d1e36a33',
    extensionPoint: 'commands',
    accepts: ['object', 'array'],
    itemSchema: {
      type: 'object',
      required: ['command', 'title'],
      properties: {
        category: {type: 'string'},
        command: {type: 'string'},
        enablement: {type: 'string'},
        icon: {
          anyOf: [
            {type: 'string'},
            {
              type: 'object',
              properties: {
                dark: {type: 'string'},
                light: {type: 'string'},
              },
            },
          ],
        },
        shortTitle: {type: 'string'},
        title: {type: 'string'},
      },
    },
    validation: {
      whitespacePredicate: 'ecmascript-trim-empty',
      nonWhitespaceStringProperties: ['command', 'title'],
      icon: {
        objectRequiredStringProperties: ['dark', 'light'],
      },
    },
  });
  assert.equal(ir.declarations.length, 2982);
});

test('CLI canonicalizes schema keys with ordinal ordering', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-ordinal-ir-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const preloadPath = path.join(directory, 'reject-locale-collation.cjs');
  fs.writeFileSync(
    preloadPath,
    "String.prototype.localeCompare = function () {\n" +
      "  throw new Error('ambient locale collation was invoked');\n" +
      '};\n',
  );
  const outputPath = path.join(directory, 'inventory.json');
  const pinsPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/pins.json',
  );

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      outputPath,
    ],
    {
      encoding: 'utf8',
      env: {...process.env, NODE_OPTIONS: `--require=${preloadPath}`},
    },
  );

  assert.equal(result.status, 0, result.stderr);
  const ir = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  assert.deepEqual(
    Object.keys(ir.contributionSchemas.commands.itemSchema.properties),
    ['category', 'command', 'enablement', 'icon', 'shortTitle', 'title'],
  );
});

test('CLI check rejects stale canonical IR with an actionable error', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-stale-ir-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pinsPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/pins.json',
  );
  const staleIrPath = path.join(directory, 'vscode-1.129.1.json');
  fs.writeFileSync(staleIrPath, '{}\n');

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--check',
      staleIrPath,
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^IR_DRIFT: /);
  assert.match(result.stderr, /does not match freshly generated output/);
  assert.match(result.stderr, /Regenerate it with:/);
  assert.match(result.stderr, /--output/);
  assert.match(result.stderr, new RegExp(escapeRegExp(staleIrPath)));
});

test('repository canonical IR matches freshly imported pinned inputs', () => {
  const pinsPath = path.resolve(
    __dirname,
    '../../bindings/inputs/vscode/1.129.1/pins.json',
  );
  const canonicalIrPath = path.resolve(
    __dirname,
    '../../bindings/ir/vscode-1.129.1.json',
  );

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--check',
      canonicalIrPath,
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 0, result.stderr);
});

test('CLI imports the pinned commands contribution schema', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-contribution-schema-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pins = materializeRepositoryPins(directory);
  pins.inputs = pins.inputs.filter(
    (input) => input.kind !== 'contributionSchemaSource',
  );
  const contributionSource = `
import { isFalsyOrWhitespace } from '../../../../base/common/strings.js';
namespace schema {
  export function isValidCommand(command, collector) {
    if (!command) {
      collector.error();
      return false;
    }
    if (isFalsyOrWhitespace(command.command)) {
      collector.error();
      return false;
    }
    if (!isValidLocalizedString(command.title, collector, 'title')) {
      return false;
    }
    if (command.shortTitle && !isValidLocalizedString(command.shortTitle, collector, 'shortTitle')) {
      return false;
    }
    if (command.enablement && typeof command.enablement !== 'string') {
      collector.error();
      return false;
    }
    if (command.category && !isValidLocalizedString(command.category, collector, 'category')) {
      return false;
    }
    if (!isValidIcon(command.icon, collector)) {
      return false;
    }
    return true;
  }
  function isValidIcon(icon, collector) {
    if (typeof icon === 'undefined') {
      return true;
    }
    if (typeof icon === 'string') {
      return true;
    } else if (typeof icon.dark === 'string' && typeof icon.light === 'string') {
      return true;
    }
    collector.error();
    return false;
  }
  function isValidLocalizedString(localized, collector, propertyName) {
    if (typeof localized === 'undefined') {
      collector.error();
      return false;
    } else if (typeof localized === 'string' && isFalsyOrWhitespace(localized)) {
      collector.error();
      return false;
    } else if (typeof localized !== 'string' && (isFalsyOrWhitespace(localized.original) || isFalsyOrWhitespace(localized.value))) {
      collector.error();
      return false;
    }
    return true;
  }
  const commandType: IJSONSchema = {
    type: 'object',
    required: ['command', 'title'],
    properties: {
      command: { description: localize('command', 'Command'), type: 'string' },
      title: { description: localize('title', 'Title'), type: 'string' },
      shortTitle: { markdownDescription: localize('short', 'Short'), type: 'string' },
      category: { description: localize('category', 'Category'), type: 'string' },
      enablement: { description: localize('enablement', 'Enablement'), type: 'string' },
      icon: {
        description: localize('icon', 'Icon'),
        anyOf: [
          { type: 'string' },
          {
            type: 'object',
            properties: {
              light: { description: localize('light', 'Light'), type: 'string' },
              dark: { description: localize('dark', 'Dark'), type: 'string' }
            }
          }
        ]
      }
    }
  };
  export const commandsContribution: IJSONSchema = {
    description: localize('commands', 'Commands'),
    oneOf: [commandType, { type: 'array', items: commandType }]
  };
}
export const commandsExtensionPoint = ExtensionsRegistry.registerExtensionPoint({
  extensionPoint: 'commands',
  jsonSchema: schema.commandsContribution
});
`;
  const contributionPath = path.join(directory, 'menusExtensionPoint.ts');
  fs.writeFileSync(contributionPath, contributionSource);
  const validationHelperInput = pins.inputs.find(
    (input) => input.kind === 'contributionValidationHelperSource',
  );
  assert.notEqual(validationHelperInput, undefined);
  pins.inputs.push({
    name: 'VS Code commands contribution schema source',
    kind: 'contributionSchemaSource',
    path: 'menusExtensionPoint.ts',
    version: '1.129.1',
    commit: validationHelperInput.commit,
    source:
      'https://raw.githubusercontent.com/microsoft/vscode/' +
      `${validationHelperInput.commit}/src/vs/workbench/services/actions/` +
      'common/menusExtensionPoint.ts',
    sha256: crypto
      .createHash('sha256')
      .update(contributionSource)
      .digest('hex'),
    license: 'MIT',
  });
  pins.contributionSchemas = [
    'commands',
    'configuration',
    'views',
    'viewsContainers',
  ];
  const pinsPath = path.join(directory, 'pins.json');
  const outputPath = path.join(directory, 'inventory.json');
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`);

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      outputPath,
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 0, result.stderr);
  const ir = JSON.parse(fs.readFileSync(outputPath, 'utf8'));
  assert.deepEqual(ir.source.contributionSchemas, [
    'commands',
    'configuration',
    'views',
    'viewsContainers',
  ]);
  assert.deepEqual(ir.contributionSchemas.commands, {
    inputSha256: pins.inputs.find(
      (input) => input.kind === 'contributionSchemaSource',
    ).sha256,
    extensionPoint: 'commands',
    accepts: ['object', 'array'],
    itemSchema: {
      type: 'object',
      required: ['command', 'title'],
      properties: {
        category: {type: 'string'},
        command: {type: 'string'},
        enablement: {type: 'string'},
        icon: {
          anyOf: [
            {type: 'string'},
            {
              type: 'object',
              properties: {
                dark: {type: 'string'},
                light: {type: 'string'},
              },
            },
          ],
        },
        shortTitle: {type: 'string'},
        title: {type: 'string'},
      },
    },
    validation: {
      whitespacePredicate: 'ecmascript-trim-empty',
      nonWhitespaceStringProperties: ['command', 'title'],
      icon: {
        objectRequiredStringProperties: ['dark', 'light'],
      },
    },
  });
});

test('CLI fails closed on an unprojected command schema constraint', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-command-schema-drift-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pins = materializeRepositoryPins(directory);
  const contributionInput = pins.inputs.find(
    (input) => input.kind === 'contributionSchemaSource',
  );
  assert.notEqual(contributionInput, undefined);
  const original = fs.readFileSync(
    path.join(directory, contributionInput.path),
    'utf8',
  );
  const changed = original.replace(
    "\t\ttype: 'object',\n\t\trequired: ['command', 'title'],",
    "\t\ttype: 'object',\n\t\tadditionalProperties: false,\n" +
      "\t\trequired: ['command', 'title'],",
  );
  assert.notEqual(changed, original);
  fs.writeFileSync(path.join(directory, contributionInput.path), changed);
  contributionInput.sha256 = crypto
    .createHash('sha256')
    .update(changed)
    .digest('hex');
  const pinsPath = path.join(directory, 'pins.json');
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`);

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      path.join(directory, 'inventory.json'),
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^CONTRIBUTION_SCHEMA_UNSUPPORTED: /);
  assert.match(
    result.stderr,
    /First differing path: schema\.commandType\.additionalProperties/,
  );
  assert.match(result.stderr, /unprojected schema property/);
  assert.match(result.stderr, /Remediation:/);
  assert.match(result.stderr, /contribution_schema\.cjs/);
  assert.match(result.stderr, /regenerate the canonical IR/);
});

test('CLI fails closed when command validator polarity changes', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-command-validator-drift-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pins = materializeRepositoryPins(directory);
  const contributionInput = pins.inputs.find(
    (input) => input.kind === 'contributionSchemaSource',
  );
  assert.notEqual(contributionInput, undefined);
  const original = fs.readFileSync(
    path.join(directory, contributionInput.path),
    'utf8',
  );
  const changed = original.replace(
    'if (!isValidLocalizedString(command.title, collector, \'title\')) {',
    'if (isValidLocalizedString(command.title, collector, \'title\')) {',
  );
  assert.notEqual(changed, original);
  fs.writeFileSync(path.join(directory, contributionInput.path), changed);
  contributionInput.sha256 = crypto
    .createHash('sha256')
    .update(changed)
    .digest('hex');
  const pinsPath = path.join(directory, 'pins.json');
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`);

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      path.join(directory, 'inventory.json'),
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^CONTRIBUTION_SCHEMA_UNSUPPORTED: /);
  assert.match(
    result.stderr,
    /First differing path: schema\.isValidCommand\.branches\[2\]/,
  );
  assert.match(result.stderr, /expected rejecting condition/);
  assert.match(result.stderr, /Remediation:/);
});

test('CLI fails closed on an added command validator branch', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-command-validator-branch-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pins = materializeRepositoryPins(directory);
  const contributionInput = pins.inputs.find(
    (input) => input.kind === 'contributionSchemaSource',
  );
  assert.notEqual(contributionInput, undefined);
  const original = fs.readFileSync(
    path.join(directory, contributionInput.path),
    'utf8',
  );
  const marker =
    "\t\tif (!isValidIcon(command.icon, collector)) {\n" +
    '\t\t\treturn false;\n' +
    '\t\t}\n' +
    '\t\treturn true;';
  const changed = original.replace(
    marker,
    marker.replace(
      '\t\treturn true;',
      '\t\tif (command.experimental) {\n' +
        '\t\t\treturn false;\n' +
        '\t\t}\n' +
        '\t\treturn true;',
    ),
  );
  assert.notEqual(changed, original);
  fs.writeFileSync(path.join(directory, contributionInput.path), changed);
  contributionInput.sha256 = crypto
    .createHash('sha256')
    .update(changed)
    .digest('hex');
  const pinsPath = path.join(directory, 'pins.json');
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`);

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      path.join(directory, 'inventory.json'),
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^CONTRIBUTION_SCHEMA_UNSUPPORTED: /);
  assert.match(
    result.stderr,
    /First differing path: schema\.isValidCommand\.branches\[7\]/,
  );
  assert.match(result.stderr, /unprojected rejecting condition/);
  assert.match(result.stderr, /Remediation:/);
});

test('CLI fails closed when the imported whitespace helper changes', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-whitespace-helper-drift-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pins = materializeRepositoryPins(directory);
  const helperInput = pins.inputs.find(
    (input) => input.kind === 'contributionValidationHelperSource',
  );
  assert.notEqual(
    helperInput,
    undefined,
    'the transitive validation helper must be pinned',
  );
  const original = fs.readFileSync(
    path.join(directory, helperInput.path),
    'utf8',
  );
  const changed = original.replace(
    'return str.trim().length === 0;',
    'return str.trim().length <= 1;',
  );
  assert.notEqual(changed, original);
  fs.writeFileSync(path.join(directory, helperInput.path), changed);
  helperInput.sha256 = crypto
    .createHash('sha256')
    .update(changed)
    .digest('hex');
  const pinsPath = path.join(directory, 'pins.json');
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`);

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      path.join(directory, 'inventory.json'),
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^CONTRIBUTION_SCHEMA_UNSUPPORTED: /);
  assert.match(
    result.stderr,
    /First differing path: validationHelpers\.isFalsyOrWhitespace\.finalReturn/,
  );
  assert.match(result.stderr, /expected str\.trim\(\)\.length === 0/);
  assert.match(result.stderr, /Remediation:/);
});

test('CLI preserves string-literal whitespace in helper comparisons', (context) => {
  const result = runPinnedInputMutation(
    context,
    'flutter-vscode-whitespace-literal-drift-',
    'contributionValidationHelperSource',
    (source) =>
      source.replace("typeof str !== 'string'", "typeof str !== 'str ing'"),
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^CONTRIBUTION_SCHEMA_UNSUPPORTED: /);
  assert.match(
    result.stderr,
    /First differing path: validationHelpers\.isFalsyOrWhitespace\.guard/,
  );
  assert.match(result.stderr, /expected !str/);
});

test('CLI rejects a contribution-local whitespace helper shadow', (context) => {
  const result = runPinnedInputMutation(
    context,
    'flutter-vscode-whitespace-shadow-drift-',
    'contributionSchemaSource',
    (source) =>
      source.replace(
        'namespace schema {',
        'namespace schema {\n' +
          '\tfunction isFalsyOrWhitespace(value: string): boolean {\n' +
          '\t\treturn false;\n' +
          '\t}\n',
      ),
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^CONTRIBUTION_SCHEMA_UNSUPPORTED: /);
  assert.match(
    result.stderr,
    /First differing path: validationHelpers\.isFalsyOrWhitespace\.binding/,
  );
  assert.match(result.stderr, /pinned import/);
});

function runPinnedInputMutation(context, prefix, inputKind, mutate) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const pins = materializeRepositoryPins(directory);
  const input = pins.inputs.find((candidate) => candidate.kind === inputKind);
  assert.notEqual(input, undefined, `${inputKind} must be pinned`);
  const original = fs.readFileSync(path.join(directory, input.path), 'utf8');
  const changed = mutate(original);
  assert.notEqual(changed, original);
  fs.writeFileSync(path.join(directory, input.path), changed);
  input.sha256 = crypto
    .createHash('sha256')
    .update(changed)
    .digest('hex');
  const pinsPath = path.join(directory, 'pins.json');
  fs.writeFileSync(pinsPath, `${JSON.stringify(pins, null, 2)}\n`);

  return spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/cli.cjs'),
      '--pins',
      pinsPath,
      '--output',
      path.join(directory, 'inventory.json'),
    ],
    {encoding: 'utf8'},
  );
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
