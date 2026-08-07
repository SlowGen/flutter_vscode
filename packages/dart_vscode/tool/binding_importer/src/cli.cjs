#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const ts = require('typescript');

const {importVscodeDeclarations} = require('./importer.cjs');
const {
  extractContributionSchemaProjection,
} = require('./contribution_schema.cjs');
const {
  extractViewsContributionProjections,
  extractConfigurationContributionProjection,
} = require('./view_configuration_schema.cjs');
const {
  extractManifestSchemaProjection,
} = require('./manifest_schema.cjs');
const {
  extractManifestValidatorProjection,
} = require('./manifest_validator.cjs');
const {verifyPinnedInputs} = require('./pins.cjs');

function main(arguments_) {
  const options = parseArguments(arguments_);
  verifyPinnedInputs(options.pins);

  const pinSet = JSON.parse(fs.readFileSync(options.pins, 'utf8'));
  if (pinSet.parser?.name !== 'typescript' || pinSet.parser.version !== ts.version) {
    throw cliError(
      'PARSER_PIN_MISMATCH',
      `Pinned parser ${pinSet.parser?.name}@${pinSet.parser?.version} does ` +
      `not match typescript@${ts.version}.`,
    );
  }
  if (!Array.isArray(pinSet.contributionSchemas)) {
    throw cliError(
      'PIN_METADATA_INVALID',
      'pins.json contributionSchemas must be an array.',
    );
  }
  validateContributionSchemaPins(pinSet.contributionSchemas);
  const apiInputs = pinSet.inputs.filter(
    (input) => input.kind === 'apiDeclarations',
  );
  if (apiInputs.length !== 1) {
    throw cliError(
      'API_INPUT_PIN_INVALID',
      `Expected exactly one apiDeclarations input, found ${apiInputs.length}.`,
    );
  }

  const apiInput = apiInputs[0];
  const inputPath = path.resolve(path.dirname(options.pins), apiInput.path);
  const manifestInputs = pinSet.inputs.filter(
    (input) => input.kind === 'extensionManifestSchemaSource',
  );
  if (manifestInputs.length !== 1) {
    throw cliError(
      'MANIFEST_INPUT_PIN_INVALID',
      'Expected exactly one extensionManifestSchemaSource input, found ' +
        `${manifestInputs.length}.`,
    );
  }
  const manifestInputPath = path.resolve(
    path.dirname(options.pins),
    manifestInputs[0].path,
  );
  const manifestValidatorInputs = pinSet.inputs.filter(
    (input) => input.kind === 'extensionManifestValidatorSource',
  );
  if (manifestValidatorInputs.length !== 1) {
    throw cliError(
      'MANIFEST_VALIDATOR_INPUT_PIN_INVALID',
      'Expected exactly one extensionManifestValidatorSource input, found ' +
        `${manifestValidatorInputs.length}.`,
    );
  }
  const manifestValidatorInputPath = path.resolve(
    path.dirname(options.pins),
    manifestValidatorInputs[0].path,
  );
  const contributionInputs = pinSet.inputs.filter(
    (input) => input.kind === 'contributionSchemaSource',
  );
  const contributionValidationHelperInputs = pinSet.inputs.filter(
    (input) => input.kind === 'contributionValidationHelperSource',
  );
  if (contributionValidationHelperInputs.length !== 1) {
    throw cliError(
      'CONTRIBUTION_SCHEMA_PIN_INVALID',
      'Expected exactly one contributionValidationHelperSource input, found ' +
        `${contributionValidationHelperInputs.length}.`,
    );
  }
  const contributionValidationHelperInput =
    contributionValidationHelperInputs[0];
  const contributionValidationHelperPath = path.resolve(
    path.dirname(options.pins),
    contributionValidationHelperInput.path,
  );
  const contributionSchemas = {};
  const recordProjection = (projection, input) => {
    if (contributionSchemas[projection.extensionPoint] !== undefined) {
      throw cliError(
        'CONTRIBUTION_SCHEMA_PIN_INVALID',
        `Multiple inputs define ${projection.extensionPoint}.`,
      );
    }
    contributionSchemas[projection.extensionPoint] = {
      inputSha256: input.sha256,
      ...projection,
    };
  };
  for (const input of contributionInputs) {
    if (
      input.version !== contributionValidationHelperInput.version ||
      input.commit !== contributionValidationHelperInput.commit
    ) {
      throw cliError(
        'CONTRIBUTION_SCHEMA_PIN_INVALID',
        'Contribution schema and validation helper inputs must use the same ' +
          'version and commit.',
      );
    }
    const contributionPath = path.resolve(
      path.dirname(options.pins),
      input.path,
    );
    recordProjection(
      extractContributionSchemaProjection(
        fs.readFileSync(contributionPath, 'utf8'),
        contributionPath,
        fs.readFileSync(contributionValidationHelperPath, 'utf8'),
        contributionValidationHelperPath,
      ),
      input,
    );
  }
  const schemaSourceExtractors = [
    ['viewsContributionSchemaSource', extractViewsContributionProjections],
    [
      'configurationContributionSchemaSource',
      extractConfigurationContributionProjection,
    ],
  ];
  for (const [kind, extract] of schemaSourceExtractors) {
    const kindInputs = pinSet.inputs.filter((input) => input.kind === kind);
    if (kindInputs.length !== 1) {
      throw cliError(
        'CONTRIBUTION_SCHEMA_PIN_INVALID',
        `Expected exactly one ${kind} input, found ${kindInputs.length}.`,
      );
    }
    const input = kindInputs[0];
    const sourcePath = path.resolve(path.dirname(options.pins), input.path);
    for (const projection of extract(
      fs.readFileSync(sourcePath, 'utf8'),
      sourcePath,
    )) {
      recordProjection(projection, input);
    }
  }
  const extractedContributionNames = Object.keys(contributionSchemas).sort();
  if (!arraysEqual(extractedContributionNames, pinSet.contributionSchemas)) {
    throw cliError(
      'CONTRIBUTION_SCHEMA_PIN_INVALID',
      'Pinned contribution schema names do not match extracted inputs: ' +
        `expected ${JSON.stringify(pinSet.contributionSchemas)}, found ` +
        `${JSON.stringify(extractedContributionNames)}.`,
    );
  }
  const inventory = importVscodeDeclarations(
    fs.readFileSync(inputPath, 'utf8'),
    inputPath,
  );
  const output = {
    schemaVersion: inventory.schemaVersion,
    source: {
      product: pinSet.product,
      parser: pinSet.parser,
      inputSha256: apiInput.sha256,
      manifestSchema: pinSet.manifestSchema,
      inputs: pinSet.inputs,
      contributionSchemas: pinSet.contributionSchemas,
    },
    manifestSchema: {
      inputSha256: manifestInputs[0].sha256,
      ...extractManifestSchemaProjection(
        fs.readFileSync(manifestInputPath, 'utf8'),
        manifestInputPath,
      ),
    },
    manifestValidator: {
      inputSha256: manifestValidatorInputs[0].sha256,
      ...extractManifestValidatorProjection(
        fs.readFileSync(manifestValidatorInputPath, 'utf8'),
        manifestValidatorInputPath,
      ),
    },
    contributionSchemas,
    module: inventory.module,
    declarations: inventory.declarations,
  };

  const serializedOutput = `${JSON.stringify(output, null, 2)}\n`;
  if (options.output !== undefined) {
    fs.mkdirSync(path.dirname(options.output), {recursive: true});
    fs.writeFileSync(options.output, serializedOutput);
    return;
  }

  const checkedInOutput = fs.readFileSync(options.check);
  if (!checkedInOutput.equals(Buffer.from(serializedOutput, 'utf8'))) {
    throw cliError(
      'IR_DRIFT',
      `Checked-in IR ${options.check} does not match freshly generated ` +
        `output. Regenerate it with: node ${JSON.stringify(__filename)} ` +
        `--pins ${JSON.stringify(options.pins)} --output ` +
        JSON.stringify(options.check),
    );
  }
}

function validateContributionSchemaPins(contributionSchemas) {
  const names = new Set();
  for (const [index, name] of contributionSchemas.entries()) {
    if (typeof name !== 'string' || name.length === 0) {
      throw cliError(
        'PIN_METADATA_INVALID',
        `pins.json contributionSchemas[${index}] must be a non-empty string.`,
      );
    }
    if (names.has(name)) {
      throw cliError(
        'PIN_METADATA_INVALID',
        `pins.json contributionSchemas contains duplicate ${name}.`,
      );
    }
    names.add(name);
  }
  const sorted = [...names].sort();
  if (!arraysEqual(sorted, contributionSchemas)) {
    throw cliError(
      'PIN_METADATA_INVALID',
      'pins.json contributionSchemas must be sorted.',
    );
  }
}

function arraysEqual(left, right) {
  return (
    left.length === right.length &&
    left.every((value, index) => value === right[index])
  );
}

function parseArguments(arguments_) {
  const options = {};
  for (let index = 0; index < arguments_.length; index += 2) {
    const name = arguments_[index];
    const value = arguments_[index + 1];
    if (
      (name !== '--pins' && name !== '--output' && name !== '--check') ||
      value === undefined
    ) {
      throw cliError('INVALID_ARGUMENTS', usage());
    }
    const key = name.slice(2);
    if (options[key] !== undefined) {
      throw cliError('INVALID_ARGUMENTS', `Duplicate argument ${name}.`);
    }
    options[key] = path.resolve(value);
  }
  const destinationCount =
    Number(options.output !== undefined) + Number(options.check !== undefined);
  if (!options.pins || destinationCount !== 1) {
    throw cliError('INVALID_ARGUMENTS', usage());
  }
  return options;
}

function usage() {
  return (
    'Usage: cli.cjs --pins <pins.json> ' +
    '(--output <inventory.json> | --check <inventory.json>)'
  );
}

function cliError(code, message) {
  const error = new Error(message);
  error.code = code;
  return error;
}

try {
  main(process.argv.slice(2));
} catch (error) {
  console.error(`${error.code ?? 'IMPORT_FAILED'}: ${error.message}`);
  process.exitCode = 1;
}
