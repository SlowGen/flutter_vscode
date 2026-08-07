part of '../generator.dart';

// Concerns the type-shape questions the strategy matchers are built from.

bool _hasTypeParameterCount(
  Map<String, Object?> declaration,
  int expected,
) =>
    declaration['typeParameters'] is List<Object?> &&
    (declaration['typeParameters']! as List<Object?>).length == expected;

bool _hasUnboundedSingleTypeParameter(Map<String, Object?> declaration) {
  final parameters = declaration['typeParameters'];
  if (parameters is! List<Object?> || parameters.length != 1) {
    return false;
  }
  final parameter = parameters.single;
  return parameter is Map<Object?, Object?> &&
      parameter.keys.toSet().length == 1 &&
      parameter.keys.single == 'name' &&
      parameter['name'] is String;
}

bool _hasUnknownDefaultSingleTypeParameter(
  Map<String, Object?> declaration,
) {
  final parameters = declaration['typeParameters'];
  if (parameters is! List<Object?> || parameters.length != 1) {
    return false;
  }
  final parameter = parameters.single;
  return parameter is Map<Object?, Object?> &&
      parameter.keys.toSet().length == 2 &&
      parameter.containsKey('name') &&
      parameter.containsKey('default') &&
      parameter['name'] is String &&
      _isType(parameter['default'], kind: 'primitive', name: 'unknown');
}

bool _hasNoHeritage(Map<String, Object?> declaration) {
  final heritage = declaration['extends'];
  return heritage is List<Object?> && heritage.isEmpty;
}

bool _isArrayOfPrimitive(Object? value, String primitiveName) {
  if (!_isType(value, kind: 'array')) {
    return false;
  }
  return _isType(
    (value! as Map<Object?, Object?>)['elementType'],
    kind: 'primitive',
    name: primitiveName,
  );
}

bool _referencesSingleTypeParameter(
  Object? value,
  Map<String, Object?> declaration,
) {
  final typeParameters = declaration['typeParameters'];
  if (typeParameters is! List<Object?> || typeParameters.length != 1) {
    return false;
  }
  final parameter = typeParameters.single;
  if (parameter is! Map<Object?, Object?> || parameter['name'] is! String) {
    return false;
  }
  return _isReferenceWithSingleArgument(
    value,
    null,
    'reference',
    parameter['name']! as String,
  );
}

bool _functionConsumesSingleTypeParameter(
  Object? value,
  Map<String, Object?> declaration,
) {
  if (!_isType(value, kind: 'function')) {
    return false;
  }
  final function = value! as Map<Object?, Object?>;
  final parameters = function['parameters'];
  if (parameters is! List<Object?> || parameters.length != 1) {
    return false;
  }
  final parameter = parameters.single;
  if (parameter is! Map<Object?, Object?> ||
      parameter['optional'] != false ||
      parameter['rest'] != false) {
    return false;
  }
  return _isSingleTypeParameterReference(parameter['type'], declaration);
}

bool _isSingleTypeParameterReference(
  Object? value,
  Map<String, Object?> declaration,
) {
  final typeParameters = declaration['typeParameters'];
  if (typeParameters is! List<Object?> || typeParameters.length != 1) {
    return false;
  }
  final parameter = typeParameters.single;
  if (parameter is! Map<Object?, Object?> || parameter['name'] is! String) {
    return false;
  }
  if (!_isType(value, kind: 'reference', name: parameter['name']! as String)) {
    return false;
  }
  final typeArguments = (value! as Map<Object?, Object?>)['typeArguments'];
  return typeArguments is List<Object?> && typeArguments.isEmpty;
}

bool _extendsSingleTypeParameter(
  Map<String, Object?> declaration,
  String parentName,
) {
  final heritage = declaration['extends'];
  if (heritage is! List<Object?> || heritage.length != 1) {
    return false;
  }
  final parent = heritage.single;
  return _isType(parent, kind: 'reference', name: parentName) &&
      _referencesSingleTypeParameter(parent, declaration);
}

bool _isProviderResultProjection(
  Map<String, Object?> declaration,
  String thenableName,
) {
  final type = declaration['type'];
  if (!_isType(type, kind: 'union')) {
    return false;
  }
  final types = (type! as Map<Object?, Object?>)['types'];
  if (types is! List<Object?> || types.length != 4) {
    return false;
  }
  bool isThenableMember(Object? candidate) {
    if (!_isType(candidate, kind: 'reference', name: thenableName)) {
      return false;
    }
    final arguments = (candidate! as Map<Object?, Object?>)['typeArguments'];
    return arguments is List<Object?> &&
        arguments.length == 1 &&
        _isNullableTypeParameterUnion(arguments.single, declaration);
  }

  return types
              .where(
                (candidate) =>
                    _isSingleTypeParameterReference(candidate, declaration),
              )
              .length ==
          1 &&
      types.where(_isUndefinedType).length == 1 &&
      types.where(_isNullLiteralType).length == 1 &&
      types.where(isThenableMember).length == 1;
}

bool _isNullableTypeParameterUnion(
  Object? value,
  Map<String, Object?> declaration,
) {
  if (!_isType(value, kind: 'union')) {
    return false;
  }
  final types = (value! as Map<Object?, Object?>)['types'];
  return types is List<Object?> &&
      types.length == 3 &&
      types
              .where(
                (candidate) =>
                    _isSingleTypeParameterReference(candidate, declaration),
              )
              .length ==
          1 &&
      types.where(_isUndefinedType).length == 1 &&
      types.where(_isNullLiteralType).length == 1;
}

bool _isUndefinedType(Object? value) =>
    _isType(value, kind: 'primitive', name: 'undefined');

bool _isNullLiteralType(Object? value) {
  if (!_isType(value, kind: 'literal')) {
    return false;
  }
  final literal = value! as Map<Object?, Object?>;
  return literal.containsKey('value') && literal['value'] == null;
}

bool _unionContainsString(Object? value) {
  if (!_isType(value, kind: 'union')) {
    return false;
  }
  final types = (value! as Map<Object?, Object?>)['types'];
  return types is List<Object?> &&
      types.any(
        (candidate) => _isType(candidate, kind: 'primitive', name: 'string'),
      );
}

bool _isType(Object? value, {required String kind, String? name}) {
  if (value is! Map<Object?, Object?> || value['kind'] != kind) {
    return false;
  }
  return name == null || value['name'] == name;
}

bool _isReferenceWithSingleArgument(
  Object? value,
  String? referenceName,
  String argumentKind,
  String argumentName,
) {
  if (!_isType(value, kind: 'reference', name: referenceName)) {
    return false;
  }
  final reference = value! as Map<Object?, Object?>;
  final arguments = reference['typeArguments'];
  return arguments is List<Object?> &&
      arguments.length == 1 &&
      _isType(arguments.single, kind: argumentKind, name: argumentName);
}

bool _isReferenceWithTypeArgumentCount(Object? value, int count) {
  if (!_isType(value, kind: 'reference')) {
    return false;
  }
  final arguments = (value! as Map<Object?, Object?>)['typeArguments'];
  return arguments is List<Object?> && arguments.length == count;
}

bool _isReadonlyArrayOfReference(Object? value) {
  if (!_isType(value, kind: 'operator')) {
    return false;
  }
  final operator = value! as Map<Object?, Object?>;
  final array = operator['type'];
  return operator['operator'] == 'readonly' &&
      _isType(array, kind: 'array') &&
      _isType(
        (array! as Map<Object?, Object?>)['elementType'],
        kind: 'reference',
      );
}

bool _sameReference(Object? left, Object? right) =>
    _isType(left, kind: 'reference') &&
    _isType(right, kind: 'reference') &&
    (left! as Map<Object?, Object?>)['name'] ==
        (right! as Map<Object?, Object?>)['name'];

String _dartIdentifier(Object? value, String path) {
  final identifier = string(value, path);
  if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(identifier)) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path $identifier is not a Dart identifier.',
    );
  }
  return identifier;
}
