const crypto = require('node:crypto');
const ts = require('typescript');

function extractManifestValidatorProjection(source, fileName) {
  const sourceFile = ts.createSourceFile(
    fileName,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  if (sourceFile.parseDiagnostics.length > 0) {
    const diagnostic = sourceFile.parseDiagnostics[0];
    unsupported(
      fileName,
      '$parse',
      ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
    );
  }

  const validator = findFunction(
    sourceFile,
    'validateExtensionManifest',
    fileName,
  );
  const conditions = [];
  collectIfConditions(validator.body, sourceFile, conditions);
  const requiredPredicates = [
    [
      'publisher',
      "typeofextensionManifest.publisher!=='undefined'&&typeofextensionManifest.publisher!=='string'",
    ],
    ['name', "typeofextensionManifest.name!=='string'"],
    ['version', "typeofextensionManifest.version!=='string'"],
    ['engines', '!extensionManifest.engines'],
    ['engines.vscode', "typeofextensionManifest.engines.vscode!=='string'"],
    [
      'activationEvents.type',
      '!isStringArray(extensionManifest.activationEvents)',
    ],
    [
      'activationEvents.entrypoint',
      "typeofextensionManifest.main==='undefined'&&typeofextensionManifest.browser==='undefined'",
    ],
    ['main', "typeofextensionManifest.main!=='string'"],
    ['versionPredicate', '!semver.valid(extensionManifest.version)'],
  ];
  for (const [path, predicate] of requiredPredicates) {
    const matches = conditions.filter((condition) => condition === predicate);
    if (matches.length !== 1) {
      unsupported(
        fileName,
        `validateExtensionManifest.${path}`,
        `expected exactly one recognized predicate, found ${matches.length}`,
      );
    }
  }

  const versionExpression = findVariableInitializer(
    sourceFile,
    'VERSION_REGEXP',
    fileName,
  );
  if (!ts.isRegularExpressionLiteral(versionExpression)) {
    unsupported(fileName, 'VERSION_REGEXP', 'expected a regular expression literal');
  }
  const literal = versionExpression.getText(sourceFile);
  const match = /^\/(.*)\/([a-z]*)$/.exec(literal);
  if (match === null) {
    unsupported(fileName, 'VERSION_REGEXP', 'cannot split source and flags');
  }

  return {
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
    engineVersionSyntax: {source: match[1], flags: match[2]},
    validatorBodySha256: crypto
      .createHash('sha256')
      .update(validator.body.getText(sourceFile))
      .digest('hex'),
    projectionLimits: {
      remainingValidatorBranches:
        'integrityPinnedByValidatorBodySha256',
      semverValidImplementation: 'unprojectedExternal',
    },
  };
}

function findFunction(sourceFile, name, fileName) {
  const matches = sourceFile.statements.filter(
    (statement) =>
      ts.isFunctionDeclaration(statement) && statement.name?.text === name,
  );
  if (matches.length !== 1 || matches[0].body === undefined) {
    unsupported(fileName, name, 'expected exactly one function body');
  }
  return matches[0];
}

function findVariableInitializer(sourceFile, name, fileName) {
  const matches = [];
  for (const statement of sourceFile.statements) {
    if (!ts.isVariableStatement(statement)) {
      continue;
    }
    for (const declaration of statement.declarationList.declarations) {
      if (ts.isIdentifier(declaration.name) && declaration.name.text === name) {
        matches.push(declaration);
      }
    }
  }
  if (matches.length !== 1 || matches[0].initializer === undefined) {
    unsupported(fileName, name, 'expected exactly one initialized declaration');
  }
  return matches[0].initializer;
}

function collectIfConditions(node, sourceFile, output) {
  if (ts.isIfStatement(node)) {
    output.push(node.expression.getText(sourceFile).replace(/\s+/g, ''));
  }
  ts.forEachChild(node, (child) =>
    collectIfConditions(child, sourceFile, output),
  );
}

function unsupported(fileName, path, detail) {
  const error = new Error(
    `Unsupported manifest validator in ${fileName} at ${path}: ${detail}.`,
  );
  error.code = 'MANIFEST_VALIDATOR_UNSUPPORTED';
  throw error;
}

module.exports = {extractManifestValidatorProjection};
