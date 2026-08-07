part of '../ir_validator.dart';

// Validates canonical signatures and the raw/canonical equality they imply.

void _validateIrCanonicalSignature(
  Object? value,
  String path, {
  List<List<String?>> inheritedScopes = const [],
  List<String?>? localTypeParameterNames,
  Set<String> extraKeys = const {},
}) {
  final serialized = string(value, path);
  Object? decoded;
  try {
    decoded = jsonDecode(serialized);
  } on FormatException {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must contain canonical v1 IR JSON.',
    );
  }
  _validateIrCanonicalSignatureObject(
    decoded,
    path,
    inheritedScopes: inheritedScopes,
    localTypeParameterNames: localTypeParameterNames,
    extraKeys: extraKeys,
  );
  if (jsonEncode(decoded) != serialized) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must use canonical producer JSON bytes.',
    );
  }
}

void _validateIrCanonicalSignatureObject(
  Object? value,
  String path, {
  List<List<String?>> inheritedScopes = const [],
  List<String?>? localTypeParameterNames,
  Set<String> extraKeys = const {},
}) {
  final signature = objectMap(value, path);
  validateIrExactKeys(
    signature,
    {'typeParameters', 'parameters', 'returnType', ...extraKeys},
    path: path,
  );
  final typeParameters = objectList(
    signature['typeParameters'],
    '$path.typeParameters',
  );
  if (localTypeParameterNames != null &&
      localTypeParameterNames.length != typeParameters.length) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.typeParameters must match the raw type-parameter count.',
    );
  }
  final localScope =
      localTypeParameterNames ??
      List<String?>.filled(typeParameters.length, null);
  final activeScopes = [...inheritedScopes, localScope];
  for (var index = 0; index < typeParameters.length; index += 1) {
    final parameterPath = '$path.typeParameters[$index]';
    final parameter = objectMap(typeParameters[index], parameterPath);
    validateIrExactKeys(
      parameter,
      const {},
      optionalKeys: const {'constraint', 'default'},
      path: parameterPath,
    );
    if (parameter.containsKey('constraint')) {
      _validateIrCanonicalType(
        parameter['constraint'],
        '$parameterPath.constraint',
        typeParameterScopes: activeScopes,
      );
    }
    if (parameter.containsKey('default')) {
      _validateIrCanonicalType(
        parameter['default'],
        '$parameterPath.default',
        typeParameterScopes: activeScopes,
      );
    }
  }
  final parameters = objectList(signature['parameters'], '$path.parameters');
  for (var index = 0; index < parameters.length; index += 1) {
    final parameterPath = '$path.parameters[$index]';
    final parameter = objectMap(parameters[index], parameterPath);
    validateIrExactKeys(
      parameter,
      const {'optional', 'rest', 'type'},
      path: parameterPath,
    );
    _validateIrBoolean(parameter['optional'], '$parameterPath.optional');
    _validateIrBoolean(parameter['rest'], '$parameterPath.rest');
    _validateIrCanonicalType(
      parameter['type'],
      '$parameterPath.type',
      typeParameterScopes: activeScopes,
    );
  }
  _validateIrCanonicalType(
    signature['returnType'],
    '$path.returnType',
    typeParameterScopes: activeScopes,
  );
  for (final key in extraKeys) {
    _validateIrBoolean(signature[key], '$path.$key');
  }
}

void _validateIrCallableCanonicalEquality(
  Map<String, Object?> declaration,
  String path, {
  required List<List<String?>> inheritedScopes,
}) {
  final extraKeys = switch (declaration['kind']) {
    'method' => const ['static', 'optional'],
    'indexSignature' => const ['readonly'],
    _ => const <String>[],
  };
  _validateIrRawCanonicalEquality(
    declaration,
    path,
    inheritedScopes: inheritedScopes,
    extraKeys: extraKeys,
  );
}

void _validateIrFunctionTypeCanonicalEquality(
  Map<String, Object?> type,
  String path, {
  required List<List<String?>> inheritedScopes,
}) {
  _validateIrRawCanonicalEquality(
    type,
    path,
    inheritedScopes: inheritedScopes,
  );
}

void _validateIrRawCanonicalEquality(
  Map<String, Object?> raw,
  String path, {
  required List<List<String?>> inheritedScopes,
  List<String> extraKeys = const [],
}) {
  final rawTypeParameters = objectList(
    raw['typeParameters'],
    '$path.typeParameters',
  );
  final ownScope = <String?>[
    for (var index = 0; index < rawTypeParameters.length; index += 1)
      string(
        objectMap(
          rawTypeParameters[index],
          '$path.typeParameters[$index]',
        )['name'],
        '$path.typeParameters[$index].name',
      ),
  ];
  final activeScopes = [...inheritedScopes, ownScope];
  final expectedTypeParameters = <Object?>[
    for (var index = 0; index < rawTypeParameters.length; index += 1)
      _canonicalizeIrTypeParameter(
        objectMap(
          rawTypeParameters[index],
          '$path.typeParameters[$index]',
        ),
        activeScopes,
      ),
  ];
  final rawParameters = objectList(raw['parameters'], '$path.parameters');
  final expectedParameters = <Object?>[
    for (var index = 0; index < rawParameters.length; index += 1)
      _canonicalizeIrParameter(
        objectMap(rawParameters[index], '$path.parameters[$index]'),
        activeScopes,
      ),
  ];
  final expected = <String, Object?>{
    'typeParameters': expectedTypeParameters,
    'parameters': expectedParameters,
    'returnType': _canonicalizeIrType(raw['returnType'], activeScopes),
    for (final key in extraKeys) key: raw[key],
  };
  final actual = string(
    raw['canonicalSignature'],
    '$path.canonicalSignature',
  );
  final expectedJson = jsonEncode(expected);
  if (actual != expectedJson) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.canonicalSignature must equal the mechanically canonicalized raw '
          'signature $expectedJson.',
    );
  }
}

Map<String, Object?> _canonicalizeIrTypeParameter(
  Map<String, Object?> parameter,
  List<List<String?>> scopes,
) {
  return {
    if (parameter.containsKey('constraint'))
      'constraint': _canonicalizeIrType(parameter['constraint'], scopes),
    if (parameter.containsKey('default'))
      'default': _canonicalizeIrType(parameter['default'], scopes),
  };
}

Map<String, Object?> _canonicalizeIrParameter(
  Map<String, Object?> parameter,
  List<List<String?>> scopes,
) {
  return {
    'optional': parameter['optional'],
    'rest': parameter['rest'],
    'type': _canonicalizeIrType(parameter['type'], scopes),
  };
}

Object? _canonicalizeIrType(
  Object? value,
  List<List<String?>> scopes,
) {
  final type = objectMap(value, 'IR type');
  final kind = type['kind'];
  if (kind == 'reference') {
    final name = type['name'];
    for (var scopeIndex = scopes.length - 1; scopeIndex >= 0; scopeIndex -= 1) {
      final index = scopes[scopeIndex].indexOf(name as String?);
      if (index < 0) {
        continue;
      }
      final depth = scopes.length - 1 - scopeIndex;
      return depth == 0
          ? <String, Object?>{'kind': 'typeParameter', 'index': index}
          : <String, Object?>{
              'kind': 'outerTypeParameter',
              'depth': depth,
              'index': index,
            };
    }
  }
  return switch (kind) {
    'primitive' => <String, Object?>{
      'kind': kind,
      'name': type['name'],
    },
    'reference' => <String, Object?>{
      'kind': kind,
      'name': type['name'],
      'typeArguments': [
        for (final argument in objectList(
          type['typeArguments'],
          'IR type.typeArguments',
        ))
          _canonicalizeIrType(argument, scopes),
      ],
    },
    'array' => <String, Object?>{
      'kind': kind,
      'elementType': _canonicalizeIrType(type['elementType'], scopes),
    },
    'union' || 'intersection' => <String, Object?>{
      'kind': kind,
      'types': [
        for (final item in objectList(type['types'], 'IR type.types'))
          _canonicalizeIrType(item, scopes),
      ],
    },
    'literal' => <String, Object?>{
      'kind': kind,
      'value': type['value'],
    },
    'tuple' => <String, Object?>{
      'kind': kind,
      'elements': [
        for (final elementValue in objectList(
          type['elements'],
          'IR type.elements',
        ))
          _canonicalizeIrTupleElement(
            objectMap(elementValue, 'IR tuple element'),
            scopes,
          ),
      ],
    },
    'operator' => <String, Object?>{
      'kind': kind,
      'operator': type['operator'],
      'type': _canonicalizeIrType(type['type'], scopes),
    },
    'function' => <String, Object?>{
      'kind': kind,
      'canonicalSignature': type['canonicalSignature'],
    },
    'typeLiteral' => <String, Object?>{
      'kind': kind,
      'shapeHash': type['shapeHash'],
    },
    _ => value,
  };
}

Map<String, Object?> _canonicalizeIrTupleElement(
  Map<String, Object?> element,
  List<List<String?>> scopes,
) {
  return {
    'optional': element['optional'],
    'rest': element['rest'],
    'type': _canonicalizeIrType(element['type'], scopes),
  };
}

void _validateIrCanonicalType(
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
      final referenceName = string(type['name'], '$path.name');
      if (typeParameterScopes.any((scope) => scope.contains(referenceName))) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path reference $referenceName must use its canonical '
              'typeParameter or outerTypeParameter node.',
        );
      }
      final arguments = objectList(
        type['typeArguments'],
        '$path.typeArguments',
      );
      for (var index = 0; index < arguments.length; index += 1) {
        _validateIrCanonicalType(
          arguments[index],
          '$path.typeArguments[$index]',
          typeParameterScopes: typeParameterScopes,
        );
      }
    case 'array':
      validateIrExactKeys(type, const {'kind', 'elementType'}, path: path);
      _validateIrCanonicalType(
        type['elementType'],
        '$path.elementType',
        typeParameterScopes: typeParameterScopes,
      );
    case 'union' || 'intersection':
      validateIrExactKeys(type, const {'kind', 'types'}, path: path);
      final types = objectList(type['types'], '$path.types');
      for (var index = 0; index < types.length; index += 1) {
        _validateIrCanonicalType(
          types[index],
          '$path.types[$index]',
          typeParameterScopes: typeParameterScopes,
        );
      }
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
          path: elementPath,
        );
        _validateIrBoolean(element['optional'], '$elementPath.optional');
        _validateIrBoolean(element['rest'], '$elementPath.rest');
        _validateIrCanonicalType(
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
      _validateIrCanonicalType(
        type['type'],
        '$path.type',
        typeParameterScopes: typeParameterScopes,
      );
    case 'function':
      validateIrExactKeys(
        type,
        const {'kind', 'canonicalSignature'},
        path: path,
      );
      _validateIrCanonicalSignature(
        type['canonicalSignature'],
        '$path.canonicalSignature',
        inheritedScopes: typeParameterScopes,
      );
    case 'typeLiteral':
      validateIrExactKeys(
        type,
        const {'kind', 'shapeHash'},
        path: path,
      );
      _validateIrSha256(type['shapeHash'], '$path.shapeHash');
    case 'typeParameter':
      validateIrExactKeys(type, const {'kind', 'index'}, path: path);
      final index = _validateIrNonNegativeInteger(
        type['index'],
        '$path.index',
      );
      if (typeParameterScopes.isEmpty ||
          index >= typeParameterScopes.last.length) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path typeParameter index $index is outside its current scope.',
        );
      }
    case 'outerTypeParameter':
      validateIrExactKeys(
        type,
        const {'kind', 'depth', 'index'},
        path: path,
      );
      final depth = _validateIrNonNegativeInteger(
        type['depth'],
        '$path.depth',
      );
      final index = _validateIrNonNegativeInteger(
        type['index'],
        '$path.index',
      );
      if (depth < 1 || depth >= typeParameterScopes.length) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path outerTypeParameter depth $depth is outside its outer scopes.',
        );
      }
      final scope = typeParameterScopes[typeParameterScopes.length - 1 - depth];
      if (index >= scope.length) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path outerTypeParameter index $index is outside depth $depth.',
        );
      }
    default:
      _invalidIrValue('$path.kind', kind);
  }
}

String _encodeCanonicalJson(Object? value) {
  if (value is Map<Object?, Object?>) {
    final keys = <String>[];
    for (final key in value.keys) {
      if (key is! String) {
        throw const VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          'A declaration fingerprint contains a non-string JSON key.',
        );
      }
      keys.add(key);
    }
    keys.sort();
    return '{${[
      for (final key in keys) '${jsonEncode(key)}:${_encodeCanonicalJson(value[key])}',
    ].join(',')}}';
  }
  if (value is List<Object?>) {
    return '[${value.map(_encodeCanonicalJson).join(',')}]';
  }
  return jsonEncode(value);
}
