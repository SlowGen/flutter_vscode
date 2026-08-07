part of '../generator.dart';

// Concerns whether a declaration is the shape a selected strategy claims it is.

bool _strategyAcceptsDeclaration(
  String strategy,
  Map<String, Object?> declaration,
) {
  const nonGenericCallableStrategies = <String>{
    'commandRegistration',
    'disposeMethod',
    'eventSubscription',
    'hoverProviderRegistration',
    'markdownHoverConstructor',
    'markdownStringConstructor',
    'numericRangeConstructor',
    'providerCallback',
    'thenableBoolMethod',
    'unaryUriMethod',
    'uriJoinPath',
    'uriToString',
    'webviewPanelCreation',
  };
  if (nonGenericCallableStrategies.contains(strategy) &&
      !_hasTypeParameterCount(declaration, 0)) {
    return false;
  }
  final kind = declaration['kind'];
  final parameters = _declarationParameters(declaration);
  final type = declaration['type'];
  final returnType = declaration['returnType'];
  switch (strategy) {
    case 'namespaceObject':
      return kind == 'namespace';
    case 'nativeJsClass':
      return kind == 'class' && _hasTypeParameterCount(declaration, 0);
    case 'opaqueHostObject':
      return (kind == 'class' || kind == 'interface') &&
          _hasTypeParameterCount(declaration, 0);
    case 'opaqueJsObject':
      return kind == 'class' || kind == 'interface';
    case 'nativeJsEnum':
      return kind == 'enum';
    case 'intEnumMember':
      final initializer = declaration['initializer'];
      return kind == 'enumMember' &&
          initializer is Map<Object?, Object?> &&
          initializer['kind'] == 'literal' &&
          initializer['value'] is int;
    case 'eventType':
      return kind == 'interface' &&
          _hasUnboundedSingleTypeParameter(declaration);
    case 'thenableFutureBridge':
      return kind == 'interface' &&
          _hasUnboundedSingleTypeParameter(declaration) &&
          _extendsSingleTypeParameter(declaration, 'PromiseLike');
    case 'providerObject':
    case 'jsObjectLiteral':
      return kind == 'interface' &&
          _hasTypeParameterCount(declaration, 0) &&
          _hasNoHeritage(declaration);
    case 'disposableStructuralType':
      return kind == 'typeLiteral';
    case 'reviewedExcluded':
      return true;
    case 'boolGetterProjection':
      return _isProperty(
            declaration,
            readonly: null,
            optional: false,
          ) &&
          _isType(type, kind: 'primitive', name: 'boolean');
    case 'boolObjectField':
      return _isProperty(
            declaration,
            readonly: true,
            optional: true,
          ) &&
          _isType(type, kind: 'primitive', name: 'boolean');
    case 'intGetterProjection':
      return _isProperty(
            declaration,
            readonly: true,
            optional: false,
          ) &&
          _isType(type, kind: 'primitive', name: 'number');
    case 'stringGetterProjection':
      return _isProperty(
            declaration,
            readonly: true,
            optional: false,
          ) &&
          _isType(type, kind: 'primitive', name: 'string');
    case 'stringGetterSetterProjection':
      return _isProperty(
            declaration,
            readonly: false,
            optional: false,
          ) &&
          _isType(type, kind: 'primitive', name: 'string');
    case 'objectGetterProjection':
      return _isProperty(
            declaration,
            readonly: true,
            optional: false,
          ) &&
          _isType(type, kind: 'reference');
    case 'eventValue':
      return (kind == 'variable' ||
              _isProperty(
                declaration,
                readonly: true,
                optional: false,
              )) &&
          _isReferenceWithTypeArgumentCount(type, 1);
    case 'voidEventValue':
      return _isProperty(
            declaration,
            readonly: true,
            optional: false,
          ) &&
          _isReferenceWithSingleArgument(type, null, 'primitive', 'void');
    case 'subscriptionsArray':
      return _isProperty(
            declaration,
            readonly: true,
            optional: false,
          ) &&
          _isType(type, kind: 'array');
    case 'uriArrayObjectField':
      return _isProperty(
            declaration,
            readonly: true,
            optional: true,
          ) &&
          _isReadonlyArrayOfReference(type);
    case 'disposeMethod':
      return _isMethod(declaration, isStatic: false) &&
          parameters.isEmpty &&
          _isType(returnType, kind: 'primitive', name: 'any');
    case 'eventSubscription':
      return kind == 'callSignature' &&
          parameters.length == 3 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: true, rest: false),
            (optional: true, rest: false),
          ]) &&
          _isType(parameters.first['type'], kind: 'function') &&
          _isType(parameters[1]['type'], kind: 'primitive', name: 'any') &&
          _isType(returnType, kind: 'reference');
    case 'commandExecution':
      return kind == 'function' &&
          _hasUnknownDefaultSingleTypeParameter(declaration) &&
          parameters.length == 2 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: true),
          ]) &&
          _isType(parameters[0]['type'], kind: 'primitive', name: 'string') &&
          _referencesSingleTypeParameter(returnType, declaration);
    case 'commandRegistration':
      return kind == 'function' &&
          parameters.length == 3 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: false),
            (optional: true, rest: false),
          ]) &&
          _isType(parameters[0]['type'], kind: 'primitive', name: 'string') &&
          _isType(parameters[1]['type'], kind: 'function') &&
          _isType(parameters[2]['type'], kind: 'primitive', name: 'any') &&
          _isType(returnType, kind: 'reference');
    case 'hoverProviderRegistration':
      return kind == 'function' &&
          parameters.length == 2 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: false),
          ]) &&
          parameters.every(
            (parameter) => _isType(parameter['type'], kind: 'reference'),
          ) &&
          _isType(returnType, kind: 'reference');
    case 'webviewPanelCreation':
      return kind == 'function' &&
          parameters.length == 4 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: false),
            (optional: false, rest: false),
            (optional: true, rest: false),
          ]) &&
          _isType(parameters[0]['type'], kind: 'primitive', name: 'string') &&
          _isType(parameters[1]['type'], kind: 'primitive', name: 'string') &&
          _isType(returnType, kind: 'reference');
    case 'providerCallback':
      return _isMethod(declaration, isStatic: false) &&
          parameters.length == 3 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: false),
            (optional: false, rest: false),
          ]) &&
          parameters.every(
            (parameter) => _isType(parameter['type'], kind: 'reference'),
          ) &&
          _isType(returnType, kind: 'reference');
    case 'markdownStringConstructor':
      return kind == 'constructor' &&
          parameters.length == 2 &&
          _hasParameterFlags(parameters, const [
            (optional: true, rest: false),
            (optional: true, rest: false),
          ]) &&
          _isType(parameters[0]['type'], kind: 'primitive', name: 'string') &&
          _isType(parameters[1]['type'], kind: 'primitive', name: 'boolean');
    case 'markdownHoverConstructor':
      return kind == 'constructor' &&
          parameters.length == 2 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: true, rest: false),
          ]) &&
          _isType(parameters[1]['type'], kind: 'reference');
    case 'numericRangeConstructor':
      return kind == 'constructor' &&
          parameters.length == 4 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: false),
            (optional: false, rest: false),
            (optional: false, rest: false),
          ]) &&
          parameters.every(
            (parameter) =>
                _isType(parameter['type'], kind: 'primitive', name: 'number'),
          );
    case 'thenableBoolMethod':
      return _isMethod(declaration, isStatic: false) &&
          parameters.length == 1 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
          ]) &&
          _isType(
            parameters.single['type'],
            kind: 'primitive',
            name: 'any',
          ) &&
          _isReferenceWithSingleArgument(
            returnType,
            null,
            'primitive',
            'boolean',
          );
    case 'unaryUriMethod':
      return _isMethod(declaration, isStatic: false) &&
          parameters.length == 1 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
          ]) &&
          _isType(parameters.first['type'], kind: 'reference') &&
          _sameReference(parameters.first['type'], returnType);
    case 'uriJoinPath':
      return _isMethod(declaration, isStatic: true) &&
          parameters.length == 2 &&
          _hasParameterFlags(parameters, const [
            (optional: false, rest: false),
            (optional: false, rest: true),
          ]) &&
          _isType(parameters[0]['type'], kind: 'reference') &&
          _isArrayOfPrimitive(parameters[1]['type'], 'string') &&
          _sameReference(parameters[0]['type'], returnType);
    case 'uriToString':
      return _isMethod(declaration, isStatic: false) &&
          parameters.length == 1 &&
          _hasParameterFlags(parameters, const [
            (optional: true, rest: false),
          ]) &&
          _isType(
            parameters.first['type'],
            kind: 'primitive',
            name: 'boolean',
          ) &&
          _isType(returnType, kind: 'primitive', name: 'string');
    case 'stringSelectorProjection':
      return kind == 'typeAlias' && _unionContainsString(type);
    case 'providerResultProjection':
      return kind == 'typeAlias' &&
          _hasUnboundedSingleTypeParameter(declaration) &&
          _isType(type, kind: 'union');
  }
  return false;
}

List<Map<String, Object?>> _declarationParameters(
  Map<String, Object?> declaration,
) => objectList(
  declaration['parameters'] ?? const <Object?>[],
  'declaration.parameters',
).map((value) => objectMap(value, 'declaration parameter')).toList();

bool _isProperty(
  Map<String, Object?> declaration, {
  required bool? readonly,
  required bool optional,
}) =>
    declaration['kind'] == 'property' &&
    (readonly == null || declaration['readonly'] == readonly) &&
    declaration['optional'] == optional &&
    declaration['static'] == false;

bool _isMethod(
  Map<String, Object?> declaration, {
  required bool isStatic,
}) =>
    declaration['kind'] == 'method' &&
    declaration['static'] == isStatic &&
    declaration['optional'] == false;

bool _hasParameterFlags(
  List<Map<String, Object?>> parameters,
  List<({bool optional, bool rest})> expected,
) =>
    parameters.length == expected.length &&
    Iterable<int>.generate(parameters.length).every(
      (index) =>
          parameters[index]['optional'] == expected[index].optional &&
          parameters[index]['rest'] == expected[index].rest,
    );
