const ts = require('typescript');
const {helpers} = require('./contribution_schema.cjs');

const {
  collectIfStatements,
  compareOrdinal,
  expectArrayProperty,
  expectIdentifier,
  expectObjectLiteral,
  expectOnlyObjectProperties,
  expectPropertyInitializer,
  expectStringLiteral,
  expectStringProperty,
  findVariableInitializer,
  hasProperty,
  normalizedExpressionText,
  propertyName,
  unsupported,
  unwrapExpression,
} = helpers;

// Keys that carry only editor affordance -- descriptions, defaults, snippet
// bodies -- and can never change what a manifest is allowed to contain.
// They are discarded exactly the way the commands projection discards its
// localize() descriptions.
const DISCARDED_KEYS = new Set([
  'comment',
  'default',
  'defaultSnippets',
  'deprecationMessage',
  'description',
  'enumDescriptions',
  'enumItemLabels',
  'markdownDeprecationMessage',
  'markdownDescription',
  'markdownEnumDescriptions',
  'patternErrorMessage',
  'title',
  'additionalItems',
  'keywords',
]);

const STRUCTURAL_KEYS = new Set([
  'additionalProperties',
  'anyOf',
  'enum',
  'items',
  'pattern',
  'properties',
  'propertyNames',
  'required',
  'type',
  '$ref',
]);

/// Normalizes one pinned IJSONSchema literal into the structural projection,
/// failing closed on any construct it cannot prove it understands.
/// [resolve] maps an identifier name to an already-normalized schema, so
/// literals may reference sibling consts the way viewsContribution
/// references viewDescriptor.
function normalizeSchema(object, fileName, path, resolve) {
  const output = {};
  for (const property of object.properties) {
    if (!ts.isPropertyAssignment(property)) {
      unsupported(
        fileName,
        path,
        `unsupported ${ts.SyntaxKind[property.kind]} member`,
      );
    }
    const name = propertyName(property.name);
    if (name === undefined) {
      unsupported(fileName, path, 'unsupported property name');
    }
    if (DISCARDED_KEYS.has(name)) {
      continue;
    }
    if (!STRUCTURAL_KEYS.has(name)) {
      unsupported(fileName, `${path}.${name}`, 'unsupported schema keyword');
    }
  }

  const read = (name) =>
    unwrapExpression(
      expectPropertyInitializer(object, name, fileName, `${path}.${name}`),
    );

  if (hasProperty(object, 'type')) {
    const initializer = read('type');
    if (ts.isArrayLiteralExpression(initializer)) {
      output.type = initializer.elements.map((element, index) =>
        expectStringLiteral(element, fileName, `${path}.type[${index}]`),
      );
    } else {
      output.type = expectStringLiteral(initializer, fileName, `${path}.type`);
    }
  }
  if (hasProperty(object, '$ref')) {
    output.$ref = expectStringLiteral(read('$ref'), fileName, `${path}.$ref`);
  }
  if (hasProperty(object, 'pattern')) {
    output.pattern = expectStringLiteral(
      read('pattern'),
      fileName,
      `${path}.pattern`,
    );
  }
  if (hasProperty(object, 'enum')) {
    output.enum = expectArrayProperty(
      object,
      'enum',
      fileName,
      `${path}.enum`,
    ).elements.map((element, index) =>
      expectStringLiteral(element, fileName, `${path}.enum[${index}]`),
    );
  }
  if (hasProperty(object, 'required')) {
    const required = expectArrayProperty(
      object,
      'required',
      fileName,
      `${path}.required`,
    ).elements.map((element, index) =>
      expectStringLiteral(element, fileName, `${path}.required[${index}]`),
    );
    if (new Set(required).size !== required.length) {
      unsupported(fileName, `${path}.required`, 'contains duplicate names');
    }
    output.required = required;
  }
  if (hasProperty(object, 'items')) {
    const initializer = read('items');
    if (ts.isIdentifier(initializer)) {
      output.items = resolve(initializer.text, `${path}.items`);
    } else {
      output.items = normalizeSchema(
        expectObjectLiteral(initializer, fileName, `${path}.items`),
        fileName,
        `${path}.items`,
        resolve,
      );
    }
  }
  if (hasProperty(object, 'propertyNames')) {
    output.propertyNames = normalizeSchema(
      expectObjectLiteral(
        read('propertyNames'),
        fileName,
        `${path}.propertyNames`,
      ),
      fileName,
      `${path}.propertyNames`,
      resolve,
    );
  }
  if (hasProperty(object, 'additionalProperties')) {
    const initializer = read('additionalProperties');
    if (initializer.kind === ts.SyntaxKind.FalseKeyword) {
      output.additionalProperties = false;
    } else if (ts.isIdentifier(initializer)) {
      output.additionalProperties = resolve(
        initializer.text,
        `${path}.additionalProperties`,
      );
    } else {
      output.additionalProperties = normalizeSchema(
        expectObjectLiteral(
          initializer,
          fileName,
          `${path}.additionalProperties`,
        ),
        fileName,
        `${path}.additionalProperties`,
        resolve,
      );
    }
  }
  if (hasProperty(object, 'anyOf')) {
    output.anyOf = expectArrayProperty(
      object,
      'anyOf',
      fileName,
      `${path}.anyOf`,
    ).elements.map((element, index) =>
      normalizeSchema(
        expectObjectLiteral(element, fileName, `${path}.anyOf[${index}]`),
        fileName,
        `${path}.anyOf[${index}]`,
        resolve,
      ),
    );
  }
  if (hasProperty(object, 'properties')) {
    const properties = expectObjectLiteral(
      read('properties'),
      fileName,
      `${path}.properties`,
    );
    const entries = [];
    for (const property of properties.properties) {
      if (!ts.isPropertyAssignment(property)) {
        unsupported(
          fileName,
          `${path}.properties`,
          `unsupported ${ts.SyntaxKind[property.kind]} member`,
        );
      }
      const name = propertyName(property.name);
      if (name === undefined) {
        unsupported(
          fileName,
          `${path}.properties`,
          'unsupported property name',
        );
      }
      entries.push([name, property.initializer]);
    }
    entries.sort(([left], [right]) => compareOrdinal(left, right));
    const normalized = {};
    for (const [name, initializer] of entries) {
      if (Object.hasOwn(normalized, name)) {
        unsupported(
          fileName,
          `${path}.properties.${name}`,
          'duplicate property',
        );
      }
      normalized[name] = normalizeSchema(
        expectObjectLiteral(
          unwrapExpression(initializer),
          fileName,
          `${path}.properties.${name}`,
        ),
        fileName,
        `${path}.properties.${name}`,
        resolve,
      );
    }
    output.properties = normalized;
  }
  // An empty projection is legal here, unlike the commands normalizer: the
  // pinned configuration schema deliberately contains
  // constraint-free leaves ("default" under agentsWindow), and an empty
  // schema accepts anything -- which is exactly what those leaves mean.
  return output;
}

/// Every ExtensionsRegistry.registerExtensionPoint call in the file, keyed
/// by its extensionPoint string, with the registration literal.
function collectRegistrations(sourceFile, fileName) {
  const registrations = new Map();
  const visit = (node) => {
    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      node.expression.name.text === 'registerExtensionPoint' &&
      ts.isIdentifier(node.expression.expression) &&
      node.expression.expression.text === 'ExtensionsRegistry'
    ) {
      if (node.arguments.length !== 1) {
        unsupported(fileName, 'registerExtensionPoint', 'unexpected arity');
      }
      const literal = expectObjectLiteral(
        unwrapExpression(node.arguments[0]),
        fileName,
        'registerExtensionPoint',
      );
      const point = expectStringLiteral(
        expectPropertyInitializer(
          literal,
          'extensionPoint',
          fileName,
          'registerExtensionPoint.extensionPoint',
        ),
        fileName,
        'registerExtensionPoint.extensionPoint',
      );
      if (registrations.has(point)) {
        unsupported(fileName, `registerExtensionPoint.${point}`, 'duplicate');
      }
      registrations.set(point, literal);
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  return registrations;
}

/// The named method of the named class, or fail closed.
function findClassMethod(sourceFile, methodName, fileName) {
  let found;
  const visit = (node) => {
    if (
      ts.isMethodDeclaration(node) &&
      ts.isIdentifier(node.name) &&
      node.name.text === methodName
    ) {
      if (found !== undefined) {
        unsupported(fileName, methodName, 'declared more than once');
      }
      found = node;
    }
    ts.forEachChild(node, visit);
  };
  visit(sourceFile);
  if (found === undefined) {
    unsupported(fileName, methodName, 'validator method not found');
  }
  return found;
}

/// Asserts the validator's if-conditions match [expected] exactly, in order,
/// so a semantic change upstream fails the import instead of silently
/// changing what a valid manifest means.
function expectValidatorConditions(method, expected, fileName, path) {
  const conditions = collectIfStatements(method.body).map((statement) =>
    normalizedExpressionText(statement.expression),
  );
  if (
    conditions.length !== expected.length ||
    conditions.some((condition, index) => condition !== expected[index])
  ) {
    unsupported(
      fileName,
      path,
      `validator branches changed: ${JSON.stringify(conditions)}`,
    );
  }
}

function parseSource(source, fileName) {
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
  return sourceFile;
}

/// Extracts the views and viewsContainers contribution projections from the
/// pinned viewsExtensionPoint.ts.
function extractViewsContributionProjections(source, fileName) {
  const sourceFile = parseSource(source, fileName);
  const statements = [...sourceFile.statements];

  const normalizedByName = new Map();
  const resolve = (name, path) => {
    if (!normalizedByName.has(name)) {
      unsupported(fileName, path, `unresolved schema identifier ${name}`);
    }
    return normalizedByName.get(name);
  };
  for (const name of [
    'viewsContainerSchema',
    'viewDescriptor',
    'remoteViewDescriptor',
  ]) {
    normalizedByName.set(
      name,
      normalizeSchema(
        expectObjectLiteral(
          unwrapExpression(findVariableInitializer(statements, name, fileName)),
          fileName,
          `schema.${name}`,
        ),
        fileName,
        `schema.${name}`,
        resolve,
      ),
    );
  }

  const containers = normalizeSchema(
    expectObjectLiteral(
      unwrapExpression(
        findVariableInitializer(statements, 'viewsContainersContribution', fileName),
      ),
      fileName,
      'schema.viewsContainersContribution',
    ),
    fileName,
    'schema.viewsContainersContribution',
    resolve,
  );
  const views = normalizeSchema(
    expectObjectLiteral(
      unwrapExpression(
        findVariableInitializer(statements, 'viewsContribution', fileName),
      ),
      fileName,
      'schema.viewsContribution',
    ),
    fileName,
    'schema.viewsContribution',
    resolve,
  );

  const registrations = collectRegistrations(sourceFile, fileName);
  const points = [...registrations.keys()].sort();
  if (points.join(',') !== 'views,viewsContainers') {
    unsupported(fileName, 'registerExtensionPoint', `found ${points}`);
  }
  expectIdentifier(
    expectPropertyInitializer(
      registrations.get('viewsContainers'),
      'jsonSchema',
      fileName,
      'registerExtensionPoint.viewsContainers.jsonSchema',
    ),
    'viewsContainersContribution',
    fileName,
    'registerExtensionPoint.viewsContainers.jsonSchema',
  );
  expectIdentifier(
    expectPropertyInitializer(
      registrations.get('views'),
      'jsonSchema',
      fileName,
      'registerExtensionPoint.views.jsonSchema',
    ),
    'viewsContribution',
    fileName,
    'registerExtensionPoint.views.jsonSchema',
  );

  // The runtime validators, branch for branch. A change here upstream is a
  // change to what VS Code accepts, and must be reviewed, not absorbed.
  expectValidatorConditions(
    findClassMethod(sourceFile, 'isValidViewsContainer', fileName),
    [
      '!Array.isArray(viewsContainersDescriptors)',
      "typeofdescriptor.id!=='string'&&isFalsyOrWhitespace(descriptor.id)",
      '!(/^[a-z0-9_-]+$/i.test(descriptor.id))',
      "typeofdescriptor.title!=='string'",
      "typeofdescriptor.icon!=='string'",
      'isFalsyOrWhitespace(descriptor.title)',
    ],
    fileName,
    'schema.isValidViewsContainer',
  );
  expectValidatorConditions(
    findClassMethod(sourceFile, 'isValidViewDescriptors', fileName),
    [
      '!Array.isArray(viewDescriptors)',
      "typeofdescriptor.id!=='string'",
      "typeofdescriptor.name!=='string'",
      "descriptor.when&&typeofdescriptor.when!=='string'",
      "descriptor.icon&&typeofdescriptor.icon!=='string'",
      'descriptor.contextualTitle&&' +
        "typeofdescriptor.contextualTitle!=='string'",
      'descriptor.visibility&&' +
        '!this.convertInitialVisibility(descriptor.visibility)',
    ],
    fileName,
    'schema.isValidViewDescriptors',
  );

  // The pinned literals repeat one item schema per location; the projection
  // carries it once, after proving every location really does share it.
  const deepEqual = (left, right) =>
    JSON.stringify(left) === JSON.stringify(right);
  const containerItem = normalizedByName.get('viewsContainerSchema');
  const containerLocations = Object.keys(containers.properties ?? {}).sort();
  if (containers.additionalProperties !== false) {
    unsupported(
      fileName,
      'schema.viewsContainersContribution.additionalProperties',
      'expected a closed location set',
    );
  }
  for (const location of containerLocations) {
    const entry = containers.properties[location];
    if (entry.type !== 'array' || !deepEqual(entry.items, containerItem)) {
      unsupported(
        fileName,
        `schema.viewsContainersContribution.properties.${location}`,
        'expected an array of the shared container schema',
      );
    }
  }
  const viewItem = normalizedByName.get('viewDescriptor');
  const remoteItem = normalizedByName.get('remoteViewDescriptor');
  const viewLocations = [];
  const remoteLocations = [];
  for (const location of Object.keys(views.properties ?? {}).sort()) {
    const entry = views.properties[location];
    if (entry.type !== 'array') {
      unsupported(
        fileName,
        `schema.viewsContribution.properties.${location}`,
        'expected an array of view descriptors',
      );
    }
    if (deepEqual(entry.items, viewItem)) {
      viewLocations.push(location);
    } else if (deepEqual(entry.items, remoteItem)) {
      remoteLocations.push(location);
    } else {
      unsupported(
        fileName,
        `schema.viewsContribution.properties.${location}`,
        'items match neither shared view descriptor',
      );
    }
  }
  const additional = views.additionalProperties;
  if (
    additional === false ||
    additional.type !== 'array' ||
    !deepEqual(additional.items, viewItem)
  ) {
    unsupported(
      fileName,
      'schema.viewsContribution.additionalProperties',
      'expected contributed containers to accept the shared view descriptor',
    );
  }

  return [
    {
      extensionPoint: 'viewsContainers',
      accepts: ['object'],
      locations: containerLocations,
      itemSchema: containerItem,
      validation: {
        whitespacePredicate: 'ecmascript-trim-empty',
        // The schema pattern is ^[a-zA-Z0-9_-]+$; the runtime regex is the
        // same character class, case-insensitively. One rule.
        idPattern: '^[a-zA-Z0-9_-]+$',
        requiredStringProperties: ['id', 'title', 'icon'],
        nonWhitespaceStringProperties: ['id'],
        // A whitespace-only title is a warning upstream, not an error; the
        // projection records that so the build does not become stricter
        // than the platform it is projecting.
        whitespaceWarningProperties: ['title'],
      },
    },
    {
      extensionPoint: 'views',
      accepts: ['object'],
      locations: viewLocations,
      remoteLocations,
      additionalLocations: true,
      itemSchema: viewItem,
      remoteItemSchema: remoteItem,
      validation: {
        requiredStringProperties: ['id', 'name'],
        optionalStringProperties: ['when', 'icon', 'contextualTitle'],
        visibilityEnum: ['visible', 'hidden', 'collapsed'],
      },
    },
  ];
}

/// Extracts the configuration contribution projection from the pinned
/// configurationExtensionPoint.ts.
function extractConfigurationContributionProjection(source, fileName) {
  const sourceFile = parseSource(source, fileName);
  const statements = [...sourceFile.statements];
  const resolve = (name, path) => {
    unsupported(fileName, path, `unresolved schema identifier ${name}`);
  };

  const entrySchema = normalizeSchema(
    expectObjectLiteral(
      unwrapExpression(
        findVariableInitializer(statements, 'configurationEntrySchema', fileName),
      ),
      fileName,
      'schema.configurationEntrySchema',
    ),
    fileName,
    'schema.configurationEntrySchema',
    resolve,
  );

  // The pinned schema accepts any draft-07 schema as a property value: the
  // first anyOf branch is a bare $ref to the draft. Everything else in that
  // anyOf is settings-editor affordance that cannot reject anything the
  // $ref branch accepts, so the projection collapses additionalProperties
  // to "any object" -- after proving the $ref anchor is still there.
  const additional =
    entrySchema.properties?.properties?.additionalProperties;
  if (
    additional?.anyOf?.[0]?.$ref !== 'http://json-schema.org/draft-07/schema#'
  ) {
    unsupported(
      fileName,
      'schema.configurationEntrySchema.properties.properties' +
        '.additionalProperties',
      'the draft-07 $ref anchor moved; review the projection',
    );
  }
  entrySchema.properties.properties.additionalProperties = {};

  const registrations = collectRegistrations(sourceFile, fileName);
  const points = [...registrations.keys()].sort();
  if (points.join(',') !== 'configuration,configurationDefaults') {
    unsupported(fileName, 'registerExtensionPoint', `found ${points}`);
  }
  const registration = registrations.get('configuration');
  const jsonSchema = expectObjectLiteral(
    expectPropertyInitializer(
      registration,
      'jsonSchema',
      fileName,
      'registerExtensionPoint.configuration.jsonSchema',
    ),
    fileName,
    'registerExtensionPoint.configuration.jsonSchema',
  );
  const oneOf = expectArrayProperty(
    jsonSchema,
    'oneOf',
    fileName,
    'registerExtensionPoint.configuration.jsonSchema.oneOf',
  );
  if (oneOf.elements.length !== 2) {
    unsupported(
      fileName,
      'registerExtensionPoint.configuration.jsonSchema.oneOf',
      'expected the object and array forms',
    );
  }
  expectIdentifier(
    oneOf.elements[0],
    'configurationEntrySchema',
    fileName,
    'registerExtensionPoint.configuration.jsonSchema.oneOf[0]',
  );
  const arrayForm = expectObjectLiteral(
    oneOf.elements[1],
    fileName,
    'registerExtensionPoint.configuration.jsonSchema.oneOf[1]',
  );
  expectStringProperty(
    arrayForm,
    'type',
    'array',
    fileName,
    'registerExtensionPoint.configuration.jsonSchema.oneOf[1].type',
  );
  expectIdentifier(
    expectPropertyInitializer(
      arrayForm,
      'items',
      fileName,
      'registerExtensionPoint.configuration.jsonSchema.oneOf[1].items',
    ),
    'configurationEntrySchema',
    fileName,
    'registerExtensionPoint.configuration.jsonSchema.oneOf[1].items',
  );

  return [
    {
      extensionPoint: 'configuration',
      accepts: ['object', 'array'],
      entrySchema,
      validation: {
        propertyNamePattern: '\\S+',
        titleType: 'string',
      },
    },
  ];
}

module.exports = {
  extractViewsContributionProjections,
  extractConfigurationContributionProjection,
};
