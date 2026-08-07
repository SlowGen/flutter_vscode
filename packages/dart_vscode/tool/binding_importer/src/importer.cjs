const crypto = require('node:crypto');

const ts = require('typescript');

function importVscodeDeclarations(source, fileName) {
  const sourceFile = ts.createSourceFile(
    fileName,
    source,
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  if (sourceFile.parseDiagnostics.length > 0) {
    const error = new Error(
      `Cannot parse ${fileName}: ${sourceFile.parseDiagnostics[0].messageText}`,
    );
    error.code = 'TYPESCRIPT_PARSE_FAILED';
    throw error;
  }

  const state = {
    sourceFile,
    declarations: [],
    declarationsById: new Map(),
    signatureOrdinals: new Map(),
  };
  let vscodeModuleCount = 0;
  for (const statement of sourceFile.statements) {
    if (
      ts.isModuleDeclaration(statement) &&
      ts.isStringLiteral(statement.name) &&
      statement.name.text === 'vscode'
    ) {
      validateModifiers(state, statement, 'module:vscode', [
        ts.SyntaxKind.ExportKeyword,
        ts.SyntaxKind.DeclareKeyword,
      ]);
      vscodeModuleCount += 1;
      if (!statement.body) {
        throwUnclassifiedPublicSyntax(
          state,
          statement,
          'module:vscode',
          'module declaration',
        );
      }
      visitModuleBody(statement.body, 'vscode', 'module:vscode', state);
      continue;
    }
    visitDeclarationStatement(statement, 'global', 'global:global', state);
  }
  if (vscodeModuleCount === 0) {
    const error = new Error(`${fileName} does not declare module 'vscode'.`);
    error.code = 'VSCODE_MODULE_MISSING';
    throw error;
  }
  state.declarations.sort(compareDeclarations);

  return {
    schemaVersion: 1,
    module: {
      id: 'module:vscode',
      name: 'vscode',
    },
    declarations: state.declarations,
  };
}

function visitModuleBody(body, parentName, parentId, state) {
  if (ts.isModuleDeclaration(body) && ts.isIdentifier(body.name)) {
    visitNamespaceDeclaration(body, parentName, parentId, state);
    return;
  }
  if (!ts.isModuleBlock(body)) {
    throwUnclassifiedPublicSyntax(
      state,
      body,
      parentId,
      'namespace body',
    );
  }

  for (const statement of body.statements) {
    visitDeclarationStatement(statement, parentName, parentId, state);
  }
}

function visitDeclarationStatement(statement, parentName, parentId, state) {
  if (ts.isModuleDeclaration(statement) && ts.isIdentifier(statement.name)) {
    visitNamespaceDeclaration(statement, parentName, parentId, state);
    return;
  }

  if (ts.isFunctionDeclaration(statement) && statement.name) {
    addSignatureDeclaration(
      state,
      'function',
      statement.name.text,
      `${parentName}.${statement.name.text}`,
      parentId,
      statement,
    );
    return;
  }

  if (ts.isInterfaceDeclaration(statement)) {
    visitInterface(statement, parentName, parentId, state);
    return;
  }

  if (ts.isClassDeclaration(statement) && statement.name) {
    visitClass(statement, parentName, parentId, state);
    return;
  }

  if (ts.isEnumDeclaration(statement)) {
    visitEnum(statement, parentName, parentId, state);
    return;
  }

  if (ts.isTypeAliasDeclaration(statement)) {
    visitTypeAlias(statement, parentName, parentId, state);
    return;
  }

  if (ts.isVariableStatement(statement)) {
    visitVariableStatement(statement, parentName, parentId, state);
    return;
  }

  throwUnclassifiedPublicSyntax(state, statement, parentId, 'statement');
}

function visitNamespaceDeclaration(statement, parentName, parentId, state) {
  if ((statement.flags & ts.NodeFlags.GlobalAugmentation) !== 0) {
    throwUnclassifiedPublicSyntax(
      state,
      statement,
      parentId,
      'global augmentation',
    );
  }
  const qualifiedName = `${parentName}.${statement.name.text}`;
  const id = `namespace:${qualifiedName}`;
  validateModifiers(state, statement, parentId, [
    ts.SyntaxKind.ExportKeyword,
    ts.SyntaxKind.DeclareKeyword,
  ]);
  addDeclaration(state, {
    id,
    kind: 'namespace',
    name: statement.name.text,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(statement),
  });
  if (!statement.body) {
    throwUnclassifiedPublicSyntax(
      state,
      statement,
      id,
      'namespace declaration',
    );
  }
  visitModuleBody(statement.body, qualifiedName, id, state);
}

function visitInterface(node, parentName, parentId, state) {
  const qualifiedName = `${parentName}.${node.name.text}`;
  const id = `interface:${qualifiedName}`;
  const typeParameters = normalizeTypeParameters(node.typeParameters, state, id);
  validateHeritageClauseKinds(
    node.heritageClauses,
    [ts.SyntaxKind.ExtendsKeyword],
    state,
    id,
  );
  validateModifiers(state, node, parentId, [
    ts.SyntaxKind.ExportKeyword,
    ts.SyntaxKind.DeclareKeyword,
  ]);
  addDeclaration(state, {
    id,
    kind: 'interface',
    name: node.name.text,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(node),
    typeParameters,
    extends: normalizeHeritageClauses(
      node.heritageClauses,
      ts.SyntaxKind.ExtendsKeyword,
      state,
      id,
    ),
  });
  visitTypeMembers(
    node.members,
    qualifiedName,
    id,
    state,
    [typeParameters],
    'interface',
  );
}

function visitClass(node, parentName, parentId, state) {
  const qualifiedName = `${parentName}.${node.name.text}`;
  const id = `class:${qualifiedName}`;
  const typeParameters = normalizeTypeParameters(node.typeParameters, state, id);
  validateHeritageClauseKinds(
    node.heritageClauses,
    [ts.SyntaxKind.ExtendsKeyword, ts.SyntaxKind.ImplementsKeyword],
    state,
    id,
  );
  validateModifiers(state, node, parentId, [
    ts.SyntaxKind.ExportKeyword,
    ts.SyntaxKind.DeclareKeyword,
    ts.SyntaxKind.AbstractKeyword,
  ]);
  addDeclaration(state, {
    id,
    kind: 'class',
    name: node.name.text,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(node),
    abstract: hasModifier(node, ts.SyntaxKind.AbstractKeyword),
    typeParameters,
    extends: normalizeHeritageClauses(
      node.heritageClauses,
      ts.SyntaxKind.ExtendsKeyword,
      state,
      id,
    ),
    implements: normalizeHeritageClauses(
      node.heritageClauses,
      ts.SyntaxKind.ImplementsKeyword,
      state,
      id,
    ),
  });
  visitTypeMembers(
    node.members,
    qualifiedName,
    id,
    state,
    [typeParameters],
    'class',
  );
}

function visitEnum(node, parentName, parentId, state) {
  const qualifiedName = `${parentName}.${node.name.text}`;
  const id = `enum:${qualifiedName}`;
  validateModifiers(state, node, parentId, [
    ts.SyntaxKind.ExportKeyword,
    ts.SyntaxKind.DeclareKeyword,
    ts.SyntaxKind.ConstKeyword,
  ]);
  addDeclaration(state, {
    id,
    kind: 'enum',
    name: node.name.text,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(node),
    constant: hasModifier(node, ts.SyntaxKind.ConstKeyword),
  });

  for (const member of node.members) {
    const name = normalizeDeclarationName(member.name, state, id);
    if (!member.initializer) {
      throwUnclassifiedPublicSyntax(
        state,
        member,
        id,
        'implicit enum member',
      );
    }
    const memberQualifiedName = `${qualifiedName}.${name}`;
    const record = {
      id: `enumMember:${id}/${encodeIdPart(name)}`,
      kind: 'enumMember',
      name,
      qualifiedName: memberQualifiedName,
      parentId: id,
      deprecated: isDeprecated(member),
    };
    record.initializer = normalizeExpression(member.initializer, state, id);
    addDeclaration(state, record);
  }
}

function visitTypeAlias(node, parentName, parentId, state) {
  const qualifiedName = `${parentName}.${node.name.text}`;
  const id = `typeAlias:${qualifiedName}`;
  const typeParameters = normalizeTypeParameters(node.typeParameters, state, id);
  validateModifiers(state, node, parentId, [
    ts.SyntaxKind.ExportKeyword,
    ts.SyntaxKind.DeclareKeyword,
  ]);
  const type = normalizeType(node.type, state, {
    qualifiedName,
    parentId: id,
    role: 'type',
    typeParameterScopes: [typeParameters],
  });
  addDeclaration(state, {
    id,
    kind: 'typeAlias',
    name: node.name.text,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(node),
    typeParameters,
    type,
  });
}

function visitVariableStatement(node, parentName, parentId, state) {
  validateModifiers(state, node, parentId, [
    ts.SyntaxKind.ExportKeyword,
    ts.SyntaxKind.DeclareKeyword,
  ]);
  if ((node.declarationList.flags & ts.NodeFlags.Using) !== 0) {
    throwUnclassifiedPublicSyntax(
      state,
      node.declarationList,
      parentId,
      'resource variable declaration',
    );
  }
  const declarationKind = variableDeclarationKind(node.declarationList.flags);
  const constant = declarationKind === 'const';
  for (const declaration of node.declarationList.declarations) {
    if (!ts.isIdentifier(declaration.name)) {
      throwUnclassifiedPublicSyntax(
        state,
        declaration,
        parentId,
        'variable declaration',
      );
    }
    const name = declaration.name.text;
    const qualifiedName = `${parentName}.${name}`;
    const id = `variable:${qualifiedName}`;
    if (!declaration.type) {
      throwUnclassifiedPublicSyntax(
        state,
        declaration,
        id,
        'missing type annotation',
      );
    }
    if (declaration.exclamationToken) {
      throwUnclassifiedPublicSyntax(
        state,
        declaration.exclamationToken,
        id,
        'definite assignment assertion',
      );
    }
    if (declaration.initializer) {
      throwUnclassifiedPublicSyntax(
        state,
        declaration.initializer,
        id,
        'variable initializer',
      );
    }
    addDeclaration(state, {
      id,
      kind: 'variable',
      name,
      qualifiedName,
      parentId,
      deprecated: isDeprecated(declaration) || isDeprecated(node),
      constant,
      declarationKind,
      type: normalizeType(declaration.type, state, {
        qualifiedName,
        parentId: id,
        role: 'type',
      }),
    });
  }
}

function variableDeclarationKind(flags) {
  if ((flags & ts.NodeFlags.Const) !== 0) {
    return 'const';
  }
  if ((flags & ts.NodeFlags.Let) !== 0) {
    return 'let';
  }
  return 'var';
}

function visitTypeMembers(
  members,
  parentName,
  parentId,
  state,
  typeParameterScopes = [],
  containerKind,
  inheritedVisibility = 'public',
) {
  for (const member of members) {
    if (ts.isPropertySignature(member) || ts.isPropertyDeclaration(member)) {
      addPropertyDeclaration(
        member,
        parentName,
        parentId,
        state,
        typeParameterScopes,
        containerKind,
        inheritedVisibility,
      );
      continue;
    }

    if (ts.isMethodSignature(member) || ts.isMethodDeclaration(member)) {
      const name = normalizeDeclarationName(member.name, state, parentId);
      addSignatureDeclaration(
        state,
        'method',
        name,
        `${parentName}.${name}`,
        parentId,
        member,
        typeParameterScopes,
        containerKind,
        inheritedVisibility,
      );
      continue;
    }

    if (ts.isConstructorDeclaration(member)) {
      addSignatureDeclaration(
        state,
        'constructor',
        'constructor',
        `${parentName}.constructor`,
        parentId,
        member,
        typeParameterScopes,
        containerKind,
        inheritedVisibility,
      );
      continue;
    }

    if (ts.isCallSignatureDeclaration(member)) {
      addSignatureDeclaration(
        state,
        'callSignature',
        '$call',
        `${parentName}.$call`,
        parentId,
        member,
        typeParameterScopes,
        containerKind,
        inheritedVisibility,
      );
      continue;
    }

    if (ts.isIndexSignatureDeclaration(member)) {
      addSignatureDeclaration(
        state,
        'indexSignature',
        '$index',
        `${parentName}.$index`,
        parentId,
        member,
        typeParameterScopes,
        containerKind,
        inheritedVisibility,
      );
      continue;
    }

    throwUnclassifiedPublicSyntax(state, member, parentId, 'type member');
  }
}

function addPropertyDeclaration(
  node,
  parentName,
  parentId,
  state,
  typeParameterScopes = [],
  containerKind,
  inheritedVisibility = 'public',
) {
  validateModifiers(
    state,
    node,
    parentId,
    propertyModifierKinds(containerKind),
  );
  const visibility = effectiveVisibility(
    inheritedVisibility,
    declarationVisibility(node),
  );
  if (!node.type) {
    throwUnclassifiedPublicSyntax(
      state,
      node,
      parentId,
      'missing type annotation',
    );
  }
  if (node.initializer) {
    throwUnclassifiedPublicSyntax(
      state,
      node.initializer,
      parentId,
      'property initializer',
    );
  }
  if (node.exclamationToken) {
    throwUnclassifiedPublicSyntax(
      state,
      node.exclamationToken,
      parentId,
      'definite assignment assertion',
    );
  }
  const name = normalizeDeclarationName(node.name, state, parentId);
  const qualifiedName = `${parentName}.${name}`;
  const staticMember = hasModifier(node, ts.SyntaxKind.StaticKeyword);
  const scope = staticMember ? '$static' : '$instance';
  const id = `property:${parentId}/${scope}/${encodeIdPart(name)}`;
  addDeclaration(state, {
    id,
    kind: 'property',
    name,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(node),
    visibility,
    optional: node.questionToken !== undefined,
    readonly: hasModifier(node, ts.SyntaxKind.ReadonlyKeyword),
    static: staticMember,
    abstract: hasModifier(node, ts.SyntaxKind.AbstractKeyword),
    type: normalizeType(node.type, state, {
      qualifiedName,
      parentId: id,
      role: 'type',
      typeParameterScopes,
      visibility,
    }),
  });
}

function addSignatureDeclaration(
  state,
  kind,
  name,
  qualifiedName,
  parentId,
  node,
  typeParameterScopes = [],
  containerKind,
  inheritedVisibility = 'public',
) {
  if (node.asteriskToken) {
    throwUnclassifiedPublicSyntax(
      state,
      node.asteriskToken,
      parentId,
      'generator declaration',
    );
  }
  if (node.body) {
    throwUnclassifiedPublicSyntax(
      state,
      node.body,
      parentId,
      'implementation body',
    );
  }
  validateModifiers(
    state,
    node,
    parentId,
    signatureModifierKinds(kind, containerKind),
  );
  const visibility = effectiveVisibility(
    inheritedVisibility,
    declarationVisibility(node),
  );
  const ordinalKey = `${kind}:${qualifiedName}:` +
    `${hasModifier(node, ts.SyntaxKind.StaticKeyword)}`;
  const overloadOrdinal = state.signatureOrdinals.get(ordinalKey) ?? 0;
  state.signatureOrdinals.set(ordinalKey, overloadOrdinal + 1);
  const preview = normalizeSignature(node, state, {
    qualifiedName,
    parentId,
    recordTypeLiterals: false,
    allowMissingReturnType: kind === 'constructor',
    typeParameterScopes,
    visibility,
  });
  const canonical = {...preview.canonical};
  if (kind === 'method') {
    canonical.static = hasModifier(node, ts.SyntaxKind.StaticKeyword);
    canonical.optional = node.questionToken !== undefined;
  }
  if (kind === 'indexSignature') {
    canonical.readonly = hasModifier(node, ts.SyntaxKind.ReadonlyKeyword);
  }
  const canonicalSignature = JSON.stringify(canonical);
  const signatureHash = sha256(canonicalSignature);
  const id = `${kind}:${qualifiedName}@${signatureHash}`;
  const normalized = normalizeSignature(node, state, {
    qualifiedName: `${qualifiedName}.$signature@${signatureHash}`,
    parentId: id,
    recordTypeLiterals: true,
    allowMissingReturnType: kind === 'constructor',
    typeParameterScopes,
    visibility,
  });
  addDeclaration(state, {
    id,
    kind,
    name,
    qualifiedName,
    parentId,
    deprecated: isDeprecated(node),
    visibility,
    overloadOrdinal,
    canonicalSignature,
    ...(kind === 'method'
      ? {
          static: hasModifier(node, ts.SyntaxKind.StaticKeyword),
          optional: node.questionToken !== undefined,
          abstract: hasModifier(node, ts.SyntaxKind.AbstractKeyword),
        }
      : {}),
    ...(kind === 'indexSignature'
      ? {readonly: hasModifier(node, ts.SyntaxKind.ReadonlyKeyword)}
      : {}),
    typeParameters: normalized.typeParameters,
    parameters: normalized.parameters,
    returnType: normalized.returnType,
  });
}

function normalizeSignature(node, state, context) {
  const typeParameters = normalizeTypeParameters(
    node.typeParameters,
    state,
    context.parentId,
    context.typeParameterScopes ?? [],
  );
  const typeParameterScopes = [
    ...(context.typeParameterScopes ?? []),
    typeParameters,
  ];
  const parameters = node.parameters.map((parameter, index) => {
    if (parameter.name.getText(state.sourceFile) === 'this') {
      throwUnclassifiedPublicSyntax(
        state,
        parameter,
        context.parentId,
        'this parameter',
      );
    }
    if ((parameter.modifiers?.length ?? 0) > 0) {
      throwUnclassifiedPublicSyntax(
        state,
        parameter,
        context.parentId,
        'parameter property',
      );
    }
    if (!parameter.type) {
      throwUnclassifiedPublicSyntax(
        state,
        parameter,
        context.parentId,
        'missing type annotation',
      );
    }
    if (parameter.initializer) {
      throwUnclassifiedPublicSyntax(
        state,
        parameter.initializer,
        context.parentId,
        'parameter initializer',
      );
    }
    return {
      name: parameter.name.getText(state.sourceFile),
      optional: parameter.questionToken !== undefined,
      rest: parameter.dotDotDotToken !== undefined,
      type: normalizeType(parameter.type, state, {
        qualifiedName: `${context.qualifiedName}.$parameter${index}`,
        parentId: context.parentId,
        role: 'parameterType',
        recordTypeLiterals: context.recordTypeLiterals,
        typeParameterScopes,
        visibility: context.visibility,
      }),
    };
  });
  if (!node.type && !context.allowMissingReturnType) {
    throwUnclassifiedPublicSyntax(
      state,
      node,
      context.parentId,
      'missing type annotation',
    );
  }
  const returnType = normalizeType(node.type, state, {
    qualifiedName: `${context.qualifiedName}.$return`,
    parentId: context.parentId,
    role: 'returnType',
    recordTypeLiterals: context.recordTypeLiterals,
    typeParameterScopes,
    visibility: context.visibility,
  });
  return {
    typeParameters,
    parameters,
    returnType,
    canonical: {
      typeParameters: canonicalTypeParameters(
        typeParameters,
        typeParameterScopes,
      ),
      parameters: parameters.map((parameter) => ({
        optional: parameter.optional,
        rest: parameter.rest,
        type: canonicalSignatureType(parameter.type, typeParameterScopes),
      })),
      returnType: canonicalSignatureType(returnType, typeParameterScopes),
    },
  };
}

function normalizeTypeParameters(
  nodes,
  state,
  ownerId,
  typeParameterScopes = [],
) {
  const parameterNodes = nodes ?? [];
  const parameters = parameterNodes.map((node) => {
    if ((node.modifiers?.length ?? 0) > 0) {
      throwUnclassifiedPublicSyntax(
        state,
        node,
        ownerId ?? 'module:vscode',
        'type parameter modifier',
      );
    }
    return {name: node.name.text};
  });
  const scopes = [...typeParameterScopes, parameters];
  for (const [index, node] of parameterNodes.entries()) {
    const parameter = parameters[index];
    const context = {
      qualifiedName: `${ownerId ?? 'module:vscode'}.$typeParameter${index}`,
      parentId: ownerId ?? 'module:vscode',
      recordTypeLiterals: false,
      typeParameterScopes: scopes,
    };
    if (node.constraint) {
      parameter.constraint = normalizeType(
        node.constraint,
        state,
        childTypeContext(context, 'constraint'),
      );
    }
    if (node.default) {
      parameter.default = normalizeType(
        node.default,
        state,
        childTypeContext(context, 'default'),
      );
    }
  }
  return parameters;
}

function canonicalTypeParameters(typeParameters, typeParameterScopes) {
  return typeParameters.map((parameter) => {
    const canonical = {};
    if (parameter.constraint) {
      canonical.constraint = canonicalSignatureType(
        parameter.constraint,
        typeParameterScopes,
      );
    }
    if (parameter.default) {
      canonical.default = canonicalSignatureType(
        parameter.default,
        typeParameterScopes,
      );
    }
    return canonical;
  });
}

function canonicalSignatureType(type, typeParameterScopes) {
  if (type === null || typeof type !== 'object') {
    return type;
  }
  if (type.kind === 'reference') {
    const reference = canonicalTypeParameterReference(
      type.name,
      typeParameterScopes,
    );
    if (reference) {
      return reference;
    }
  }
  if (type.kind === 'function') {
    return {
      kind: 'function',
      canonicalSignature: type.canonicalSignature,
    };
  }
  if (type.kind === 'tuple') {
    return {
      kind: 'tuple',
      elements: type.elements.map((element) => ({
        optional: element.optional,
        rest: element.rest,
        type: canonicalSignatureType(element.type, typeParameterScopes),
      })),
    };
  }
  if (type.kind === 'typeLiteral') {
    return {kind: 'typeLiteral', shapeHash: type.shapeHash};
  }
  if (Array.isArray(type)) {
    return type.map((item) =>
      canonicalSignatureType(item, typeParameterScopes));
  }
  return Object.fromEntries(
    Object.entries(type).map(([key, value]) => [
      key,
      canonicalSignatureType(value, typeParameterScopes),
    ]),
  );
}

function canonicalTypeParameterReference(name, typeParameterScopes) {
  for (
    let scopeIndex = typeParameterScopes.length - 1;
    scopeIndex >= 0;
    scopeIndex -= 1
  ) {
    const index = typeParameterScopes[scopeIndex].findIndex(
      (parameter) => parameter.name === name,
    );
    if (index < 0) {
      continue;
    }
    const depth = typeParameterScopes.length - 1 - scopeIndex;
    return depth === 0
      ? {kind: 'typeParameter', index}
      : {kind: 'outerTypeParameter', depth, index};
  }
  return undefined;
}

function normalizeType(type, state, context) {
  if (!type) {
    return {kind: 'primitive', name: 'void'};
  }
  const primitive = primitiveTypeName(type.kind);
  if (primitive) {
    return {kind: 'primitive', name: primitive};
  }
  if (ts.isTypeReferenceNode(type)) {
    return {
      kind: 'reference',
      name: normalizeEntityName(
        type.typeName,
        state,
        context?.parentId ?? 'module:vscode',
      ),
      typeArguments: (type.typeArguments ?? []).map((argument, index) =>
        normalizeType(argument, state, childTypeContext(context, `argument${index}`)),
      ),
    };
  }
  if (ts.isArrayTypeNode(type)) {
    return {
      kind: 'array',
      elementType: normalizeType(
        type.elementType,
        state,
        childTypeContext(context, 'element'),
      ),
    };
  }
  if (ts.isUnionTypeNode(type) || ts.isIntersectionTypeNode(type)) {
    const types = type.types.map((item, index) =>
      normalizeType(item, state, childTypeContext(context, `item${index}`)),
    );
    return {
      kind: ts.isUnionTypeNode(type) ? 'union' : 'intersection',
      types,
    };
  }
  if (ts.isParenthesizedTypeNode(type)) {
    return normalizeType(type.type, state, context);
  }
  if (ts.isLiteralTypeNode(type)) {
    return {
      kind: 'literal',
      value: normalizeLiteral(
        type.literal,
        state,
        context?.parentId ?? 'module:vscode',
      ),
    };
  }
  if (ts.isTupleTypeNode(type)) {
    return {
      kind: 'tuple',
      elements: type.elements.map((element, index) =>
        normalizeTupleElement(
          element,
          state,
          childTypeContext(context, `element${index}`),
        ),
      ),
    };
  }
  if (ts.isTypeOperatorNode(type)) {
    const operator = typeOperatorName(type.operator);
    if (operator === undefined) {
      throwUnclassifiedPublicSyntax(
        state,
        type,
        context?.parentId ?? 'module:vscode',
        'type operator',
      );
    }
    return {
      kind: 'operator',
      operator,
      type: normalizeType(type.type, state, childTypeContext(context, 'operand')),
    };
  }
  if (ts.isFunctionTypeNode(type)) {
    const signature = normalizeSignature(type, state, {
      qualifiedName: context?.qualifiedName ?? '$functionType',
      parentId: context?.parentId ?? 'module:vscode',
      recordTypeLiterals: context?.recordTypeLiterals,
      typeParameterScopes: context?.typeParameterScopes,
      visibility: context?.visibility,
    });
    return {
      kind: 'function',
      typeParameters: signature.typeParameters,
      parameters: signature.parameters,
      returnType: signature.returnType,
      canonicalSignature: JSON.stringify(signature.canonical),
    };
  }
  if (ts.isTypeLiteralNode(type)) {
    return normalizeTypeLiteral(type, state, context);
  }
  throwUnclassifiedPublicSyntax(
    state,
    type,
    context?.parentId ?? 'module:vscode',
    'type syntax',
  );
}

function normalizeTypeLiteral(node, state, context) {
  const ownerId = context?.parentId ?? 'module:vscode';
  const shape = canonicalTypeLiteralShape(
    node,
    state,
    ownerId,
    context?.typeParameterScopes ?? [],
  );
  const shapeHash = sha256(JSON.stringify(shape));
  if (!context || context.recordTypeLiterals === false) {
    return {kind: 'typeLiteral', shape, shapeHash};
  }

  const qualifiedName = `${context.parentId}.$shape@${shapeHash}`;
  const id = `typeLiteral:${context.parentId}/$shape@${shapeHash}`;
  addDeclaration(state, {
    id,
    kind: 'typeLiteral',
    name: '$type',
    qualifiedName,
    parentId: context.parentId,
    deprecated: false,
    visibility: context.visibility ?? 'public',
    shapeHash,
    shape,
  });
  visitTypeMembers(
    node.members,
    qualifiedName,
    id,
    state,
    context.typeParameterScopes ?? [],
    'typeLiteral',
    context.visibility ?? 'public',
  );
  return {kind: 'typeLiteral', id, shapeHash};
}

function canonicalTypeLiteralShape(
  node,
  state,
  ownerId,
  typeParameterScopes = [],
) {
  const members = node.members.map((member) => {
    if (ts.isPropertySignature(member)) {
      validateModifiers(
        state,
        member,
        ownerId,
        propertyModifierKinds('typeLiteral'),
      );
      if (!member.type) {
        throwUnclassifiedPublicSyntax(
          state,
          member,
          ownerId,
          'missing type annotation',
        );
      }
      const type = normalizeType(member.type, state, {
        parentId: ownerId,
        recordTypeLiterals: false,
        typeParameterScopes,
      });
      return {
        kind: 'property',
        name: normalizeDeclarationName(member.name, state, ownerId),
        optional: member.questionToken !== undefined,
        readonly: hasModifier(member, ts.SyntaxKind.ReadonlyKeyword),
        type: typeParameterScopes.some((scope) => scope.length > 0)
          ? canonicalSignatureType(type, typeParameterScopes)
          : type,
      };
    }
    if (ts.isMethodSignature(member)) {
      return canonicalMemberSignature(
        'method',
        member,
        state,
        ownerId,
        typeParameterScopes,
      );
    }
    if (ts.isCallSignatureDeclaration(member)) {
      return canonicalMemberSignature(
        'callSignature',
        member,
        state,
        ownerId,
        typeParameterScopes,
      );
    }
    if (ts.isIndexSignatureDeclaration(member)) {
      return canonicalMemberSignature(
        'indexSignature',
        member,
        state,
        ownerId,
        typeParameterScopes,
      );
    }
    throwUnclassifiedPublicSyntax(
      state,
      member,
      ownerId,
      'type literal member',
    );
  });
  return {members};
}

function canonicalMemberSignature(
  kind,
  node,
  state,
  ownerId,
  typeParameterScopes,
) {
  validateModifiers(
    state,
    node,
    ownerId,
    signatureModifierKinds(kind, 'typeLiteral'),
  );
  const signature = normalizeSignature(node, state, {
    qualifiedName: '$shape',
    parentId: 'module:vscode',
    recordTypeLiterals: false,
    typeParameterScopes,
  });
  const result = {kind, signature: signature.canonical};
  if (node.name) {
    result.name = normalizeDeclarationName(node.name, state, ownerId);
  }
  if (kind === 'method') {
    result.optional = node.questionToken !== undefined;
    result.static = hasModifier(node, ts.SyntaxKind.StaticKeyword);
    result.abstract = hasModifier(node, ts.SyntaxKind.AbstractKeyword);
  }
  if (kind === 'indexSignature') {
    result.readonly = hasModifier(node, ts.SyntaxKind.ReadonlyKeyword);
  }
  return result;
}

function normalizeTupleElement(node, state, context) {
  if (ts.isNamedTupleMember(node)) {
    return {
      name: node.name.text,
      optional: node.questionToken !== undefined,
      rest: node.dotDotDotToken !== undefined,
      type: normalizeType(node.type, state, context),
    };
  }
  if (ts.isOptionalTypeNode(node)) {
    return {
      optional: true,
      rest: false,
      type: normalizeType(node.type, state, context),
    };
  }
  if (ts.isRestTypeNode(node)) {
    return {
      optional: false,
      rest: true,
      type: normalizeType(node.type, state, context),
    };
  }
  return {
    optional: false,
    rest: false,
    type: normalizeType(node, state, context),
  };
}

function normalizeHeritageClauses(clauses, token, state, ownerId) {
  return (clauses ?? [])
    .filter((clause) => clause.token === token)
    .flatMap((clause) => clause.types)
    .map((type) => ({
      kind: 'reference',
      name: normalizeExpressionName(type.expression, state, ownerId),
      typeArguments: (type.typeArguments ?? []).map((argument) =>
        normalizeType(argument, state),
      ),
    }));
}

function validateHeritageClauseKinds(
  clauses,
  allowedTokens,
  state,
  ownerId,
) {
  for (const clause of clauses ?? []) {
    if (!allowedTokens.includes(clause.token)) {
      throwUnclassifiedPublicSyntax(
        state,
        clause,
        ownerId,
        'heritage clause',
      );
    }
  }
}

function normalizeExpression(node, state, ownerId) {
  if (ts.isStringLiteral(node)) {
    return {kind: 'literal', value: node.text};
  }
  if (ts.isNumericLiteral(node)) {
    return {kind: 'literal', value: normalizeNumericLiteral(node, state, ownerId)};
  }
  if (node.kind === ts.SyntaxKind.TrueKeyword) {
    return {kind: 'literal', value: true};
  }
  if (node.kind === ts.SyntaxKind.FalseKeyword) {
    return {kind: 'literal', value: false};
  }
  if (ts.isPrefixUnaryExpression(node)) {
    return {
      kind: 'unary',
      operator: ts.tokenToString(node.operator),
      operand: normalizeExpression(node.operand, state, ownerId),
    };
  }
  if (ts.isIdentifier(node) || ts.isPropertyAccessExpression(node)) {
    return {
      kind: 'reference',
      name: normalizeExpressionName(node, state, ownerId),
    };
  }
  throwUnclassifiedPublicSyntax(
    state,
    node,
    ownerId,
    'expression syntax',
  );
}

function normalizeLiteral(node, state, ownerId) {
  if (ts.isStringLiteral(node)) {
    return node.text;
  }
  if (ts.isNumericLiteral(node)) {
    return normalizeNumericLiteral(node, state, ownerId);
  }
  if (node.kind === ts.SyntaxKind.TrueKeyword) {
    return true;
  }
  if (node.kind === ts.SyntaxKind.FalseKeyword) {
    return false;
  }
  if (node.kind === ts.SyntaxKind.NullKeyword) {
    return null;
  }
  if (ts.isPrefixUnaryExpression(node) && ts.isNumericLiteral(node.operand)) {
    const value = normalizeNumericLiteral(node.operand, state, ownerId);
    if (node.operator === ts.SyntaxKind.MinusToken) {
      return -value;
    }
    if (node.operator === ts.SyntaxKind.PlusToken) {
      return value;
    }
  }
  throwUnclassifiedPublicSyntax(state, node, ownerId, 'literal type');
}

function normalizeNumericLiteral(node, state, ownerId) {
  const value = Number(node.text);
  if (!Number.isSafeInteger(value)) {
    throwUnclassifiedPublicSyntax(
      state,
      node,
      ownerId,
      'unsafe numeric literal',
    );
  }
  return value;
}

function normalizeDeclarationName(node, state, ownerId) {
  if (ts.isIdentifier(node) || ts.isPrivateIdentifier(node)) {
    return node.text;
  }
  if (ts.isStringLiteral(node)) {
    const hasEquivalentUnquotedName =
      ts.isIdentifierText(node.text, ts.ScriptTarget.Latest) ||
      isCanonicalNumericPropertyName(node.text);
    return hasEquivalentUnquotedName
      ? node.text
      : JSON.stringify(node.text);
  }
  if (ts.isNumericLiteral(node)) {
    return node.text;
  }
  if (ts.isComputedPropertyName(node)) {
    return `[${normalizeExpressionName(node.expression, state, ownerId)}]`;
  }
  throwUnclassifiedPublicSyntax(state, node, ownerId, 'declaration name');
}

function isCanonicalNumericPropertyName(name) {
  const value = Number(name);
  return value >= 0 && String(value) === name;
}

function normalizeEntityName(node, state, ownerId) {
  if (ts.isIdentifier(node)) {
    return node.text;
  }
  if (ts.isQualifiedName(node)) {
    return `${normalizeEntityName(node.left, state, ownerId)}.${node.right.text}`;
  }
  throwUnclassifiedPublicSyntax(state, node, ownerId, 'entity name');
}

function normalizeExpressionName(node, state, ownerId) {
  if (ts.isIdentifier(node)) {
    return node.text;
  }
  if (ts.isPropertyAccessExpression(node)) {
    return `${normalizeExpressionName(node.expression, state, ownerId)}.${node.name.text}`;
  }
  throwUnclassifiedPublicSyntax(state, node, ownerId, 'expression name');
}

function childTypeContext(context, child) {
  if (!context) {
    return undefined;
  }
  return {
    qualifiedName: `${context.qualifiedName}.$${child}`,
    parentId: context.parentId,
    role: child,
    recordTypeLiterals: context.recordTypeLiterals,
    typeParameterScopes: context.typeParameterScopes,
    visibility: context.visibility,
  };
}

function primitiveTypeName(kind) {
  switch (kind) {
    case ts.SyntaxKind.AnyKeyword:
      return 'any';
    case ts.SyntaxKind.BooleanKeyword:
      return 'boolean';
    case ts.SyntaxKind.NeverKeyword:
      return 'never';
    case ts.SyntaxKind.NumberKeyword:
      return 'number';
    case ts.SyntaxKind.ObjectKeyword:
      return 'object';
    case ts.SyntaxKind.StringKeyword:
      return 'string';
    case ts.SyntaxKind.UndefinedKeyword:
      return 'undefined';
    case ts.SyntaxKind.UnknownKeyword:
      return 'unknown';
    case ts.SyntaxKind.VoidKeyword:
      return 'void';
    default:
      return undefined;
  }
}

function typeOperatorName(kind) {
  switch (kind) {
    case ts.SyntaxKind.KeyOfKeyword:
      return 'keyof';
    case ts.SyntaxKind.ReadonlyKeyword:
      return 'readonly';
    case ts.SyntaxKind.UniqueKeyword:
      return 'unique';
    default:
      return undefined;
  }
}

function addDeclaration(state, declaration) {
  declaration.visibility ??= 'public';
  declaration.coverage ??= initialCoverage(declaration.visibility);
  const existing = state.declarationsById.get(declaration.id);
  if (existing) {
    if (existing.kind !== declaration.kind) {
      throwDeclarationConflict(state, declaration.id, 'kind');
    }
    if (existing.kind === 'interface' && declaration.kind === 'interface') {
      if (!canonicalValuesEqual(
        existing.typeParameters,
        declaration.typeParameters,
      )) {
        throwDeclarationConflict(state, declaration.id, 'typeParameters');
      }
      existing.extends = canonicalUnion(existing.extends, declaration.extends);
    }
    const field = firstConflictingField(
      existing,
      declaration,
      duplicateCompatibilityFields(existing.kind),
    );
    if (field) {
      throwDeclarationConflict(state, declaration.id, field);
    }
    if (
      ['class', 'typeAlias', 'enumMember'].includes(existing.kind) ||
      (existing.kind === 'variable' && existing.declarationKind !== 'var')
    ) {
      throwNonMergeableDuplicate(state, declaration.id);
    }
    existing.deprecated ||= declaration.deprecated;
    existing.occurrenceCount = (existing.occurrenceCount ?? 1) + 1;
    return existing;
  }
  state.declarationsById.set(declaration.id, declaration);
  state.declarations.push(declaration);
  return declaration;
}

function canonicalUnion(left, right) {
  return [...new Map(
    [...left, ...right].map((value) => [JSON.stringify(value), value]),
  ).values()];
}

function canonicalValuesEqual(left, right) {
  return JSON.stringify(left) === JSON.stringify(right);
}

function firstConflictingField(left, right, fields) {
  return fields.find((field) => !canonicalValuesEqual(left[field], right[field]));
}

function duplicateCompatibilityFields(kind) {
  switch (kind) {
    case 'namespace':
    case 'interface':
      return [];
    case 'class':
      return ['abstract', 'typeParameters', 'extends', 'implements'];
    case 'enum':
      return ['constant'];
    case 'enumMember':
      return ['initializer'];
    case 'typeAlias':
      return ['typeParameters', 'type'];
    case 'variable':
      return ['declarationKind', 'constant', 'type'];
    case 'property':
      return [
        'visibility',
        'optional',
        'readonly',
        'static',
        'abstract',
        'type',
      ];
    case 'method':
      return ['visibility', 'canonicalSignature', 'abstract'];
    case 'function':
    case 'constructor':
    case 'callSignature':
    case 'indexSignature':
      return ['visibility', 'canonicalSignature'];
    case 'typeLiteral':
      return ['shapeHash'];
    default:
      return ['kind'];
  }
}

function throwDeclarationConflict(state, id, field) {
  const error = new Error(
    `${state.sourceFile.fileName}: conflicting declarations for ${id}: ` +
      `${field} must match across declarations.`,
  );
  error.code = 'CONFLICTING_DECLARATION';
  throw error;
}

function throwNonMergeableDuplicate(state, id) {
  const error = new Error(
    `${state.sourceFile.fileName}: duplicate declaration ${id} cannot be merged.`,
  );
  error.code = 'CONFLICTING_DECLARATION';
  throw error;
}

function compareDeclarations(left, right) {
  return compareStrings(left.qualifiedName, right.qualifiedName) ||
    compareOptionalNumbers(left.overloadOrdinal, right.overloadOrdinal) ||
    compareStrings(left.id, right.id);
}

function compareOptionalNumbers(left, right) {
  if (left === undefined || right === undefined) {
    return 0;
  }
  return left - right;
}

function compareCanonicalValues(left, right) {
  return compareStrings(JSON.stringify(left), JSON.stringify(right));
}

function compareStrings(left, right) {
  if (left < right) {
    return -1;
  }
  if (left > right) {
    return 1;
  }
  return 0;
}

function encodeIdPart(value) {
  return encodeURIComponent(value);
}

function sha256(value) {
  return crypto.createHash('sha256').update(value).digest('hex');
}

function propertyModifierKinds(containerKind) {
  if (containerKind !== 'class') {
    return [ts.SyntaxKind.ReadonlyKeyword];
  }
  return [
    ts.SyntaxKind.PublicKeyword,
    ts.SyntaxKind.PrivateKeyword,
    ts.SyntaxKind.ProtectedKeyword,
    ts.SyntaxKind.StaticKeyword,
    ts.SyntaxKind.ReadonlyKeyword,
    ts.SyntaxKind.AbstractKeyword,
  ];
}

function signatureModifierKinds(kind, containerKind) {
  switch (kind) {
    case 'function':
      return [ts.SyntaxKind.ExportKeyword, ts.SyntaxKind.DeclareKeyword];
    case 'method':
      if (containerKind !== 'class') {
        return [];
      }
      return [
        ts.SyntaxKind.PublicKeyword,
        ts.SyntaxKind.PrivateKeyword,
        ts.SyntaxKind.ProtectedKeyword,
        ts.SyntaxKind.StaticKeyword,
        ts.SyntaxKind.AbstractKeyword,
      ];
    case 'constructor':
      return [
        ts.SyntaxKind.PublicKeyword,
        ts.SyntaxKind.PrivateKeyword,
        ts.SyntaxKind.ProtectedKeyword,
      ];
    case 'indexSignature':
      return [ts.SyntaxKind.ReadonlyKeyword];
    default:
      return [];
  }
}

function validateModifiers(state, node, ownerId, allowedKinds) {
  for (const modifier of node.modifiers ?? []) {
    if (!allowedKinds.includes(modifier.kind)) {
      throwUnclassifiedPublicSyntax(
        state,
        modifier,
        ownerId,
        'modifier',
      );
    }
  }
}

function hasModifier(node, kind) {
  return node.modifiers?.some((modifier) => modifier.kind === kind) ?? false;
}

function declarationVisibility(node) {
  if (node.name && ts.isPrivateIdentifier(node.name)) {
    return 'private';
  }
  if (hasModifier(node, ts.SyntaxKind.PrivateKeyword)) {
    return 'private';
  }
  if (hasModifier(node, ts.SyntaxKind.ProtectedKeyword)) {
    return 'protected';
  }
  return 'public';
}

function effectiveVisibility(inheritedVisibility, declaredVisibility) {
  const rank = {public: 0, protected: 1, private: 2};
  return rank[inheritedVisibility] >= rank[declaredVisibility]
    ? inheritedVisibility
    : declaredVisibility;
}

function initialCoverage(visibility) {
  if (visibility !== 'public') {
    return {
      discovery: 'discovered',
      semantics: 'excluded',
      binding: 'excluded',
      host: 'notApplicable',
    };
  }
  return {
    discovery: 'discovered',
    semantics: 'pending',
    binding: 'pending',
    host: 'pending',
  };
}

function isDeprecated(node) {
  return ts.getJSDocDeprecatedTag(node) !== undefined;
}

function throwUnclassifiedPublicSyntax(state, node, ownerId, category) {
  const syntaxKind = ts.SyntaxKind[node.kind];
  const snippet = node
    .getText(state.sourceFile)
    .replace(/\s+/g, ' ')
    .trim();
  const error = new Error(
    `${state.sourceFile.fileName}: unclassified public ${category} ` +
      `${syntaxKind} under ${ownerId}: ${snippet}`,
  );
  error.code = 'UNCLASSIFIED_PUBLIC_SYNTAX';
  throw error;
}

module.exports = {importVscodeDeclarations};
