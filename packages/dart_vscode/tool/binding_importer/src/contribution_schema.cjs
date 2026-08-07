const ts = require('typescript');

function extractContributionSchemaProjection(
  source,
  fileName,
  validationHelperSource,
  validationHelperFileName,
) {
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
  const whitespaceHelperImport = validateWhitespaceHelperImport(
    sourceFile,
    fileName,
  );
  validateIsFalsyOrWhitespaceHelper(
    validationHelperSource,
    validationHelperFileName,
  );

  const schemaStatements = findNamespaceStatements(sourceFile, 'schema', fileName);
  validateWhitespaceHelperCallBindings(
    sourceFile,
    schemaStatements,
    whitespaceHelperImport,
    fileName,
  );
  const commandType = expectObjectLiteral(
    findVariableInitializer(schemaStatements, 'commandType', fileName),
    fileName,
    'schema.commandType',
  );
  const commandsContribution = expectObjectLiteral(
    findVariableInitializer(
      schemaStatements,
      'commandsContribution',
      fileName,
    ),
    fileName,
    'schema.commandsContribution',
  );

  expectOnlyObjectProperties(
    commandsContribution,
    new Set(['description', 'oneOf']),
    fileName,
    'schema.commandsContribution',
  );
  const alternatives = expectArrayProperty(
    commandsContribution,
    'oneOf',
    fileName,
    'schema.commandsContribution.oneOf',
  );
  if (alternatives.elements.length !== 2) {
    unsupported(
      fileName,
      'schema.commandsContribution.oneOf',
      'expected the object and array command forms',
    );
  }
  expectIdentifier(
    alternatives.elements[0],
    'commandType',
    fileName,
    'schema.commandsContribution.oneOf[0]',
  );
  const arrayForm = expectObjectLiteral(
    alternatives.elements[1],
    fileName,
    'schema.commandsContribution.oneOf[1]',
  );
  expectOnlyObjectProperties(
    arrayForm,
    new Set(['items', 'type']),
    fileName,
    'schema.commandsContribution.oneOf[1]',
  );
  expectStringProperty(
    arrayForm,
    'type',
    'array',
    fileName,
    'schema.commandsContribution.oneOf[1].type',
  );
  expectIdentifier(
    expectPropertyInitializer(
      arrayForm,
      'items',
      fileName,
      'schema.commandsContribution.oneOf[1].items',
    ),
    'commandType',
    fileName,
    'schema.commandsContribution.oneOf[1].items',
  );

  validateRegistration(sourceFile, fileName);
  const validation = extractCommandValidationProjection(
    schemaStatements,
    fileName,
  );

  return {
    extensionPoint: 'commands',
    accepts: ['object', 'array'],
    itemSchema: normalizeSchemaObject(
      commandType,
      fileName,
      'schema.commandType',
      new Set(['properties', 'required', 'type']),
    ),
    validation,
  };
}

function extractCommandValidationProjection(statements, fileName) {
  const commandValidator = findFunctionDeclaration(
    statements,
    'isValidCommand',
    fileName,
  );
  expectExactValidatorBranches(
    commandValidator,
    [
      '!command',
      'isFalsyOrWhitespace(command.command)',
      "!isValidLocalizedString(command.title,collector,'title')",
      'command.shortTitle&&' +
        "!isValidLocalizedString(command.shortTitle,collector,'shortTitle')",
      "command.enablement&&typeofcommand.enablement!=='string'",
      'command.category&&' +
        "!isValidLocalizedString(command.category,collector,'category')",
      '!isValidIcon(command.icon,collector)',
    ],
    false,
    true,
    3,
    fileName,
    'schema.isValidCommand',
  );
  const commandProperty = expectRejectedPropertyCall(
    commandValidator,
    'isFalsyOrWhitespace',
    'command',
    false,
    fileName,
    'schema.isValidCommand.command',
  );
  const titleProperty = expectRejectedPropertyCall(
    commandValidator,
    'isValidLocalizedString',
    'command',
    true,
    fileName,
    'schema.isValidCommand.title',
  );
  expectRejectedPropertyCall(
    commandValidator,
    'isValidIcon',
    'command',
    true,
    fileName,
    'schema.isValidCommand.icon',
  );

  const localizedStringValidator = findFunctionDeclaration(
    statements,
    'isValidLocalizedString',
    fileName,
  );
  expectExactValidatorBranches(
    localizedStringValidator,
    [
      "typeoflocalized==='undefined'",
      "typeoflocalized==='string'&&isFalsyOrWhitespace(localized)",
      "typeoflocalized!=='string'&&" +
        '(isFalsyOrWhitespace(localized.original)||' +
        'isFalsyOrWhitespace(localized.value))',
    ],
    false,
    true,
    3,
    fileName,
    'schema.isValidLocalizedString',
  );
  expectStringWhitespaceRejection(
    localizedStringValidator,
    fileName,
    'schema.isValidLocalizedString',
  );

  const iconValidator = findFunctionDeclaration(
    statements,
    'isValidIcon',
    fileName,
  );
  expectExactValidatorBranches(
    iconValidator,
    [
      "typeoficon==='undefined'",
      "typeoficon==='string'",
      "typeoficon.dark==='string'&&typeoficon.light==='string'",
    ],
    true,
    false,
    1,
    fileName,
    'schema.isValidIcon',
  );
  const requiredIconProperties = extractRequiredIconStringProperties(
    iconValidator,
    fileName,
    'schema.isValidIcon',
  );

  return {
    whitespacePredicate: 'ecmascript-trim-empty',
    nonWhitespaceStringProperties: [commandProperty, titleProperty].sort(
      compareOrdinal,
    ),
    icon: {
      objectRequiredStringProperties: requiredIconProperties,
    },
  };
}

function validateWhitespaceHelperImport(sourceFile, fileName) {
  const matches = sourceFile.statements.filter((statement) => {
    if (
      !ts.isImportDeclaration(statement) ||
      !ts.isStringLiteral(statement.moduleSpecifier) ||
      statement.moduleSpecifier.text !== '../../../../base/common/strings.js'
    ) {
      return false;
    }
    const bindings = statement.importClause?.namedBindings;
    return (
      bindings !== undefined &&
      ts.isNamedImports(bindings) &&
      bindings.elements.some(
        (element) =>
          element.name.text === 'isFalsyOrWhitespace' &&
          (element.propertyName?.text ?? element.name.text) ===
            'isFalsyOrWhitespace',
      )
    );
  });
  if (matches.length !== 1) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace.import',
      'expected one direct import from ../../../../base/common/strings.js',
    );
  }
  const bindings = matches[0].importClause.namedBindings;
  const helperBindings = bindings.elements.filter(
    (element) => element.name.text === 'isFalsyOrWhitespace',
  );
  if (helperBindings.length !== 1) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace.import',
      'expected exactly one isFalsyOrWhitespace binding',
    );
  }
  return helperBindings[0];
}

function validateWhitespaceHelperCallBindings(
  sourceFile,
  schemaStatements,
  importBinding,
  fileName,
) {
  const options = {
    noLib: true,
    noResolve: true,
    target: ts.ScriptTarget.Latest,
  };
  const host = {
    getSourceFile(requestedFileName) {
      return requestedFileName === fileName ? sourceFile : undefined;
    },
    getDefaultLibFileName() {
      return 'lib.d.ts';
    },
    writeFile() {},
    getCurrentDirectory() {
      return '';
    },
    getDirectories() {
      return [];
    },
    fileExists(requestedFileName) {
      return requestedFileName === fileName;
    },
    readFile(requestedFileName) {
      return requestedFileName === fileName ? sourceFile.getFullText() : undefined;
    },
    getCanonicalFileName(requestedFileName) {
      return requestedFileName;
    },
    useCaseSensitiveFileNames() {
      return true;
    },
    getNewLine() {
      return '\n';
    },
  };
  const program = ts.createProgram([fileName], options, host);
  const checker = program.getTypeChecker();
  let callIndex = 0;
  for (const statement of schemaStatements) {
    visit(statement);
  }

  function visit(node) {
    if (
      ts.isCallExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'isFalsyOrWhitespace'
    ) {
      const symbol = checker.getSymbolAtLocation(node.expression);
      if (
        symbol === undefined ||
        !symbol.declarations?.includes(importBinding)
      ) {
        unsupported(
          fileName,
          'validationHelpers.isFalsyOrWhitespace.binding',
          `call ${callIndex} does not resolve to the pinned import`,
        );
      }
      callIndex += 1;
    }
    ts.forEachChild(node, visit);
  }
}

function validateIsFalsyOrWhitespaceHelper(source, fileName) {
  if (typeof source !== 'string' || typeof fileName !== 'string') {
    unsupported(
      fileName ?? '<unpinned helper>',
      'validationHelpers.isFalsyOrWhitespace.source',
      'expected one pinned helper source',
    );
  }
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
      'validationHelpers.isFalsyOrWhitespace.parse',
      ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'),
    );
  }
  const matches = sourceFile.statements.filter(
    (statement) =>
      ts.isFunctionDeclaration(statement) &&
      statement.name?.text === 'isFalsyOrWhitespace',
  );
  if (matches.length !== 1 || matches[0].body === undefined) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace',
      'expected exactly one function implementation',
    );
  }
  const helper = matches[0];
  const modifierKinds = (helper.modifiers ?? []).map(
    (modifier) => modifier.kind,
  );
  if (
    modifierKinds.length !== 1 ||
    modifierKinds[0] !== ts.SyntaxKind.ExportKeyword
  ) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace.modifiers',
      'expected one exported function',
    );
  }
  if (
    helper.parameters.length !== 1 ||
    !ts.isIdentifier(helper.parameters[0].name) ||
    helper.parameters[0].name.text !== 'str' ||
    helper.parameters[0].initializer !== undefined ||
    normalizedNodeText(helper.parameters[0].type) !== 'string|undefined' ||
    normalizedNodeText(helper.type) !== 'boolean'
  ) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace.signature',
      'expected (str: string | undefined): boolean',
    );
  }
  const statements = helper.body.statements;
  if (
    statements.length !== 2 ||
    !ts.isIfStatement(statements[0]) ||
    statements[0].elseStatement !== undefined ||
    normalizedExpressionText(statements[0].expression) !==
      "!str||typeofstr!=='string'" ||
    !ts.isBlock(statements[0].thenStatement) ||
    statements[0].thenStatement.statements.length !== 1 ||
    !returnsBoolean(statements[0].thenStatement, true)
  ) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace.guard',
      "expected !str || typeof str !== 'string' to return true",
    );
  }
  const finalReturn = statements[1];
  if (
    !ts.isReturnStatement(finalReturn) ||
    normalizedExpressionText(finalReturn.expression) !==
      'str.trim().length===0'
  ) {
    unsupported(
      fileName,
      'validationHelpers.isFalsyOrWhitespace.finalReturn',
      'expected str.trim().length === 0',
    );
  }
}

function normalizedNodeText(node) {
  if (node === undefined) {
    return undefined;
  }
  const scanner = ts.createScanner(
    ts.ScriptTarget.Latest,
    true,
    ts.LanguageVariant.Standard,
    node.getText(),
  );
  let result = '';
  for (
    let token = scanner.scan();
    token !== ts.SyntaxKind.EndOfFileToken;
    token = scanner.scan()
  ) {
    result += scanner.getTokenText();
  }
  return result;
}

function findFunctionDeclaration(statements, name, fileName) {
  const matches = statements.filter(
    (statement) =>
      ts.isFunctionDeclaration(statement) && statement.name?.text === name,
  );
  if (matches.length !== 1 || matches[0].body === undefined) {
    unsupported(fileName, `schema.${name}`, 'expected exactly one function');
  }
  return matches[0];
}

function expectRejectedPropertyCall(
  validator,
  calleeName,
  objectName,
  expectedNegated,
  fileName,
  path,
) {
  const matches = validator.body.statements.filter((statement) => {
    if (
      !ts.isIfStatement(statement) ||
      !returnsBoolean(statement.thenStatement, false)
    ) {
      return false;
    }
    const callWithPolarity = unwrapCallWithPolarity(statement.expression);
    const call = callWithPolarity?.call;
    return (
      call !== undefined &&
      callWithPolarity.negated === expectedNegated &&
      ts.isIdentifier(call.expression) &&
      call.expression.text === calleeName &&
      call.arguments.length >= 1 &&
      propertyAccessName(call.arguments[0], objectName) !== undefined
    );
  });
  if (matches.length !== 1) {
    unsupported(
      fileName,
      path,
      `expected one rejecting ${calleeName} property check`,
    );
  }
  const call = unwrapCallWithPolarity(matches[0].expression).call;
  const property = propertyAccessName(call.arguments[0], objectName);
  if (
    calleeName === 'isValidLocalizedString' &&
    (call.arguments.length !== 3 ||
      expectStringLiteral(call.arguments[2], fileName, path) !== property)
  ) {
    unsupported(
      fileName,
      path,
      'localized-string property label does not match the checked property',
    );
  }
  return property;
}

function unwrapCallWithPolarity(expression) {
  const unwrapped = unwrapExpression(expression);
  if (
    ts.isPrefixUnaryExpression(unwrapped) &&
    unwrapped.operator === ts.SyntaxKind.ExclamationToken
  ) {
    const operand = unwrapExpression(unwrapped.operand);
    return ts.isCallExpression(operand)
      ? {call: operand, negated: true}
      : undefined;
  }
  return ts.isCallExpression(unwrapped)
    ? {call: unwrapped, negated: false}
    : undefined;
}

function propertyAccessName(expression, objectName) {
  const unwrapped = unwrapExpression(expression);
  if (
    !ts.isPropertyAccessExpression(unwrapped) ||
    !ts.isIdentifier(unwrapped.expression) ||
    unwrapped.expression.text !== objectName
  ) {
    return undefined;
  }
  return unwrapped.name.text;
}

function expectStringWhitespaceRejection(validator, fileName, path) {
  const matches = collectIfStatements(validator.body).filter((statement) => {
    if (!returnsBoolean(statement.thenStatement, false)) {
      return false;
    }
    const conditions = flattenAndConditions(statement.expression);
    return (
      conditions.some((condition) =>
        isTypeofStringComparison(condition, 'localized'),
      ) &&
      conditions.some((condition) =>
        isIdentifierCall(condition, 'isFalsyOrWhitespace', 'localized'),
      )
    );
  });
  if (matches.length !== 1) {
    unsupported(
      fileName,
      path,
      'expected one rejecting whitespace check for string values',
    );
  }
}

function extractRequiredIconStringProperties(validator, fileName, path) {
  const ifStatements = collectIfStatements(validator.body);
  const stringBranches = ifStatements.filter(
    (statement) =>
      returnsBoolean(statement.thenStatement, true) &&
      isTypeofStringComparison(statement.expression, 'icon'),
  );
  if (stringBranches.length !== 1) {
    unsupported(fileName, path, 'expected one accepting string icon branch');
  }

  const objectBranches = ifStatements.filter((statement) => {
    if (!returnsBoolean(statement.thenStatement, true)) {
      return false;
    }
    const conditions = flattenAndConditions(statement.expression);
    return conditions.every(
      (condition) =>
        typeofStringPropertyName(condition, 'icon') !== undefined,
    );
  });
  if (objectBranches.length !== 1) {
    unsupported(
      fileName,
      path,
      'expected one accepting object icon branch with string properties',
    );
  }
  const properties = flattenAndConditions(objectBranches[0].expression).map(
    (condition) => typeofStringPropertyName(condition, 'icon'),
  );
  if (properties.length === 0 || new Set(properties).size !== properties.length) {
    unsupported(fileName, path, 'icon object string checks must be unique');
  }
  if (!returnsFinalBoolean(validator.body, false)) {
    unsupported(fileName, path, 'expected invalid icon values to return false');
  }
  return properties.sort(compareOrdinal);
}

function collectIfStatements(node) {
  const statements = [];
  function visit(current) {
    if (ts.isIfStatement(current)) {
      statements.push(current);
    }
    ts.forEachChild(current, visit);
  }
  visit(node);
  return statements;
}

function expectExactValidatorBranches(
  validator,
  expectedConditions,
  branchReturnValue,
  finalReturnValue,
  expectedExpressionStatementCount,
  fileName,
  path,
) {
  const branches = collectIfStatements(validator.body);
  const sharedLength = Math.min(branches.length, expectedConditions.length);
  for (let index = 0; index < sharedLength; index += 1) {
    const actual = normalizedExpressionText(branches[index].expression);
    const expected = expectedConditions[index];
    if (actual !== expected) {
      unsupported(
        fileName,
        `${path}.branches[${index}]`,
        `expected rejecting condition ${expected}, found ${actual}`,
      );
    }
    if (!returnsBoolean(branches[index].thenStatement, branchReturnValue)) {
      unsupported(
        fileName,
        `${path}.branches[${index}]`,
        `expected branch to return ${branchReturnValue}`,
      );
    }
  }
  if (branches.length > expectedConditions.length) {
    const index = expectedConditions.length;
    unsupported(
      fileName,
      `${path}.branches[${index}]`,
      'unprojected rejecting condition ' +
        normalizedExpressionText(branches[index].expression),
    );
  }
  if (branches.length < expectedConditions.length) {
    const index = branches.length;
    unsupported(
      fileName,
      `${path}.branches[${index}]`,
      `missing projected condition ${expectedConditions[index]}`,
    );
  }
  if (!returnsFinalBoolean(validator.body, finalReturnValue)) {
    unsupported(
      fileName,
      `${path}.finalReturn`,
      `expected final return ${finalReturnValue}`,
    );
  }
  let returnCount = 0;
  let expressionStatementCount = 0;
  function visit(current) {
    if (ts.isReturnStatement(current)) {
      returnCount += 1;
    } else if (ts.isExpressionStatement(current)) {
      expressionStatementCount += 1;
    } else if (
      ts.isStatement(current) &&
      !ts.isBlock(current) &&
      !ts.isIfStatement(current)
    ) {
      unsupported(
        fileName,
        `${path}.controlFlow`,
        `unprojected ${ts.SyntaxKind[current.kind]} statement`,
      );
    }
    ts.forEachChild(current, visit);
  }
  visit(validator.body);
  if (returnCount !== branches.length + 1) {
    unsupported(
      fileName,
      `${path}.returns`,
      `expected ${branches.length + 1} projected returns, found ${returnCount}`,
    );
  }
  if (expressionStatementCount !== expectedExpressionStatementCount) {
    unsupported(
      fileName,
      `${path}.diagnostics`,
      'expected ' +
        `${expectedExpressionStatementCount} diagnostic statements, found ` +
        expressionStatementCount,
    );
  }
}

function normalizedExpressionText(expression) {
  return normalizedNodeText(unwrapExpression(expression));
}

function flattenAndConditions(expression) {
  const unwrapped = unwrapExpression(expression);
  if (
    ts.isBinaryExpression(unwrapped) &&
    unwrapped.operatorToken.kind === ts.SyntaxKind.AmpersandAmpersandToken
  ) {
    return [
      ...flattenAndConditions(unwrapped.left),
      ...flattenAndConditions(unwrapped.right),
    ];
  }
  return [unwrapped];
}

function isTypeofStringComparison(expression, identifierName) {
  const unwrapped = unwrapExpression(expression);
  if (!ts.isBinaryExpression(unwrapped)) {
    return false;
  }
  const [operand, literal] = comparisonOperands(unwrapped);
  return (
    operand !== undefined &&
    ts.isTypeOfExpression(operand) &&
    ts.isIdentifier(unwrapExpression(operand.expression)) &&
    unwrapExpression(operand.expression).text === identifierName &&
    literal !== undefined &&
    literal.text === 'string'
  );
}

function typeofStringPropertyName(expression, objectName) {
  const unwrapped = unwrapExpression(expression);
  if (!ts.isBinaryExpression(unwrapped)) {
    return undefined;
  }
  const [operand, literal] = comparisonOperands(unwrapped);
  if (
    operand === undefined ||
    !ts.isTypeOfExpression(operand) ||
    literal === undefined ||
    literal.text !== 'string'
  ) {
    return undefined;
  }
  return propertyAccessName(operand.expression, objectName);
}

function comparisonOperands(expression) {
  if (
    expression.operatorToken.kind !== ts.SyntaxKind.EqualsEqualsEqualsToken
  ) {
    return [];
  }
  const left = unwrapExpression(expression.left);
  const right = unwrapExpression(expression.right);
  if (ts.isStringLiteral(right)) {
    return [left, right];
  }
  if (ts.isStringLiteral(left)) {
    return [right, left];
  }
  return [];
}

function isIdentifierCall(expression, calleeName, argumentName) {
  const unwrapped = unwrapExpression(expression);
  return (
    ts.isCallExpression(unwrapped) &&
    ts.isIdentifier(unwrapped.expression) &&
    unwrapped.expression.text === calleeName &&
    unwrapped.arguments.length === 1 &&
    ts.isIdentifier(unwrapExpression(unwrapped.arguments[0])) &&
    unwrapExpression(unwrapped.arguments[0]).text === argumentName
  );
}

function returnsBoolean(statement, value) {
  const unwrapped = ts.isBlock(statement)
    ? statement.statements.at(-1)
    : statement;
  return (
    unwrapped !== undefined &&
    ts.isReturnStatement(unwrapped) &&
    unwrapped.expression?.kind ===
      (value ? ts.SyntaxKind.TrueKeyword : ts.SyntaxKind.FalseKeyword)
  );
}

function returnsFinalBoolean(block, value) {
  const statement = block.statements.at(-1);
  return statement !== undefined && returnsBoolean(statement, value);
}

function compareOrdinal(left, right) {
  return left < right ? -1 : left > right ? 1 : 0;
}

function validateRegistration(sourceFile, fileName) {
  const initializer = findVariableInitializer(
    sourceFile.statements,
    'commandsExtensionPoint',
    fileName,
  );
  const unwrapped = unwrapExpression(initializer);
  if (!ts.isCallExpression(unwrapped) || unwrapped.arguments.length !== 1) {
    unsupported(
      fileName,
      'commandsExtensionPoint',
      'expected one registerExtensionPoint call',
    );
  }
  const callee = unwrapExpression(unwrapped.expression);
  if (
    !ts.isPropertyAccessExpression(callee) ||
    !ts.isIdentifier(callee.expression) ||
    callee.expression.text !== 'ExtensionsRegistry' ||
    callee.name.text !== 'registerExtensionPoint'
  ) {
    unsupported(
      fileName,
      'commandsExtensionPoint',
      'expected ExtensionsRegistry.registerExtensionPoint',
    );
  }
  const descriptor = expectObjectLiteral(
    unwrapped.arguments[0],
    fileName,
    'commandsExtensionPoint.descriptor',
  );
  expectOnlyObjectProperties(
    descriptor,
    new Set(['activationEventsGenerator', 'extensionPoint', 'jsonSchema']),
    fileName,
    'commandsExtensionPoint.descriptor',
  );
  expectStringProperty(
    descriptor,
    'extensionPoint',
    'commands',
    fileName,
    'commandsExtensionPoint.extensionPoint',
  );
  const jsonSchema = unwrapExpression(
    expectPropertyInitializer(
      descriptor,
      'jsonSchema',
      fileName,
      'commandsExtensionPoint.jsonSchema',
    ),
  );
  if (
    !ts.isPropertyAccessExpression(jsonSchema) ||
    !ts.isIdentifier(jsonSchema.expression) ||
    jsonSchema.expression.text !== 'schema' ||
    jsonSchema.name.text !== 'commandsContribution'
  ) {
    unsupported(
      fileName,
      'commandsExtensionPoint.jsonSchema',
      'expected schema.commandsContribution',
    );
  }
}

function normalizeSchemaObject(object, fileName, path, allowed) {
  expectOnlyObjectProperties(
    object,
    new Set([...allowed, 'description', 'markdownDescription']),
    fileName,
    path,
  );
  const output = {};
  if (hasProperty(object, 'type')) {
    output.type = expectStringLiteral(
      expectPropertyInitializer(object, 'type', fileName, `${path}.type`),
      fileName,
      `${path}.type`,
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
  if (hasProperty(object, 'properties')) {
    const properties = expectObjectLiteral(
      expectPropertyInitializer(
        object,
        'properties',
        fileName,
        `${path}.properties`,
      ),
      fileName,
      `${path}.properties`,
    );
    const normalized = {};
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
        unsupported(fileName, `${path}.properties`, 'unsupported property name');
      }
      entries.push([name, property.initializer]);
    }
    entries.sort(([left], [right]) => compareOrdinal(left, right));
    for (const [name, initializer] of entries) {
      if (Object.hasOwn(normalized, name)) {
        unsupported(fileName, `${path}.properties.${name}`, 'duplicate property');
      }
      normalized[name] = normalizeSchemaObject(
        expectObjectLiteral(initializer, fileName, `${path}.properties.${name}`),
        fileName,
        `${path}.properties.${name}`,
        new Set(['anyOf', 'properties', 'type']),
      );
    }
    output.properties = normalized;
  }
  if (hasProperty(object, 'anyOf')) {
    const alternatives = expectArrayProperty(
      object,
      'anyOf',
      fileName,
      `${path}.anyOf`,
    );
    output.anyOf = alternatives.elements.map((element, index) =>
      normalizeSchemaObject(
        expectObjectLiteral(element, fileName, `${path}.anyOf[${index}]`),
        fileName,
        `${path}.anyOf[${index}]`,
        new Set(['properties', 'type']),
      ),
    );
  }
  if (Object.keys(output).length === 0) {
    unsupported(fileName, path, 'schema has no supported constraints');
  }
  return output;
}

function findNamespaceStatements(sourceFile, name, fileName) {
  const matches = sourceFile.statements.filter(
    (statement) =>
      ts.isModuleDeclaration(statement) &&
      ts.isIdentifier(statement.name) &&
      statement.name.text === name,
  );
  if (
    matches.length !== 1 ||
    matches[0].body === undefined ||
    !ts.isModuleBlock(matches[0].body)
  ) {
    unsupported(fileName, name, 'expected exactly one namespace block');
  }
  return matches[0].body.statements;
}

function findVariableInitializer(statements, name, fileName) {
  const matches = [];
  for (const statement of statements) {
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

function hasProperty(object, name) {
  return object.properties.some(
    (property) =>
      ts.isPropertyAssignment(property) && propertyName(property.name) === name,
  );
}

function expectPropertyInitializer(object, name, fileName, path) {
  const matches = object.properties.filter(
    (property) =>
      ts.isPropertyAssignment(property) && propertyName(property.name) === name,
  );
  if (matches.length !== 1) {
    unsupported(fileName, path, 'expected exactly one object property');
  }
  return matches[0].initializer;
}

function expectArrayProperty(object, name, fileName, path) {
  const initializer = unwrapExpression(
    expectPropertyInitializer(object, name, fileName, path),
  );
  if (!ts.isArrayLiteralExpression(initializer)) {
    unsupported(fileName, path, 'expected an array literal');
  }
  return initializer;
}

function expectStringProperty(object, name, expected, fileName, path) {
  const actual = expectStringLiteral(
    expectPropertyInitializer(object, name, fileName, path),
    fileName,
    path,
  );
  if (actual !== expected) {
    unsupported(fileName, path, `expected ${expected}, found ${actual}`);
  }
}

function expectObjectLiteral(expression, fileName, path) {
  const unwrapped = unwrapExpression(expression);
  if (!ts.isObjectLiteralExpression(unwrapped)) {
    unsupported(fileName, path, 'expected an object literal');
  }
  return unwrapped;
}

function expectIdentifier(expression, expected, fileName, path) {
  const unwrapped = unwrapExpression(expression);
  if (!ts.isIdentifier(unwrapped) || unwrapped.text !== expected) {
    unsupported(fileName, path, `expected identifier ${expected}`);
  }
}

function expectStringLiteral(expression, fileName, path) {
  const unwrapped = unwrapExpression(expression);
  if (
    !ts.isStringLiteral(unwrapped) &&
    !ts.isNoSubstitutionTemplateLiteral(unwrapped)
  ) {
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
    `Unsupported contribution schema in ${fileName}. ` +
      `First differing path: ${path}. Detail: ${detail}. ` +
      'Remediation: review the pinned VS Code constraint, update ' +
      'tool/binding_importer/src/contribution_schema.cjs and its regression ' +
      'tests to project it, then regenerate the canonical IR with the ' +
      'importer CLI --output command.',
  );
  error.code = 'CONTRIBUTION_SCHEMA_UNSUPPORTED';
  throw error;
}

module.exports = {
  extractContributionSchemaProjection,
  // Shared fail-closed AST helpers, reused by the views/configuration
  // extractor so both speak the same dialect of refusal.
  helpers: {
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
  },
};
