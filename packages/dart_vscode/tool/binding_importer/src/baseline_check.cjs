#!/usr/bin/env node

const fs = require('node:fs');
const path = require('node:path');

const {validateBaselineUpdate} = require('./baseline.cjs');

function main(arguments_) {
  const options = parseArguments(arguments_);
  validateBaselineUpdate(
    readJson(options.previous),
    readJson(options.candidate),
    readJson(options.overrides),
  );
}

function parseArguments(arguments_) {
  const options = {};
  for (let index = 0; index < arguments_.length; index += 2) {
    const name = arguments_[index];
    const value = arguments_[index + 1];
    if (
      !['--previous', '--candidate', '--overrides'].includes(name) ||
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
  if (!options.previous || !options.candidate || !options.overrides) {
    throw cliError('INVALID_ARGUMENTS', usage());
  }
  return options;
}

function readJson(filePath) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch (cause) {
    throw cliError('INVALID_BASELINE_INPUT', `Cannot read ${filePath}: ${cause.message}`);
  }
}

function usage() {
  return (
    'Usage: baseline_check.cjs --previous <inventory.json> ' +
    '--candidate <inventory.json> --overrides <overrides.json>'
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
  console.error(`${error.code ?? 'BASELINE_CHECK_FAILED'}: ${error.message}`);
  process.exitCode = 1;
}
