#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const {
  validateBaselineOverrides,
  validateBaselineUpdate,
} = require('./baseline.cjs');

function main(arguments_) {
  const options = parseArguments(arguments_);
  const baselines = discoverBaselines(options.irDirectory);
  if (baselines.length === 0 || baselines[0].version !== options.seed) {
    throw cliError(
      'INVALID_BASELINE_SERIES',
      `The first checked-in baseline must be the explicit seed ${options.seed}.`,
    );
  }
  validateOverrideFiles(options.overridesDirectory, baselines);

  const seed = baselines[0];
  try {
    const seedOverrides = readJson(
      path.join(options.overridesDirectory, `vscode-${seed.version}.json`),
    );
    validateOverrideVersion(seed.version, seedOverrides);
    validateBaselineOverrides(readJson(seed.path), seedOverrides);
  } catch (error) {
    error.message = `${seed.version} seed: ${error.message}`;
    throw error;
  }

  for (let index = 1; index < baselines.length; index += 1) {
    const previous = baselines[index - 1];
    const candidate = baselines[index];
    const overridePath = path.join(
      options.overridesDirectory,
      `vscode-${candidate.version}.json`,
    );
    try {
      const candidateOverrides = readJson(overridePath);
      validateOverrideVersion(candidate.version, candidateOverrides);
      validateBaselineUpdate(
        readJson(previous.path),
        readJson(candidate.path),
        candidateOverrides,
      );
    } catch (error) {
      error.message = `${previous.version} -> ${candidate.version}: ${error.message}`;
      throw error;
    }
  }
}

function validateOverrideFiles(directory, baselines) {
  let names;
  try {
    names = fs.readdirSync(directory);
  } catch (cause) {
    throw cliError(
      'INVALID_BASELINE_SERIES',
      `Cannot read override directory ${directory}: ${cause.message}`,
    );
  }
  const baselineVersions = new Set(baselines.map((baseline) => baseline.version));
  const orphanVersions = names
    .filter((name) => name.startsWith('vscode-') && name.endsWith('.json'))
    .map((name) => {
      const match = /^vscode-(\d+)\.(\d+)\.(\d+)\.json$/.exec(name);
      if (match === null) {
        throw cliError(
          'INVALID_BASELINE_SERIES',
          `Override filename ${name} must use vscode-MAJOR.MINOR.PATCH.json.`,
        );
      }
      return `${match[1]}.${match[2]}.${match[3]}`;
    })
    .filter((version) => !baselineVersions.has(version))
    .sort();
  if (orphanVersions.length > 0) {
    throw cliError(
      'INVALID_BASELINE_SERIES',
      orphanVersions
        .map((version) => `Semantic override ${version} has no matching baseline.`)
        .join('\n'),
    );
  }
}

function validateOverrideVersion(expectedVersion, overrides) {
  if (overrides.vscodeVersion === expectedVersion) {
    return;
  }
  throw cliError(
    'INVALID_BASELINE_SERIES',
    'Semantic Override version mismatch: expected ' +
      `${expectedVersion}, found ${String(overrides.vscodeVersion)}.`,
  );
}

function discoverBaselines(directory) {
  let names;
  try {
    names = fs.readdirSync(directory);
  } catch (cause) {
    throw cliError(
      'INVALID_BASELINE_SERIES',
      `Cannot read baseline directory ${directory}: ${cause.message}`,
    );
  }
  return names
    .filter((name) => name.startsWith('vscode-') && name.endsWith('.json'))
    .map((name) => {
      const match = /^vscode-(\d+)\.(\d+)\.(\d+)\.json$/.exec(name);
      if (match === null) {
        throw cliError(
          'INVALID_BASELINE_SERIES',
          `Baseline filename ${name} must use vscode-MAJOR.MINOR.PATCH.json.`,
        );
      }
      return {
        path: path.join(directory, name),
        version: `${match[1]}.${match[2]}.${match[3]}`,
        versionParts: match.slice(1).map(Number),
      };
    })
    .sort((left, right) =>
      compareVersionParts(left.versionParts, right.versionParts),
    );
}

function compareVersionParts(left, right) {
  for (let index = 0; index < left.length; index += 1) {
    if (left[index] !== right[index]) {
      return left[index] - right[index];
    }
  }
  return 0;
}

function parseArguments(arguments_) {
  const options = {};
  for (let index = 0; index < arguments_.length; index += 2) {
    const name = arguments_[index];
    const value = arguments_[index + 1];
    if (
      !['--ir-directory', '--overrides-directory', '--seed'].includes(name) ||
      value === undefined
    ) {
      throw cliError('INVALID_ARGUMENTS', usage());
    }
    const key = name
      .slice(2)
      .replaceAll(/-([a-z])/g, (_, letter) => letter.toUpperCase());
    if (options[key] !== undefined) {
      throw cliError('INVALID_ARGUMENTS', `Duplicate argument ${name}.`);
    }
    options[key] = name === '--seed' ? value : path.resolve(value);
  }
  if (!options.irDirectory || !options.overridesDirectory || !options.seed) {
    throw cliError('INVALID_ARGUMENTS', usage());
  }
  return options;
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (cause) {
    throw cliError(
      'INVALID_BASELINE_INPUT',
      `Cannot read ${filePath}: ${cause.message}`,
    );
  }
}

function usage() {
  return (
    'Usage: baseline_series_check.cjs --ir-directory <directory> ' +
    '--overrides-directory <directory> --seed <MAJOR.MINOR.PATCH>'
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
  console.error(
    `${error.code ?? 'BASELINE_SERIES_CHECK_FAILED'}: ${error.message}`,
  );
  process.exitCode = 1;
}
