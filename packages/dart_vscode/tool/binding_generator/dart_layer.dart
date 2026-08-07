/// Emits the self-contained generated API layer: the Parity Layer
/// substrate inlined beneath the mechanical Dart-ergonomics layer
/// (developer-experience D-2).
///
/// The emitted library carries the substrate declarations (what
/// [ParityEmitter] emits) directly, so one artifact is the whole
/// generated API surface. The dart-layer rules are a second generated,
/// total, judgment-free rule set layered on the parity surface — NOT a
/// hand-reviewed facade. Every rule is deterministic over its construct
/// class and applied to every occurrence:
///
/// * boundary-de-js — generated helpers (constructors, rest calls, call
///   signatures, tuple accessors, `lit$` factories) whose parameters or
///   returns are `JSString`/`JSNumber`/`JSBoolean` (or their `?`) expose
///   ordinary `String`/`num`/`bool` with mechanical conversion; `JSAny`,
///   `JSObject`, and interface types pass through unchanged.
/// * future-from-promise — `JSPromise<T>` returns become `Future<T'>`
///   via `.toDart`, with `T'` de-JS'd where boundary-de-js applies.
/// * stream-from-event — parity `Event<T>` members gain a broadcast
///   `Stream<T'>` accessor beside the event (`onDidX` gains
///   `onDidXStream`): subscribe on first listen, dispose the returned
///   registration when the last listener cancels. The event itself stays
///   inherited — provider objects still take raw `Event` values.
/// * flattened-literal-factory — dart-layer `lit$` factories include the
///   full transitive interface hierarchy's members, resolved from the
///   IR's declared hierarchy.
/// * alias-named-wrapper — lives in the parity emitter: an
///   all-string-literal alias names its zero-cost wrapper after the alias.
/// * totality-accounting — every parity-layer declaration receives a
///   dart-layer disposition (emitted / passthrough-identical / carried
///   parity erasure); a construct the rules cannot consume fails
///   generation with the declaration id.
///
/// Each `XDart` extension type wraps and implements its parity type `X`,
/// so dart-layer values flow anywhere the parity surface is expected and
/// every unconverted member is inherited unchanged. Conversions replace
/// getters only; parity setters stay inherited. Trailing optional
/// arguments that are `null` are not forwarded (the parity helpers'
/// documented trimming semantics).
library;

import 'dart:convert';

import 'ir_type_mapper.dart';
import 'parity_layer.dart';

/// A construct reached the dart-layer emitter without a total rule.
final class DartLayerGenerationException implements Exception {
  /// Creates an actionable totality failure.
  DartLayerGenerationException(this.declarationId, this.message);

  /// The IR declaration that could not be consumed.
  final String declarationId;

  /// What rule is missing.
  final String message;

  @override
  String toString() => 'DART_LAYER_TOTALITY_ERROR: $declarationId: $message';
}

/// The generated artifacts: the self-contained Dart library, its
/// disposition ledger, and the substrate (parity) totality ledger.
typedef DartLayerArtifacts = ({
  String library,
  String ledger,
  String parityLedger,
});

/// The dart-layer rule classes: one per total rule. Each requires an
/// emitter unit case tagged `dc:<class>` in the dart-layer unit suite.
const dartLayerRuleClasses = [
  'boundary-de-js',
  'future-from-promise',
  'stream-from-event',
  'flattened-literal-factory',
  'alias-named-wrapper',
  'totality-accounting',
];

/// Builds the dart-layer library and its totality ledger from IR JSON.
DartLayerArtifacts emitDartLayer(Map<String, Object?> inventory) {
  final mapper = IrTypeMapper(inventory);
  return _DartLayerEmitter(mapper, ParityEmitter(mapper)).emit();
}

final class _DartLayerEmitter {
  _DartLayerEmitter(this.mapper, this.parity);

  final IrTypeMapper mapper;
  final ParityEmitter parity;
  final dispositions = <String, String>{};
  final _typeIdsWithDart = <String>{};
  final _classIdsWithCtorDart = <String>{};
  final _emittedAnonNames = <String>{};
  var _needsStreamHelper = false;

  DartLayerArtifacts emit() {
    final parityArtifacts = parity.emit();

    final anonTypes = StringBuffer();
    final namespaces = StringBuffer();
    final interfaces = StringBuffer();
    final classes = StringBuffer();

    for (final declaration in mapper.declarations) {
      if (!parity.isEmitted(declaration)) {
        continue;
      }
      final parent = declaration['parentId']! as String;
      final topLevel = parent == 'module:vscode' || parent == 'global:global';
      switch (declaration['kind']) {
        case 'interface' when topLevel:
          _emitInterfaceDart(declaration, interfaces);
        case 'class' when topLevel:
          _emitClassDart(declaration, classes);
        case 'namespace' when topLevel:
          _emitNamespaceDart(declaration, namespaces);
        case 'typeLiteral':
          _emitAnonDart(declaration, anonTypes);
        case 'typeAlias' || 'enum' when topLevel:
          break; // Already Dart-first in the parity layer.
        case 'variable' when parent == 'module:vscode':
          break; // Converted on the module root.
        case 'interface' || 'class' || 'enum' || 'typeAlias' || 'namespace':
        case 'property' ||
            'method' ||
            'constructor' ||
            'function' ||
            'variable' ||
            'enumMember' ||
            'indexSignature' ||
            'callSignature':
          break; // Converted as part of an owning surface.
        default:
          throw DartLayerGenerationException(
            declaration['id']! as String,
            'no dart-layer rule for declaration kind '
            "${declaration['kind']}",
          );
      }
    }

    final tuples = StringBuffer();
    _emitTupleDarts(tuples);
    final root = StringBuffer();
    _emitRootDart(root);

    final library = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln('//')
      ..writeln('// The self-contained generated VS Code API layer. It')
      ..writeln('// carries the complete typed Parity Layer substrate')
      ..writeln('// (ADR 0012, produced only by Total Mapping Rules) and,')
      ..writeln('// on top of it, the mechanical Dart-ergonomics layer')
      ..writeln('// (developer-experience D-2), produced only by total,')
      ..writeln('// judgment-free rules: helper boundaries take ordinary')
      ..writeln('// String/num/bool, JSPromise returns become Futures,')
      ..writeln('// Event members gain broadcast Stream accessors (onDidX')
      ..writeln(r'// gains onDidXStream), and lit$ factories flatten')
      ..writeln('// inherited interface members.')
      ..writeln('// Regenerate with:')
      ..writeln(
        '//   dart tool/binding_generator/generate.dart '
        '--dart-layer .',
      )
      ..writeln('//')
      ..writeln('// JS `undefined` and `null` both surface as Dart `null`')
      ..writeln('// (documented platform-wide conflation).')
      ..writeln('//')
      ..writeln('// Enter the layer with VscodeApi(rawVscode).dart; every')
      ..writeln('// XDart type wraps and implements its parity type X, so')
      ..writeln('// dart-layer values flow anywhere the parity surface is')
      ..writeln('// expected. Trailing optional arguments that are null are')
      ..writeln('// not forwarded (the parity trimming semantics).')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln("import 'dart:async';")
      ..writeln("import 'dart:js_interop';")
      ..writeln("import 'dart:js_interop_unsafe';")
      ..writeln()
      ..write(parity.body)
      ..writeln()
      ..write(tuples)
      ..write(anonTypes)
      ..write(namespaces)
      ..write(interfaces)
      ..write(classes)
      ..write(root);
    if (_needsStreamHelper) {
      library.write(_streamHelperSource);
    }

    final ledgerEntries = <String, String>{};
    for (final declaration in mapper.declarations) {
      final id = declaration['id']! as String;
      final parityDisposition = parity.dispositions[id]!;
      ledgerEntries[id] = parityDisposition != 'emitted'
          ? 'parity:$parityDisposition'
          : (dispositions[id] ?? 'passthrough-identical');
    }
    final ledger = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'dispositions': ledgerEntries,
    });
    return (
      library: library.toString(),
      ledger: '$ledger\n',
      parityLedger: parityArtifacts.ledger,
    );
  }

  // ------------------------------------------------------------ conversions

  /// The Dart counterpart of a scalar JS type, or `null` when the type
  /// passes through unchanged (boundary-de-js applies to naked scalars
  /// only).
  String? _deJs(String type) => switch (type) {
    'JSString' => 'String',
    'JSString?' => 'String?',
    'JSNumber' => 'num',
    'JSNumber?' => 'num?',
    'JSBoolean' => 'bool',
    'JSBoolean?' => 'bool?',
    _ => null,
  };

  String _toJsExpression(String dartType, String name) =>
      dartType.endsWith('?') ? '$name?.toJS' : '$name.toJS';

  String _fromJsSuffix(String jsType) => switch (jsType) {
    'JSString' => '.toDart',
    'JSString?' => '?.toDart',
    'JSNumber' => '.toDartDouble',
    'JSNumber?' => '?.toDartDouble',
    'JSBoolean' => '.toDart',
    'JSBoolean?' => '?.toDart',
    _ => '',
  };

  String _promiseThen(String inner) => switch (inner) {
    'JSString' => '.then((value) => value.toDart)',
    'JSString?' => '.then((value) => value?.toDart)',
    'JSNumber' => '.then((value) => value.toDartDouble)',
    'JSNumber?' => '.then((value) => value?.toDartDouble)',
    'JSBoolean' => '.then((value) => value.toDart)',
    'JSBoolean?' => '.then((value) => value?.toDart)',
    _ => '',
  };

  String _rawConvert(String inner) => switch (inner) {
    'JSString' => '(raw) => (raw! as JSString).toDart',
    'JSString?' => '(raw) => (raw as JSString?)?.toDart',
    'JSNumber' => '(raw) => (raw! as JSNumber).toDartDouble',
    'JSNumber?' => '(raw) => (raw as JSNumber?)?.toDartDouble',
    'JSBoolean' => '(raw) => (raw! as JSBoolean).toDart',
    'JSBoolean?' => '(raw) => (raw as JSBoolean?)?.toDart',
    'JSAny?' => '(raw) => raw',
    _ => '(raw) => raw as $inner',
  };

  /// Parses a mapped type as an instance of the generic [base]
  /// (`base<inner>` or `base<inner>?`).
  ({String inner, bool nullable})? _instanceOf(String mapped, String base) {
    final prefix = '$base<';
    if (!mapped.startsWith(prefix)) {
      return null;
    }
    if (mapped.endsWith('>?')) {
      return (
        inner: mapped.substring(prefix.length, mapped.length - 2),
        nullable: true,
      );
    }
    if (mapped.endsWith('>')) {
      return (
        inner: mapped.substring(prefix.length, mapped.length - 1),
        nullable: false,
      );
    }
    return null;
  }

  String _typeArguments(Map<String, Object?> declaration) {
    final parameters = declaration['typeParameters'];
    if (parameters is! List<Object?> || parameters.isEmpty) {
      return '';
    }
    final names = [
      for (final parameter in parameters)
        (parameter! as Map<Object?, Object?>)['name']! as String,
    ];
    return '<${names.join(', ')}>';
  }

  // ---------------------------------------------------------------- members

  /// The converted dart-layer counterpart of one parity member, or `null`
  /// when the parity member is already Dart-first (passthrough-identical).
  String? _convertedMember(
    Map<String, Object?> child, {
    required bool eraseScopeReferences,
  }) {
    switch (child['kind']) {
      case 'property' || 'variable':
        return _convertedReadable(
          child,
          eraseScopeReferences: eraseScopeReferences,
        );
      case 'method' || 'function':
        final parameters = (child['parameters'] as List<Object?>?) ?? const [];
        final hasRest = parameters.any(
          (parameter) => (parameter! as Map<Object?, Object?>)['rest'] == true,
        );
        return hasRest
            ? _convertedHelperCallable(
                child,
                eraseScopeReferences: eraseScopeReferences,
              )
            : _convertedExternalCallable(
                child,
                eraseScopeReferences: eraseScopeReferences,
              );
      case 'callSignature':
        return _convertedCallSignature(
          child,
          eraseScopeReferences: eraseScopeReferences,
        );
      case 'indexSignature':
        return null; // The blessed operators stay parity-shaped.
      case 'constructor':
        return null; // Converted on the Ctor dart type.
      case 'typeLiteral':
        return null; // Registered literals get their own dart types.
      default:
        throw DartLayerGenerationException(
          child['id']! as String,
          "no dart-layer rule for member kind ${child['kind']}",
        );
    }
  }

  String? _convertedReadable(
    Map<String, Object?> declaration, {
    required bool eraseScopeReferences,
  }) {
    final id = declaration['id']! as String;
    final scopes = mapper.scopesFor(declaration);
    var mapped = mapper.mapType(
      declaration['type'],
      generic: false,
      scopes: scopes,
      context: id,
      eraseScopeReferences: eraseScopeReferences,
    );
    if (declaration['optional'] == true &&
        !mapped.endsWith('?') &&
        mapped != 'void') {
      mapped = '$mapped?';
    }
    if (mapped == 'void') {
      mapped = 'JSAny?';
    }
    final name = mapper.dartName(declaration['name']! as String);
    final event = _instanceOf(mapped, 'Event');
    if (event != null) {
      _requireSubscribableEvent(id);
      _needsStreamHelper = true;
      final streamed = _deJs(event.inner) ?? event.inner;
      final convert = _rawConvert(event.inner);
      if (event.nullable) {
        return '  Stream<$streamed>? get ${name}Stream {\n'
            '    final event\$ = \$js.$name;\n'
            '    if (event\$ == null) return null;\n'
            '    return _eventStream\$(\n'
            '      (listener) => event\$.call(listener),\n'
            '      $convert,\n'
            '    );\n'
            '  }\n';
      }
      return '  Stream<$streamed> get ${name}Stream => _eventStream\$(\n'
          '        (listener) => \$js.$name.call(listener),\n'
          '        $convert,\n'
          '      );\n';
    }
    final promise = _instanceOf(mapped, 'JSPromise');
    if (promise != null) {
      final mutable = declaration['kind'] == 'property'
          ? declaration['readonly'] != true
          : declaration['declarationKind'] != null &&
                declaration['declarationKind'] != 'const';
      if (mutable) {
        // A Future-returning getter beside the inherited Event/JSPromise
        // setter is illegal at the package language level; no occurrence
        // exists in the pinned baseline, so this stays a loud totality
        // failure rather than a silent approximation.
        throw DartLayerGenerationException(
          id,
          'no dart-layer rule for a mutable promise-valued member',
        );
      }
      final resolved = _deJs(promise.inner) ?? promise.inner;
      final then = _promiseThen(promise.inner);
      final question = promise.nullable ? '?' : '';
      return '  Future<$resolved>$question get $name => '
          '\$js.$name$question.toDart$then;\n';
    }
    return null;
  }

  String? _convertedExternalCallable(
    Map<String, Object?> declaration, {
    required bool eraseScopeReferences,
  }) {
    final id = declaration['id']! as String;
    final scopes = mapper.scopesFor(declaration);
    final returnType = mapper.mapType(
      declaration['returnType'],
      generic: false,
      scopes: scopes,
      context: id,
      eraseScopeReferences: eraseScopeReferences,
    );
    final promise = _instanceOf(returnType, 'JSPromise');
    if (promise == null) {
      // Non-helper externals already take Dart scalars at the boundary;
      // only a promise return leaves anything to convert.
      return null;
    }
    final dartName = mapper.memberName(declaration);
    final clause = mapper.typeParameterClause(declaration);
    final typeArguments = _typeArguments(declaration);
    final required = <String>[];
    final optional = <String>[];
    final requiredArguments = <String>[];
    final optionalArguments = <String>[];
    for (final rawParameter
        in (declaration['parameters'] as List<Object?>?) ?? const <Object?>[]) {
      final parameter = (rawParameter! as Map<Object?, Object?>)
          .cast<String, Object?>();
      var type = mapper.mapType(
        parameter['type'],
        generic: false,
        scopes: scopes,
        context: id,
        eraseScopeReferences: eraseScopeReferences,
      );
      if (type == 'void') {
        type = 'JSAny?';
      }
      final parameterName = mapper.dartName(parameter['name']! as String);
      if (parameter['optional'] == true) {
        if (!type.endsWith('?')) {
          type = '$type?';
        }
        optional.add('$type $parameterName');
        optionalArguments.add(parameterName);
      } else {
        required.add('$type $parameterName');
        requiredArguments.add(parameterName);
      }
    }
    final signature = [
      required.join(', '),
      if (optional.isNotEmpty) '[${optional.join(', ')}]',
    ].where((part) => part.isNotEmpty).join(', ');
    String callWith(int optionalCount) {
      final arguments = [
        ...requiredArguments,
        ...optionalArguments.take(optionalCount),
      ].join(', ');
      return '\$js.$dartName$typeArguments($arguments)';
    }

    // Trailing nulls are treated as omitted, matching the parity helpers'
    // trimming semantics.
    String chain;
    if (optionalArguments.isEmpty) {
      chain = callWith(0);
    } else {
      final branches = StringBuffer('(');
      for (var count = optionalArguments.length; count > 0; count -= 1) {
        branches.write(
          '${optionalArguments[count - 1]} != null ? ${callWith(count)} : ',
        );
      }
      branches
        ..write(callWith(0))
        ..write(')');
      chain = branches.toString();
    }
    final resolved = _deJs(promise.inner) ?? promise.inner;
    final then = _promiseThen(promise.inner);
    final question = promise.nullable ? '?' : '';
    return '  Future<$resolved>$question $dartName$clause($signature) => '
        '$chain$question.toDart$then;\n';
  }

  String? _convertedHelperCallable(
    Map<String, Object?> declaration, {
    required bool eraseScopeReferences,
  }) {
    final id = declaration['id']! as String;
    final scopes = mapper.scopesFor(declaration);
    final signature = _helperSignature(
      (declaration['parameters'] as List<Object?>?) ?? const [],
      scopes,
      id,
      eraseScopeReferences: eraseScopeReferences,
    );
    final returnType = mapper.nullableForGeneric(
      mapper.mapType(
        declaration['returnType'],
        generic: true,
        scopes: scopes,
        context: id,
        eraseScopeReferences: eraseScopeReferences,
      ),
    );
    final promise = _instanceOf(returnType, 'JSPromise');
    final scalar = _deJs(returnType);
    if (!signature.converted && promise == null && scalar == null) {
      return null;
    }
    final dartName = mapper.memberName(declaration);
    final clause = mapper.typeParameterClause(declaration);
    final typeArguments = _typeArguments(declaration);
    final call = '\$js.$dartName$typeArguments(${signature.forwards})';
    if (promise != null) {
      final resolved = _deJs(promise.inner) ?? promise.inner;
      final then = _promiseThen(promise.inner);
      final question = promise.nullable ? '?' : '';
      return '  Future<$resolved>$question $dartName$clause'
          '(${signature.clause}) => $call$question.toDart$then;\n';
    }
    if (scalar != null) {
      return '  $scalar $dartName$clause(${signature.clause}) => '
          '$call${_fromJsSuffix(returnType)};\n';
    }
    return '  $returnType $dartName$clause(${signature.clause}) => $call;\n';
  }

  String? _convertedCallSignature(
    Map<String, Object?> declaration, {
    required bool eraseScopeReferences,
  }) {
    final id = declaration['id']! as String;
    final scopes = mapper.scopesFor(declaration);
    final signature = _helperSignature(
      (declaration['parameters'] as List<Object?>?) ?? const [],
      scopes,
      id,
      eraseScopeReferences: eraseScopeReferences,
    );
    final returnType = mapper.nullableForGeneric(
      mapper.mapType(
        declaration['returnType'],
        generic: true,
        scopes: scopes,
        context: id,
        eraseScopeReferences: eraseScopeReferences,
      ),
    );
    final promise = _instanceOf(returnType, 'JSPromise');
    final scalar = _deJs(returnType);
    if (!signature.converted && promise == null && scalar == null) {
      return null;
    }
    final call = '\$js.call(${signature.forwards})';
    if (promise != null) {
      final resolved = _deJs(promise.inner) ?? promise.inner;
      final then = _promiseThen(promise.inner);
      final question = promise.nullable ? '?' : '';
      return '  Future<$resolved>$question call(${signature.clause}) => '
          '$call$question.toDart$then;\n';
    }
    if (scalar != null) {
      return '  $scalar call(${signature.clause}) => '
          '$call${_fromJsSuffix(returnType)};\n';
    }
    return '  $returnType call(${signature.clause}) => $call;\n';
  }

  String? _convertedConstructor(
    Map<String, Object?> declaration,
    String className,
  ) {
    final id = declaration['id']! as String;
    final ordinal = declaration['overloadOrdinal'];
    final suffix = ordinal is int && ordinal > 0 ? '\$${ordinal + 1}' : '';
    final scopes = mapper.scopesFor(declaration);
    final signature = _helperSignature(
      (declaration['parameters'] as List<Object?>?) ?? const [],
      scopes,
      id,
      eraseScopeReferences: false,
    );
    if (!signature.converted) {
      return null;
    }
    final owner = mapper.byId[declaration['parentId']]!;
    final ownerClause = mapper.typeParameterClause(owner);
    final ownerArguments = _typeArguments(owner);
    final instantiated = '$className$ownerArguments';
    return '  $instantiated new\$$suffix$ownerClause(${signature.clause}) => '
        '\$js.new\$$suffix$ownerArguments(${signature.forwards});\n';
  }

  /// Builds a de-JS'd helper parameter list mirroring the parity helpers'
  /// shapes: optionals nullable, rest parameters as `List<JSAny?>`; the
  /// forwarded expressions convert scalars back with `.toJS`.
  ({String clause, String forwards, bool converted}) _helperSignature(
    List<Object?> parameters,
    List<Set<String>> scopes,
    String context, {
    required bool eraseScopeReferences,
  }) {
    final requiredParts = <String>[];
    final optionalParts = <String>[];
    final forwards = <String>[];
    var converted = false;
    for (final rawParameter in parameters) {
      final parameter = (rawParameter! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final parameterName = mapper.dartName(parameter['name']! as String);
      if (parameter['rest'] == true) {
        optionalParts.add('List<JSAny?> $parameterName = const []');
        forwards.add(parameterName);
        continue;
      }
      var type = mapper.nullableForGeneric(
        mapper.mapType(
          parameter['type'],
          generic: true,
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        ),
      );
      if (parameter['optional'] == true && !type.endsWith('?')) {
        type = '$type?';
      }
      final de = _deJs(type);
      if (de != null) {
        converted = true;
        forwards.add(_toJsExpression(de, parameterName));
        type = de;
      } else {
        forwards.add(parameterName);
      }
      (parameter['optional'] == true ? optionalParts : requiredParts).add(
        '$type $parameterName',
      );
    }
    final clause = [
      requiredParts.join(', '),
      if (optionalParts.isNotEmpty) '[${optionalParts.join(', ')}]',
    ].where((part) => part.isNotEmpty).join(', ');
    return (
      clause: clause,
      forwards: forwards.join(', '),
      converted: converted,
    );
  }

  void _requireSubscribableEvent(String consumerId) {
    final event = mapper.topLevelByName['Event'];
    final children = event == null
        ? const <Map<String, Object?>>[]
        : (mapper.childrenByParent[event['id']! as String] ??
              const <Map<String, Object?>>[]);
    final hasSubscribe = children.any(
      (child) =>
          child['kind'] == 'callSignature' &&
          parity.isEmitted(child) &&
          ((child['parameters'] as List<Object?>?) ?? const []).isNotEmpty,
    );
    if (!hasSubscribe) {
      throw DartLayerGenerationException(
        consumerId,
        'the stream-from-event rule requires the Event interface to '
        'declare a call signature taking a listener',
      );
    }
  }

  // ----------------------------------------------------------------- shapes

  void _emitInterfaceDart(
    Map<String, Object?> declaration,
    StringBuffer out,
  ) {
    final id = declaration['id']! as String;
    final name = declaration['name']! as String;
    final children =
        mapper.childrenByParent[id] ?? const <Map<String, Object?>>[];
    final hasCallSignature = children.any(
      (child) => child['kind'] == 'callSignature',
    );
    final members = _convertedMembers(
      children.where(parity.isEmitted),
      eraseScopeReferences: false,
    );
    final dartTypeName = '${name}Dart';
    final literal = hasCallSignature
        ? null
        : _flattenedLiteralFactory(
            declaration,
            dartTypeName,
            name,
            eraseScopeReferences: false,
          );
    if (members.isEmpty && literal == null) {
      return;
    }
    dispositions[id] = 'emitted';
    _typeIdsWithDart.add(id);
    final clause = mapper.typeParameterClause(declaration);
    final arguments = _typeArguments(declaration);
    out.writeln(
      'extension type $dartTypeName$clause($name$arguments \$js) '
      'implements $name$arguments {',
    );
    if (literal != null) {
      out.write(literal);
    }
    members.forEach(out.write);
    out
      ..writeln('}')
      ..writeln();
    _writeHop(out, name, clause, arguments);
  }

  void _emitAnonDart(Map<String, Object?> declaration, StringBuffer out) {
    final id = declaration['id']! as String;
    final name = mapper.hashName('JSAnon', declaration['shapeHash']);
    final children =
        mapper.childrenByParent[id] ?? const <Map<String, Object?>>[];
    final hasCallSignature = children.any(
      (child) => child['kind'] == 'callSignature',
    );
    final members = _convertedMembers(
      children.where(parity.isEmitted),
      eraseScopeReferences: true,
    );
    final dartTypeName = '${name}Dart';
    final literal = hasCallSignature
        ? null
        : _flattenedLiteralFactory(
            declaration,
            dartTypeName,
            name,
            eraseScopeReferences: true,
          );
    if (members.isEmpty && literal == null) {
      return;
    }
    dispositions[id] = 'emitted';
    if (!_emittedAnonNames.add(name)) {
      return; // Shared shapes emit once; dispositions cover both sites.
    }
    out.writeln(
      'extension type $dartTypeName($name \$js) implements $name {',
    );
    if (literal != null) {
      out.write(literal);
    }
    members.forEach(out.write);
    out
      ..writeln('}')
      ..writeln();
    _writeHop(out, name, '', '');
  }

  void _emitNamespaceDart(
    Map<String, Object?> declaration,
    StringBuffer out,
  ) {
    final id = declaration['id']! as String;
    final typeName = mapper.namespaceTypeName(declaration['name']! as String);
    final children =
        mapper.childrenByParent[id] ?? const <Map<String, Object?>>[];
    final members = _convertedMembers(
      children.where(parity.isEmitted),
      eraseScopeReferences: false,
    );
    if (members.isEmpty) {
      return;
    }
    dispositions[id] = 'emitted';
    _typeIdsWithDart.add(id);
    out.writeln(
      'extension type ${typeName}Dart($typeName \$js) '
      'implements $typeName {',
    );
    members.forEach(out.write);
    out
      ..writeln('}')
      ..writeln();
    _writeHop(out, typeName, '', '');
  }

  void _emitClassDart(Map<String, Object?> declaration, StringBuffer out) {
    final id = declaration['id']! as String;
    final name = declaration['name']! as String;
    final children =
        mapper.childrenByParent[id] ?? const <Map<String, Object?>>[];
    final clause = mapper.typeParameterClause(declaration);
    final arguments = _typeArguments(declaration);

    final instanceMembers = _convertedMembers(
      children.where(
        (child) =>
            parity.isEmitted(child) &&
            child['static'] != true &&
            child['kind'] != 'constructor',
      ),
      eraseScopeReferences: false,
    );
    if (instanceMembers.isNotEmpty) {
      dispositions[id] = 'emitted';
      _typeIdsWithDart.add(id);
      out.writeln(
        'extension type ${name}Dart$clause($name$arguments \$js) '
        'implements $name$arguments {',
      );
      instanceMembers.forEach(out.write);
      out
        ..writeln('}')
        ..writeln();
      _writeHop(out, name, clause, arguments);
    }

    final ctorMembers = <String>[];
    for (final child in children.where(parity.isEmitted)) {
      String? converted;
      if (child['kind'] == 'constructor') {
        converted = _convertedConstructor(child, name);
      } else if (child['static'] == true) {
        converted = _convertedMember(child, eraseScopeReferences: false);
      }
      if (converted != null) {
        ctorMembers.add(converted);
        dispositions[child['id']! as String] = 'emitted';
      }
    }
    if (ctorMembers.isNotEmpty) {
      dispositions[id] = 'emitted';
      _classIdsWithCtorDart.add(id);
      out.writeln(
        'extension type ${name}CtorDart(${name}Ctor \$js) '
        'implements ${name}Ctor {',
      );
      ctorMembers.forEach(out.write);
      out
        ..writeln('}')
        ..writeln();
      _writeHop(out, '${name}Ctor', '', '');
    }
  }

  List<String> _convertedMembers(
    Iterable<Map<String, Object?>> children, {
    required bool eraseScopeReferences,
  }) {
    final members = <String>[];
    for (final child in children) {
      final converted = _convertedMember(
        child,
        eraseScopeReferences: eraseScopeReferences,
      );
      if (converted != null) {
        members.add(converted);
        dispositions[child['id']! as String] = 'emitted';
      }
    }
    return members;
  }

  /// The flattened object-literal factory: the parity `lit$` eligibility
  /// rules applied across the full transitive declared hierarchy, with
  /// boundary-de-js on every scalar parameter. Derived members shadow
  /// base members of the same name; bases resolve through the IR's
  /// declared `extends` references (external references such as
  /// `Iterable` declare no members and contribute nothing).
  String? _flattenedLiteralFactory(
    Map<String, Object?> declaration,
    String dartTypeName,
    String parityTypeName, {
    required bool eraseScopeReferences,
  }) {
    final scopes = mapper.scopesFor(declaration);
    final parameters = <String>[];
    final assignments = <String>[];
    final seen = <String>{};
    final visited = <String>{};

    void visit(
      Map<String, Object?> owner,
      Map<String, Object?> substitution,
    ) {
      final ownerId = owner['id']! as String;
      if (!visited.add(ownerId)) {
        return;
      }
      for (final child
          in mapper.childrenByParent[ownerId] ??
              const <Map<String, Object?>>[]) {
        if (!parity.isEmitted(child) || child['static'] == true) {
          continue;
        }
        final childName = child['name'];
        if (childName is! String || mapper.dartName(childName) != childName) {
          continue;
        }
        if (child['kind'] == 'property') {
          if (!seen.add(childName)) {
            continue;
          }
          final type = substitution.isEmpty
              ? child['type']
              : mapper.substitute(child['type'], substitution);
          final mapped = mapper.nullableForGeneric(
            mapper.mapType(
              type,
              generic: true,
              scopes: scopes,
              context: child['id']! as String,
              eraseScopeReferences: eraseScopeReferences,
            ),
          );
          final de = _deJs(mapped);
          var dartType = de ?? mapped;
          if (!dartType.endsWith('?')) {
            dartType = '$dartType?';
          }
          parameters.add('$dartType $childName');
          final value = de != null ? '$childName.toJS' : childName;
          assignments.add(
            '    if ($childName != null) {\n'
            "      object\$.setProperty('$childName'.toJS, $value);\n"
            '    }\n',
          );
        } else if (child['kind'] == 'method' &&
            (child['overloadOrdinal'] ?? 0) == 0) {
          if (!seen.add(childName)) {
            continue;
          }
          parameters.add('JSFunction? $childName');
          assignments.add(
            '    if ($childName != null) {\n'
            "      object\$.setProperty('$childName'.toJS, $childName);\n"
            '    }\n',
          );
        }
      }
      for (final rawBase
          in (owner['extends'] as List<Object?>?) ?? const <Object?>[]) {
        if (rawBase is! Map<Object?, Object?>) {
          continue;
        }
        final base = rawBase.cast<String, Object?>();
        if (base['kind'] != 'reference') {
          continue;
        }
        final target = mapper.topLevelByName[base['name']];
        if (target == null) {
          continue; // External references declare no members in the IR.
        }
        if (target['kind'] != 'interface' && target['kind'] != 'class') {
          throw DartLayerGenerationException(
            owner['id']! as String,
            'no flattened-literal-factory rule for a base of kind '
            "${target['kind']}",
          );
        }
        final targetParameters =
            (target['typeParameters'] as List<Object?>?) ?? const [];
        final baseArguments =
            (base['typeArguments'] as List<Object?>?) ?? const [];
        final composed = <String, Object?>{
          for (var index = 0; index < targetParameters.length; index += 1)
            (targetParameters[index]! as Map<Object?, Object?>)['name']!
                as String: index < baseArguments.length
                ? (substitution.isEmpty
                      ? baseArguments[index]
                      : mapper.substitute(baseArguments[index], substitution))
                : {'kind': 'primitive', 'name': 'any'},
        };
        visit(target, composed);
      }
    }

    visit(declaration, const {});
    if (parameters.isEmpty) {
      return null;
    }
    final arguments = _typeArguments(declaration);
    final buffer = StringBuffer()
      ..writeln('  factory $dartTypeName.lit\$({${parameters.join(', ')}}) {')
      ..writeln(r'    final object$ = JSObject();');
    assignments.forEach(buffer.write);
    buffer
      ..writeln(
        '    return $dartTypeName$arguments'
        '($parityTypeName$arguments(object\$));',
      )
      ..writeln('  }');
    return buffer.toString();
  }

  void _writeHop(
    StringBuffer out,
    String name,
    String clause,
    String arguments,
  ) {
    out
      ..writeln('extension ${name}ToDart$clause on $name$arguments {')
      ..writeln(
        '  ${name}Dart$arguments get dart => ${name}Dart$arguments(this);',
      )
      ..writeln('}')
      ..writeln();
  }

  void _emitTupleDarts(StringBuffer out) {
    final names = mapper.tupleElements.keys.toList()..sort();
    for (final name in names) {
      final elements = mapper.tupleElements[name]!;
      final members = <String>[];
      for (var index = 0; index < elements.length; index += 1) {
        final de = _deJs(elements[index]);
        if (de == null) {
          continue;
        }
        members.add(
          '  $de get \$${index + 1} => '
          '\$js.\$${index + 1}${_fromJsSuffix(elements[index])};\n',
        );
      }
      if (members.isEmpty) {
        continue;
      }
      out.writeln('extension type ${name}Dart($name \$js) implements $name {');
      members.forEach(out.write);
      out
        ..writeln('}')
        ..writeln();
      _writeHop(out, name, '', '');
    }
  }

  void _emitRootDart(StringBuffer out) {
    out
      ..writeln('/// The dart-layer view of the VS Code API module object.')
      ..writeln('///')
      ..writeln(
        '/// Entered from the parity root with '
        '`VscodeApi(rawVscode).dart`.',
      )
      ..writeln(
        r'extension type VscodeApiDart(VscodeApi $js) implements VscodeApi {',
      );
    for (final declaration in mapper.declarations) {
      if (declaration['parentId'] != 'module:vscode' ||
          !parity.isEmitted(declaration)) {
        continue;
      }
      final id = declaration['id']! as String;
      final name = declaration['name']! as String;
      switch (declaration['kind']) {
        case 'namespace':
          if (_typeIdsWithDart.contains(id)) {
            final typeName = mapper.namespaceTypeName(name);
            out.writeln(
              '  ${typeName}Dart get $name => ${typeName}Dart(\$js.$name);',
            );
          }
        case 'class':
          if (_classIdsWithCtorDart.contains(id)) {
            out.writeln(
              '  ${name}CtorDart get $name => ${name}CtorDart(\$js.$name);',
            );
          }
        case 'variable':
          final converted = _convertedReadable(
            declaration,
            eraseScopeReferences: false,
          );
          if (converted != null) {
            out.write(converted);
            dispositions[id] = 'emitted';
          }
        default:
          break;
      }
    }
    out
      ..writeln('}')
      ..writeln();
    _writeHop(out, 'VscodeApi', '', '');
  }
}

const _streamHelperSource = r'''
Stream<S> _eventStream$<S>(
  JSAny? Function(JSFunction listener) subscribe,
  S Function(JSAny? raw) convert,
) {
  JSAny? registration;
  late final StreamController<S> controller;
  controller = StreamController<S>.broadcast(
    onListen: () {
      registration = subscribe(
        ((JSAny? raw) {
          controller.add(convert(raw));
        }).toJS,
      );
    },
    onCancel: () {
      final registered = registration;
      registration = null;
      if (registered is JSObject) {
        registered.callMethod('dispose'.toJS);
      }
    },
  );
  return controller.stream;
}
''';
