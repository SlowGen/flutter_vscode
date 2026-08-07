const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

const officialSourcePathByKind = new Map([
  ['apiDeclarations', 'src/vscode-dts/vscode.d.ts'],
  [
    'contributionSchemaSource',
    'src/vs/workbench/services/actions/common/menusExtensionPoint.ts',
  ],
  ['contributionValidationHelperSource', 'src/vs/base/common/strings.ts'],
  [
    'viewsContributionSchemaSource',
    'src/vs/workbench/api/browser/viewsExtensionPoint.ts',
  ],
  [
    'configurationContributionSchemaSource',
    'src/vs/workbench/api/common/configurationExtensionPoint.ts',
  ],
  [
    'extensionManifestSchemaSource',
    'src/vs/workbench/services/extensions/common/extensionsRegistry.ts',
  ],
  [
    'extensionManifestValidatorSource',
    'src/vs/platform/extensions/common/extensionValidator.ts',
  ],
  ['license', 'LICENSE.txt'],
]);

function verifyPinnedInputs(manifestPath) {
  const manifest = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const directory = path.dirname(manifestPath);

  if (manifest.schemaVersion !== 1 || !Array.isArray(manifest.inputs)) {
    invalidMetadata('schemaVersion must be 1 and inputs must be an array');
  }
  if (
    typeof manifest.product?.version !== 'string' ||
    manifest.product.version.length === 0 ||
    typeof manifest.product?.commit !== 'string' ||
    manifest.product.commit.length === 0
  ) {
    invalidMetadata('product version and commit must be non-empty strings');
  }
  if (!/^[a-f0-9]{40}$/.test(manifest.product.commit)) {
    invalidMetadata(
      'product commit must be a 40-character lowercase Git commit',
    );
  }

  const requiredFields = [
    'name',
    'kind',
    'path',
    'version',
    'commit',
    'source',
    'sha256',
    'license',
  ];
  const supportedKinds = new Set(officialSourcePathByKind.keys());
  for (const [index, input] of manifest.inputs.entries()) {
    for (const field of requiredFields) {
      if (typeof input?.[field] !== 'string' || input[field].length === 0) {
        invalidMetadata(`inputs[${index}].${field} must be a non-empty string`);
      }
    }
    if (!supportedKinds.has(input.kind)) {
      invalidMetadata(
        `inputs[${index}].kind is unsupported: ${JSON.stringify(input.kind)}`,
      );
    }
    if (
      input.version !== manifest.product.version ||
      input.commit !== manifest.product.commit
    ) {
      invalidMetadata(
        `inputs[${index}] version and commit must match product ` +
          `${manifest.product.version}@${manifest.product.commit}`,
      );
    }
    if (!/^[a-f0-9]{64}$/.test(input.sha256)) {
      invalidMetadata(`inputs[${index}].sha256 must be lowercase SHA-256`);
    }
    if (
      path.isAbsolute(input.path) ||
      input.path.includes('\\') ||
      path.posix.normalize(input.path) !== input.path ||
      input.path
        .split('/')
        .some(
          (segment) =>
            segment.length === 0 || segment === '.' || segment === '..',
        )
    ) {
      invalidMetadata(
        `inputs[${index}].path must stay inside the pin manifest directory`,
      );
    }
    let source;
    try {
      source = new URL(input.source);
    } catch {
      invalidMetadata(`inputs[${index}].source must be an absolute URL`);
    }
    if (source.protocol !== 'https:') {
      invalidMetadata(`inputs[${index}].source must use HTTPS`);
    }
    const expectedSource =
      `https://raw.githubusercontent.com/microsoft/vscode/` +
      `${manifest.product.commit}/${officialSourcePathByKind.get(input.kind)}`;
    if (input.source !== expectedSource) {
      invalidMetadata(
        `inputs[${index}].source must be the canonical microsoft/vscode ` +
          `source for ${input.kind} at ${manifest.product.commit}: ` +
          expectedSource,
      );
    }
  }

  const realDirectory = fs.realpathSync(directory);
  for (const [index, input] of manifest.inputs.entries()) {
    const inputPath = path.resolve(directory, input.path);
    const realInputPath = fs.realpathSync(inputPath);
    const relativeRealPath = path.relative(realDirectory, realInputPath);
    if (
      relativeRealPath === '' ||
      path.isAbsolute(relativeRealPath) ||
      relativeRealPath === '..' ||
      relativeRealPath.startsWith(`..${path.sep}`)
    ) {
      invalidMetadata(
        `inputs[${index}].path must stay inside the pin manifest directory`,
      );
    }
    const actual = crypto
      .createHash('sha256')
      .update(fs.readFileSync(inputPath))
      .digest('hex');
    if (actual !== input.sha256) {
      const error = new Error(
        `${input.name} checksum mismatch: expected ${input.sha256}, ` +
          `actual ${actual} (${input.path})`,
      );
      error.code = 'PIN_CHECKSUM_MISMATCH';
      throw error;
    }
  }

  for (const kind of officialSourcePathByKind.keys()) {
    const count = manifest.inputs.filter(
      (input) => input.kind === kind,
    ).length;
    if (count !== 1) {
      invalidMetadata(
        `inputs must contain exactly one ${kind} receipt; found ${count}`,
      );
    }
  }
  const expectedSchemas = [
    'commands',
    'configuration',
    'views',
    'viewsContainers',
  ];
  if (
    !Array.isArray(manifest.contributionSchemas) ||
    manifest.contributionSchemas.join(',') !== expectedSchemas.join(',')
  ) {
    invalidMetadata(
      `contributionSchemas must be exactly ${JSON.stringify(expectedSchemas)}`,
    );
  }

  validateExactKeys(
    manifest,
    [
      'schemaVersion',
      'product',
      'parser',
      'manifestSchema',
      'contributionSchemas',
      'inputs',
    ],
    [],
    'pin root',
  );
  validateExactKeys(
    manifest.product,
    ['name', 'version', 'commit'],
    [],
    'product',
  );
  validateExactKeys(
    manifest.parser,
    ['name', 'version'],
    [],
    'parser',
  );
  validateExactKeys(
    manifest.manifestSchema,
    ['schemaUri', 'standalone', 'composition'],
    [],
    'manifestSchema',
  );
  for (const [index, input] of manifest.inputs.entries()) {
    validateExactKeys(
      input,
      requiredFields,
      ['licensePath'],
      `inputs[${index}]`,
    );
  }

  requireNonEmptyString(manifest.product.name, 'product.name');
  if (manifest.parser.name !== 'typescript') {
    invalidMetadata('parser.name must be typescript');
  }
  requireNonEmptyString(manifest.parser.version, 'parser.version');
  requireNonEmptyString(
    manifest.manifestSchema.schemaUri,
    'manifestSchema.schemaUri',
  );
  if (typeof manifest.manifestSchema.standalone !== 'boolean') {
    invalidMetadata('manifestSchema.standalone must be a boolean');
  }
  requireNonEmptyString(
    manifest.manifestSchema.composition,
    'manifestSchema.composition',
  );
  for (const [index, input] of manifest.inputs.entries()) {
    if (Object.hasOwn(input, 'licensePath')) {
      requireNonEmptyString(
        input.licensePath,
        `inputs[${index}].licensePath`,
      );
    }
  }
}

function validateExactKeys(value, requiredKeys, optionalKeys, subject) {
  if (value === null || typeof value !== 'object' || Array.isArray(value)) {
    invalidMetadata(`${subject} must be an object`);
  }
  const actualKeys = new Set(Object.keys(value));
  const allowedKeys = new Set([...requiredKeys, ...optionalKeys]);
  const missing = requiredKeys.filter((key) => !actualKeys.has(key));
  const unexpected = [...actualKeys]
    .filter((key) => !allowedKeys.has(key))
    .sort();
  if (missing.length === 0 && unexpected.length === 0) {
    return;
  }
  const details = [];
  if (missing.length > 0) {
    details.push(`missing ${missing.join(', ')}`);
  }
  if (unexpected.length > 0) {
    details.push(`unexpected ${unexpected.join(', ')}`);
  }
  invalidMetadata(`${subject} has invalid keys: ${details.join('; ')}`);
}

function requireNonEmptyString(value, subject) {
  if (typeof value !== 'string' || value.length === 0) {
    invalidMetadata(`${subject} must be a non-empty string`);
  }
}

function invalidMetadata(detail) {
  const error = new Error(`Invalid pin metadata: ${detail}.`);
  error.code = 'PIN_METADATA_INVALID';
  throw error;
}

module.exports = {verifyPinnedInputs};
