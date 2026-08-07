part of '../ir_validator.dart';

// Validates type references, parameters, and heritage across declarations.

/// Returns the type-parameter scopes one declaration inherits.
List<List<String?>> irInheritedTypeParameterScopes(
  Map<String, Object?> declaration,
  Map<String, Map<String, Object?>> declarationsById,
  String path,
) {
  final ancestors = <Map<String, Object?>>[];
  var parentId = string(declaration['parentId'], '$path.parentId');
  final seen = <String>{};
  while (parentId != 'module:vscode' && parentId != 'global:global') {
    if (!seen.add(parentId)) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.parentId participates in a declaration cycle.',
      );
    }
    final parent = declarationsById[parentId];
    if (parent == null) {
      return const [];
    }
    ancestors.add(parent);
    parentId = string(parent['parentId'], '$path.parentId');
  }
  final scopes = <List<String?>>[];
  for (final ancestor in ancestors.reversed) {
    if (_irDeclarationContributesTypeParameterScope(ancestor)) {
      scopes.add(_irTypeParameterNames(ancestor['typeParameters']));
    }
  }
  return scopes;
}

bool _irDeclarationContributesTypeParameterScope(
  Map<String, Object?> declaration,
) {
  return const {
    'interface',
    'class',
    'typeAlias',
    'function',
    'constructor',
    'callSignature',
    'method',
    'indexSignature',
  }.contains(declaration['kind']);
}

List<String?> _irTypeParameterNames(Object? value) {
  return [
    for (final parameter in objectList(value, 'typeParameters'))
      string(
        objectMap(parameter, 'typeParameters entry')['name'],
        'typeParameters entry.name',
      ),
  ];
}

/// Validates every type reference in one inventory declaration.
void validateIrDeclarationTypes(
  Map<String, Object?> declaration,
  String path, {
  required List<List<String?>> inheritedScopes,
}) {
  final kind = declaration['kind'];
  if (kind == 'interface' || kind == 'class') {
    _validateIrTypeParameterTypes(
      declaration['typeParameters'],
      '$path.typeParameters',
      inheritedScopes: inheritedScopes,
    );
    _validateIrHeritageTypes(declaration['extends'], '$path.extends');
    if (kind == 'class') {
      _validateIrHeritageTypes(
        declaration['implements'],
        '$path.implements',
      );
    }
    return;
  }
  if (kind == 'typeAlias') {
    final ownScope = _validateIrTypeParameterTypes(
      declaration['typeParameters'],
      '$path.typeParameters',
      inheritedScopes: inheritedScopes,
    );
    _validateIrType(
      declaration['type'],
      '$path.type',
      typeParameterScopes: [...inheritedScopes, ownScope],
    );
    return;
  }
  if (kind == 'variable' || kind == 'property') {
    _validateIrType(
      declaration['type'],
      '$path.type',
      typeParameterScopes: inheritedScopes,
    );
    return;
  }
  if (kind == 'enumMember') {
    _validateIrExpression(declaration['initializer'], '$path.initializer');
    return;
  }
  if (const {
    'function',
    'constructor',
    'callSignature',
    'method',
    'indexSignature',
  }.contains(kind)) {
    final ownScope = _validateIrTypeParameterTypes(
      declaration['typeParameters'],
      '$path.typeParameters',
      inheritedScopes: inheritedScopes,
    );
    final activeScopes = [...inheritedScopes, ownScope];
    _validateIrParameterTypes(
      declaration['parameters'],
      '$path.parameters',
      typeParameterScopes: activeScopes,
    );
    _validateIrType(
      declaration['returnType'],
      '$path.returnType',
      typeParameterScopes: activeScopes,
    );
    _validateIrCanonicalSignature(
      declaration['canonicalSignature'],
      '$path.canonicalSignature',
      inheritedScopes: inheritedScopes,
      localTypeParameterNames: ownScope,
      extraKeys: switch (kind) {
        'method' => const {'static', 'optional'},
        'indexSignature' => const {'readonly'},
        _ => const {},
      },
    );
    _validateIrCallableCanonicalEquality(
      declaration,
      path,
      inheritedScopes: inheritedScopes,
    );
  }
}

void _validateIrHeritageTypes(Object? value, String path) {
  final types = objectList(value, path);
  for (var index = 0; index < types.length; index += 1) {
    final typePath = '$path[$index]';
    final type = objectMap(types[index], typePath);
    if (type['kind'] != 'reference') {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$typePath must be a producer reference heritage node.',
      );
    }
    _validateIrType(type, typePath);
  }
}

void _validateIrTypes(
  Object? value,
  String path, {
  List<List<String?>> typeParameterScopes = const [],
}) {
  final types = objectList(value, path);
  for (var index = 0; index < types.length; index += 1) {
    _validateIrType(
      types[index],
      '$path[$index]',
      typeParameterScopes: typeParameterScopes,
    );
  }
}

void _validateIrParameterTypes(
  Object? value,
  String path, {
  List<List<String?>> typeParameterScopes = const [],
}) {
  final parameters = objectList(value, path);
  for (var index = 0; index < parameters.length; index += 1) {
    final parameterPath = '$path[$index]';
    final parameter = objectMap(parameters[index], parameterPath);
    validateIrExactKeys(
      parameter,
      const {'name', 'optional', 'rest', 'type'},
      path: parameterPath,
    );
    nonEmptyString(parameter['name'], '$parameterPath.name');
    _validateIrBoolean(parameter['optional'], '$parameterPath.optional');
    _validateIrBoolean(parameter['rest'], '$parameterPath.rest');
    _validateIrType(
      parameter['type'],
      '$parameterPath.type',
      typeParameterScopes: typeParameterScopes,
    );
  }
}

List<String?> _validateIrTypeParameterTypes(
  Object? value,
  String path, {
  List<List<String?>> inheritedScopes = const [],
}) {
  final parameters = objectList(value, path);
  final names = <String?>[];
  for (var index = 0; index < parameters.length; index += 1) {
    final parameterPath = '$path[$index]';
    final parameter = objectMap(parameters[index], parameterPath);
    validateIrExactKeys(
      parameter,
      const {'name'},
      optionalKeys: const {'constraint', 'default'},
      path: parameterPath,
    );
    names.add(nonEmptyString(parameter['name'], '$parameterPath.name'));
  }
  final activeScopes = [...inheritedScopes, names];
  for (var index = 0; index < parameters.length; index += 1) {
    final parameterPath = '$path[$index]';
    final parameter = objectMap(parameters[index], parameterPath);
    if (parameter.containsKey('constraint')) {
      _validateIrType(
        parameter['constraint'],
        '$parameterPath.constraint',
        typeParameterScopes: activeScopes,
      );
    }
    if (parameter.containsKey('default')) {
      _validateIrType(
        parameter['default'],
        '$parameterPath.default',
        typeParameterScopes: activeScopes,
      );
    }
  }
  return names;
}

void _validateIrType(
  Object? value,
  String path, {
  List<List<String?>> typeParameterScopes = const [],
}) {
  final type = objectMap(value, path);
  final kind = string(type['kind'], '$path.kind');
  switch (kind) {
    case 'primitive':
      validateIrExactKeys(type, const {'kind', 'name'}, path: path);
      final name = string(type['name'], '$path.name');
      if (!const {
        'any',
        'boolean',
        'never',
        'number',
        'object',
        'string',
        'undefined',
        'unknown',
        'void',
      }.contains(name)) {
        _invalidIrValue('$path.name', name);
      }
    case 'reference':
      validateIrExactKeys(
        type,
        const {'kind', 'name', 'typeArguments'},
        path: path,
      );
      nonEmptyString(type['name'], '$path.name');
      _validateIrTypes(
        type['typeArguments'],
        '$path.typeArguments',
        typeParameterScopes: typeParameterScopes,
      );
    case 'array':
      validateIrExactKeys(type, const {'kind', 'elementType'}, path: path);
      _validateIrType(
        type['elementType'],
        '$path.elementType',
        typeParameterScopes: typeParameterScopes,
      );
    case 'union' || 'intersection':
      validateIrExactKeys(type, const {'kind', 'types'}, path: path);
      _validateIrTypes(
        type['types'],
        '$path.types',
        typeParameterScopes: typeParameterScopes,
      );
    case 'literal':
      validateIrExactKeys(type, const {'kind', 'value'}, path: path);
      final literal = type['value'];
      if (literal != null &&
          literal is! String &&
          literal is! bool &&
          literal is! int) {
        _invalidIrValue('$path.value', literal);
      }
      if (literal is int) {
        _validateIrSafeInteger(literal, '$path.value');
      }
    case 'tuple':
      validateIrExactKeys(type, const {'kind', 'elements'}, path: path);
      final elements = objectList(type['elements'], '$path.elements');
      for (var index = 0; index < elements.length; index += 1) {
        final elementPath = '$path.elements[$index]';
        final element = objectMap(elements[index], elementPath);
        validateIrExactKeys(
          element,
          const {'optional', 'rest', 'type'},
          optionalKeys: const {'name'},
          path: elementPath,
        );
        if (element.containsKey('name')) {
          nonEmptyString(element['name'], '$elementPath.name');
        }
        _validateIrBoolean(element['optional'], '$elementPath.optional');
        _validateIrBoolean(element['rest'], '$elementPath.rest');
        _validateIrType(
          element['type'],
          '$elementPath.type',
          typeParameterScopes: typeParameterScopes,
        );
      }
    case 'operator':
      validateIrExactKeys(
        type,
        const {'kind', 'operator', 'type'},
        path: path,
      );
      final operator = string(type['operator'], '$path.operator');
      if (!const {'keyof', 'readonly', 'unique'}.contains(operator)) {
        _invalidIrValue('$path.operator', operator);
      }
      _validateIrType(
        type['type'],
        '$path.type',
        typeParameterScopes: typeParameterScopes,
      );
    case 'function':
      validateIrExactKeys(
        type,
        const {
          'kind',
          'typeParameters',
          'parameters',
          'returnType',
          'canonicalSignature',
        },
        path: path,
      );
      final ownScope = _validateIrTypeParameterTypes(
        type['typeParameters'],
        '$path.typeParameters',
        inheritedScopes: typeParameterScopes,
      );
      final activeScopes = [...typeParameterScopes, ownScope];
      _validateIrParameterTypes(
        type['parameters'],
        '$path.parameters',
        typeParameterScopes: activeScopes,
      );
      _validateIrType(
        type['returnType'],
        '$path.returnType',
        typeParameterScopes: activeScopes,
      );
      _validateIrCanonicalSignature(
        type['canonicalSignature'],
        '$path.canonicalSignature',
        inheritedScopes: typeParameterScopes,
        localTypeParameterNames: ownScope,
      );
      _validateIrFunctionTypeCanonicalEquality(
        type,
        path,
        inheritedScopes: typeParameterScopes,
      );
    case 'typeLiteral':
      final hasId = type.containsKey('id');
      final hasShape = type.containsKey('shape');
      if (hasId == hasShape) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path must contain exactly one of id or shape.',
        );
      }
      if (hasId) {
        validateIrExactKeys(
          type,
          const {'kind', 'id', 'shapeHash'},
          path: path,
        );
        nonEmptyString(type['id'], '$path.id');
      } else {
        validateIrExactKeys(
          type,
          const {'kind', 'shape', 'shapeHash'},
          path: path,
        );
        _validateIrTypeLiteralShape(
          type['shape'],
          '$path.shape',
          typeParameterScopes: typeParameterScopes,
        );
      }
      _validateIrSha256(type['shapeHash'], '$path.shapeHash');
      if (hasShape) {
        final actualHash = string(type['shapeHash'], '$path.shapeHash');
        final expectedHash = sha256
            .convert(utf8.encode(jsonEncode(type['shape'])))
            .toString();
        if (actualHash != expectedHash) {
          throw VSCodeBindingGenerationException(
            'INVALID_GENERATOR_INPUT',
            '$path.shapeHash must equal the SHA-256 of its canonical shape '
                '$expectedHash.',
          );
        }
      }
    default:
      _invalidIrValue('$path.kind', kind);
  }
}
