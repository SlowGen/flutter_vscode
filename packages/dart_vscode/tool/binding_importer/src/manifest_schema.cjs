const ts = require('typescript');

const manifestSchemaUri = 'vscode://schemas/vscode-extensions';

function extractManifestSchemaProjection(source, fileName) {
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

  const schemaId = findVariableInitializer(sourceFile, 'schemaId', fileName);
  const schemaUri = expectStringLiteral(schemaId, fileName, 'schemaId');
  if (schemaUri !== manifestSchemaUri) {
    unsupported(fileName, 'schemaId', `expected ${manifestSchemaUri}`);
  }

  const schema = expectObjectLiteral(
    findVariableInitializer(sourceFile, 'schema', fileName),
    fileName,
    'schema',
  );
  expectOnlyObjectProperties(schema, new Set(['properties']), fileName, 'schema');
  const properties = expectObjectProperty(
    schema,
    'properties',
    fileName,
    'schema.properties',
  );

  const engines = schemaProperty(properties, 'engines', fileName);
  const enginesProperties = expectObjectProperty(
    engines,
    'properties',
    fileName,
    'engines.properties',
  );
  const vscodeEngine = schemaProperty(
    enginesProperties,
    'vscode',
    fileName,
    'engines.properties',
  );
  const activationEvents = schemaProperty(
    properties,
    'activationEvents',
    fileName,
  );
  const activationEventItems = expectObjectProperty(
    activationEvents,
    'items',
    fileName,
    'activationEvents.items',
  );
  const contributes = schemaProperty(properties, 'contributes', fileName);
  const contributionProperties = expectObjectProperty(
    contributes,
    'properties',
    fileName,
    'contributes.properties',
  );
  if (contributionProperties.properties.length !== 0) {
    unsupported(
      fileName,
      'contributes.properties',
      'expected an empty overlay populated by contribution-point schemas',
    );
  }

  return {
    schemaUri,
    standalone: false,
    properties: {
      activationEvents: {
        type: expectSchemaType(
          activationEvents,
          'array',
          fileName,
          'activationEvents.type',
        ),
        items: {
          type: expectSchemaType(
            activationEventItems,
            'string',
            fileName,
            'activationEvents.items.type',
          ),
        },
      },
      contributes: {
        type: expectSchemaType(
          contributes,
          'object',
          fileName,
          'contributes.type',
        ),
      },
      displayName: {
        type: expectSchemaType(
          schemaProperty(properties, 'displayName', fileName),
          'string',
          fileName,
          'displayName.type',
        ),
      },
      engines: {
        type: expectSchemaType(
          engines,
          'object',
          fileName,
          'engines.type',
        ),
        properties: {
          vscode: {
            type: expectSchemaType(
              vscodeEngine,
              'string',
              fileName,
              'engines.properties.vscode.type',
            ),
          },
        },
      },
      publisher: {
        type: expectSchemaType(
          schemaProperty(properties, 'publisher', fileName),
          'string',
          fileName,
          'publisher.type',
        ),
      },
    },
  };
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
  if (matches.length !== 1 || !matches[0].initializer) {
    unsupported(fileName, name, 'expected exactly one initialized declaration');
  }
  return matches[0].initializer;
}

function schemaProperty(properties, name, fileName, parentPath = '') {
  const path = parentPath ? `${parentPath}.${name}` : name;
  return expectObjectProperty(properties, name, fileName, path);
}

function expectObjectProperty(object, name, fileName, path) {
  const matches = object.properties.filter(
    (property) =>
      ts.isPropertyAssignment(property) && propertyName(property.name) === name,
  );
  if (matches.length !== 1) {
    unsupported(fileName, path, 'expected exactly one object property');
  }
  return expectObjectLiteral(matches[0].initializer, fileName, path);
}

function expectOnlyObjectProperties(object, allowed, fileName, path) {
  for (const property of object.properties) {
    if (!ts.isPropertyAssignment(property)) {
      unsupported(
        fileName,
        path,
        `unsupported ${ts.SyntaxKind[property.kind]} member`,
      );
    }
    const name = propertyName(property.name);
    if (name === undefined || !allowed.has(name)) {
      unsupported(
        fileName,
        `${path}.${name ?? ts.SyntaxKind[property.name.kind]}`,
        'unprojected schema property',
      );
    }
  }
}

function expectSchemaType(object, expected, fileName, path) {
  const matches = object.properties.filter(
    (property) =>
      ts.isPropertyAssignment(property) && propertyName(property.name) === 'type',
  );
  if (matches.length !== 1) {
    unsupported(fileName, path, 'expected exactly one string literal');
  }
  const actual = expectStringLiteral(matches[0].initializer, fileName, path);
  if (actual !== expected) {
    unsupported(fileName, path, `expected ${expected}, found ${actual}`);
  }
  return actual;
}

function expectObjectLiteral(expression, fileName, path) {
  const unwrapped = unwrapExpression(expression);
  if (!ts.isObjectLiteralExpression(unwrapped)) {
    unsupported(fileName, path, 'expected an object literal');
  }
  return unwrapped;
}

function expectStringLiteral(expression, fileName, path) {
  const unwrapped = unwrapExpression(expression);
  if (!ts.isStringLiteral(unwrapped) && !ts.isNoSubstitutionTemplateLiteral(unwrapped)) {
    unsupported(fileName, path, 'expected a string literal');
  }
  return unwrapped.text;
}

function unwrapExpression(expression) {
  let current = expression;
  while (
    ts.isParenthesizedExpression(current) ||
    ts.isAsExpression(current) ||
    ts.isTypeAssertionExpression(current) ||
    ts.isSatisfiesExpression(current) ||
    ts.isNonNullExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function propertyName(name) {
  if (
    ts.isIdentifier(name) ||
    ts.isStringLiteral(name) ||
    ts.isNumericLiteral(name)
  ) {
    return name.text;
  }
  return undefined;
}

function unsupported(fileName, path, detail) {
  const error = new Error(
    `Unsupported manifest schema in ${fileName} at ${path}: ${detail}.`,
  );
  error.code = 'MANIFEST_SCHEMA_UNSUPPORTED';
  throw error;
}

module.exports = {extractManifestSchemaProjection};
