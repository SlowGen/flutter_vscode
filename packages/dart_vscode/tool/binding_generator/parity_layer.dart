/// Emits the complete typed Parity Layer from the pinned canonical IR.
///
/// Every rule in this emitter is a Total Mapping Rule (ADR 0012): a
/// judgment-free, deterministic mapping from one class of TypeScript
/// construct to `dart:js_interop` code, applied to every occurrence. A
/// construct with no rule fails generation with an actionable error;
/// nothing is approximated. Strategy and per-construct precedent:
/// `specs/research/js-to-dart-mapping.md`.
///
/// The emitted layer is rooted in the module object an extension receives
/// at activation (`VscodeApi`); it introduces no globals. External members
/// use ordinary Dart primitives where blessed; generated helpers (tuple
/// accessors, constructors, rest-parameter calls, call signatures) use JS
/// types throughout so every value is boundary-safe by construction.
library;

import 'dart:convert';

import 'ir_type_mapper.dart';

export 'ir_type_mapper.dart' show ParityGenerationException;

/// The generated artifacts: the Dart library and the disposition ledger.
typedef ParityArtifacts = ({String library, String ledger});

/// The canonical Construct Classes: one per Total Mapping Rule. Live
/// coverage requires a tagged real-host probe per class unless the class
/// appears in [parityLiveExemptions] with a reason.
const parityConstructClasses = [
  'mixed-union',
  'string-literal-union',
  'overload-set',
  'reserved-name',
  'underscore-name',
  'numeric-enum',
  'tuple',
  'index-signature',
  'rest-parameter',
  'promise-thenable',
  'array',
  'declared-constructor',
  'default-constructor',
  'object-literal-factory',
  'type-literal',
  'intersection',
  'call-signature',
  'readonly-property',
  'optional-member',
  'stable-typedef',
  'narrowing',
  'external-setter',
  'function-type',
];

/// Construct Classes exempt from live probing, each with its reason.
const parityLiveExemptions = {
  'string-literal-union':
      'zero occurrences in the pinned baseline; rule proven on synthetic IR',
  'readonly-property':
      'the rule is the absence of a setter, provable only at compile time',
  'underscore-name':
      'the only baseline sites are deprecated internal fields with no '
      'stable behavior to observe',
};

/// Builds the Parity Layer library and its totality ledger from IR JSON.
ParityArtifacts emitParityLayer(Map<String, Object?> inventory) {
  return ParityEmitter(IrTypeMapper(inventory)).emit();
}

/// The Parity Layer emitter.
///
/// Owns declaration emission and the disposition ledger over a shared
/// [IrTypeMapper] (the IR indexes, the Total Mapping Rules for types, and
/// the helper-type registries). Public so that the dart-layer emitter
/// (`dart_layer.dart`) can consume the same mapper plus this emitter's
/// dispositions when it layers Dart-first ergonomics over the parity
/// surface; the parity output itself is produced only through
/// [emitParityLayer].
final class ParityEmitter {
  /// Emits over the given mapper's indexes and registries.
  ParityEmitter(this.mapper);

  /// The shared IR index and type-mapping module.
  final IrTypeMapper mapper;

  /// Generated anonymous-shape extension types by name.
  final _anonTypes = <String, String>{};

  /// Generated intersection extension types by name, built from the
  /// mapper's registered operand sets.
  final _intersectionTypes = <String, String>{};

  /// The per-declaration disposition ledger.
  final dispositions = <String, String>{};

  String? _body;

  /// The declaration body of the last [emit] — the library without its
  /// header comment or imports — for inlining as the substrate of the
  /// self-contained dart-layer artifact.
  String get body =>
      _body ?? (throw StateError('emit() has not run on this emitter'));

  /// Emits the parity library and ledger, populating every registry.
  ParityArtifacts emit() {
    _computeDispositions();

    final namespaces = StringBuffer();
    // Thenable itself is mapped to JSPromise (its ledger disposition);
    // the typedef ships so author code can keep the upstream name.
    if (mapper.topLevelByName.containsKey('Thenable')) {
      namespaces
        ..writeln('typedef Thenable<T extends JSAny?> = JSPromise<T>;')
        ..writeln();
    }
    final interfaces = StringBuffer();
    final classes = StringBuffer();
    final enums = StringBuffer();
    final typedefs = StringBuffer();
    final anonTypes = StringBuffer();
    final root = StringBuffer();

    for (final declaration in mapper.declarations) {
      if (dispositions[declaration['id']! as String] != 'emitted') {
        continue;
      }
      final parent = declaration['parentId']! as String;
      final topLevel = parent == 'module:vscode' || parent == 'global:global';
      switch (declaration['kind']) {
        case 'typeAlias' when topLevel:
          _emitAlias(declaration, typedefs);
        case 'enum' when topLevel:
          _emitEnum(declaration, typedefs, enums);
        case 'namespace' when topLevel:
          _emitNamespace(declaration, namespaces);
        case 'interface' when topLevel:
          _emitInterface(declaration, interfaces);
        case 'class' when topLevel:
          _emitClass(declaration, classes);
        case 'typeLiteral':
          _emitTypeLiteral(declaration, anonTypes);
        case 'variable' when parent == 'module:vscode':
        case 'interface' || 'class' || 'enum' || 'typeAlias' || 'namespace':
        case 'property' ||
            'method' ||
            'constructor' ||
            'function' ||
            'variable' ||
            'enumMember' ||
            'indexSignature' ||
            'callSignature':
          break; // Emitted as part of an owning surface.
        default:
          throw ParityGenerationException(
            declaration['id']! as String,
            'no Total Mapping Rule for declaration kind '
            "${declaration['kind']}",
          );
      }
    }

    final stableTypedefs = StringBuffer();
    final typedefCounters = <String, int>{};
    for (final declaration in mapper.declarations) {
      if (declaration['kind'] != 'typeLiteral' || !isEmitted(declaration)) {
        continue;
      }
      final base = _stableLiteralBase(declaration);
      final ordinal = typedefCounters.update(
        base,
        (value) => value + 1,
        ifAbsent: () => 1,
      );
      final target = mapper.hashName('JSAnon', declaration['shapeHash']);
      stableTypedefs.writeln('typedef $base\$$ordinal = $target;');
    }
    if (stableTypedefs.isNotEmpty) {
      stableTypedefs.writeln();
    }

    _emitRoot(root);
    _buildIntersectionBodies();

    _body =
        (StringBuffer()
              ..write(typedefs)
              ..write(stableTypedefs)
              ..write(_sortedValues(mapper.tupleTypes))
              ..write(_sortedValues(mapper.literalWrappers))
              ..write(_sortedValues(_intersectionTypes))
              ..write(anonTypes)
              ..write(enums)
              ..write(namespaces)
              ..write(interfaces)
              ..write(classes)
              ..write(root))
            .toString();
    final library = StringBuffer()
      ..writeln('// GENERATED CODE - DO NOT MODIFY BY HAND.')
      ..writeln('//')
      ..writeln('// The complete typed VS Code Parity Layer substrate')
      ..writeln('// (ADR 0012), produced only by Total Mapping Rules. It')
      ..writeln('// ships inlined inside vscode_dart_layer.g.dart;')
      ..writeln('// regenerate that artifact with:')
      ..writeln(
        '//   dart tool/binding_generator/generate.dart '
        '--dart-layer .',
      )
      ..writeln('//')
      ..writeln('// JS `undefined` and `null` both surface as Dart `null`')
      ..writeln('// (documented platform-wide conflation).')
      ..writeln('// ignore_for_file: type=lint')
      ..writeln("import 'dart:js_interop';")
      ..writeln("import 'dart:js_interop_unsafe';")
      ..writeln()
      ..write(_body);

    final ledger = const JsonEncoder.withIndent('  ').convert({
      'schemaVersion': 1,
      'dispositions': dispositions,
    });
    return (library: library.toString(), ledger: '$ledger\n');
  }

  String _sortedValues(Map<String, String> registry) {
    final names = registry.keys.toList()..sort();
    return names.map((name) => registry[name]!).join();
  }

  // ---------------------------------------------------------------- ledger

  void _computeDispositions() {
    final thenable = mapper.topLevelByName['Thenable'];
    bool underThenable(Map<String, Object?> declaration) {
      var parent = declaration['parentId'] as String?;
      while (parent != null) {
        if (thenable != null && parent == thenable['id']) {
          return true;
        }
        parent = mapper.byId[parent]?['parentId'] as String?;
      }
      return false;
    }

    bool underSymbolKeyed(Map<String, Object?> declaration) {
      Map<String, Object?>? cursor = declaration;
      while (cursor != null) {
        final name = cursor['name'];
        if (name is String && name.startsWith('[')) {
          return true;
        }
        cursor = mapper.byId[cursor['parentId']];
      }
      return false;
    }

    for (final declaration in mapper.declarations) {
      final id = declaration['id']! as String;
      if (declaration['visibility'] != 'public') {
        dispositions[id] = 'non-public';
      } else if (thenable != null &&
          (id == thenable['id'] || underThenable(declaration))) {
        dispositions[id] = 'thenable-as-jspromise';
      } else if (underSymbolKeyed(declaration)) {
        dispositions[id] = 'symbol-keyed-member';
      } else {
        dispositions[id] = 'emitted';
      }
    }
  }

  /// Whether [declaration] carries the `emitted` parity disposition.
  bool isEmitted(Map<String, Object?> declaration) =>
      dispositions[declaration['id']! as String] == 'emitted';

  // ----------------------------------------------------------------- names

  String? _jsRename(Map<String, Object?> declaration, String dartName) {
    final jsName = declaration['name']! as String;
    return dartName == jsName ? null : jsName;
  }

  /// A readable, deterministic alias base from the literal's named
  /// ancestor chain (e.g. class Position, member `with` ->
  /// `PositionWith`); occurrence ordinals disambiguate siblings.
  String _stableLiteralBase(Map<String, Object?> declaration) {
    final segments = <String>[];
    var cursor = mapper.byId[declaration['parentId']];
    while (cursor != null) {
      final name = cursor['name'];
      if (name is String && cursor['kind'] != 'typeLiteral') {
        final clean = name.replaceAll(RegExp('[^A-Za-z0-9]'), '');
        if (clean.isNotEmpty) {
          segments.add(
            clean[0].toUpperCase() + clean.substring(1),
          );
        }
      }
      cursor = mapper.byId[cursor['parentId']];
    }
    final base = segments.reversed.join();
    if (base.isEmpty || RegExp('^[0-9]').hasMatch(base)) {
      return 'Anon$base';
    }
    return base;
  }

  // --------------------------------------------------------- intersections

  /// Builds the hoisted intersection extension types for every operand
  /// set the mapper registered, including sets first reached while an
  /// earlier body was being built.
  void _buildIntersectionBodies() {
    while (true) {
      final pending = [
        for (final name in mapper.intersectionOperands.keys)
          if (!_intersectionTypes.containsKey(name)) name,
      ];
      if (pending.isEmpty) {
        return;
      }
      for (final name in pending) {
        _intersectionTypes[name] = _buildIntersection(
          name,
          mapper.intersectionOperands[name]!,
        );
      }
    }
  }

  Map<String, Object?>? _operandDeclaration(String mappedName) {
    if (mappedName.startsWith('JSAnon_')) {
      for (final declaration in mapper.declarations) {
        if (declaration['kind'] == 'typeLiteral' &&
            mapper.hashName('JSAnon', declaration['shapeHash']) == mappedName) {
          return declaration;
        }
      }
      return null;
    }
    final target = mapper.topLevelByName[mappedName];
    if (target != null &&
        (target['kind'] == 'interface' || target['kind'] == 'class')) {
      return target;
    }
    return null;
  }

  /// Implements every operand; members two or more operands declare are
  /// redeclared from the first declaring operand to resolve the conflict
  /// deterministically.
  String _buildIntersection(String name, List<String> mapped) {
    final bases = {...mapped.where((m) => !m.endsWith('?')), 'JSObject'};
    final memberOwners = <String, List<Map<String, Object?>>>{};
    for (final operand in mapped) {
      final declaration = _operandDeclaration(operand);
      if (declaration == null) {
        continue;
      }
      final children =
          mapper.childrenByParent[declaration['id']] ??
          const <Map<String, Object?>>[];
      for (final child in children) {
        final childName = child['name'];
        if (childName is String && isEmitted(child)) {
          memberOwners.putIfAbsent(childName, () => []).add(child);
        }
      }
    }
    final body = StringBuffer()
      ..writeln(
        'extension type $name(JSObject _self) '
        'implements ${bases.join(', ')} {',
      );
    for (final owners in memberOwners.values) {
      if (owners.length < 2) {
        continue;
      }
      _emitMembers(
        [owners.first],
        body,
        receiver: '_self',
        eraseScopeReferences: true,
      );
    }
    body
      ..writeln('}')
      ..writeln();
    return body.toString();
  }

  // ---------------------------------------------------------------- shapes

  void _emitAlias(Map<String, Object?> declaration, StringBuffer out) {
    final name = declaration['name']! as String;
    final clause = mapper.typeParameterClause(declaration);
    if (name == 'Thenable') {
      out.writeln('typedef Thenable<T extends JSAny?> = JSPromise<T>;');
      return;
    }
    final literalUnion = mapper.stringLiteralUnion(declaration['type']);
    if (literalUnion != null) {
      // The alias IS its wrapper (parity-runtime ledger entry 6): the
      // wrapper is registered under the alias name and hoists with the
      // other literal wrappers; no typedef is emitted.
      mapper.registerLiteralWrapper(literalUnion.members, name: name);
      return;
    }
    final mapped = mapper.mapType(
      declaration['type'],
      generic: true,
      scopes: mapper.scopesFor(declaration),
      context: declaration['id']! as String,
    );
    out
      ..writeln(
        'typedef $name$clause = ${mapper.nullableForGeneric(mapped)};',
      )
      ..writeln();
  }

  void _emitEnum(
    Map<String, Object?> declaration,
    StringBuffer typedefs,
    StringBuffer out,
  ) {
    final name = declaration['name']! as String;
    typedefs.writeln('typedef $name = int;');
    final members =
        mapper.childrenByParent[declaration['id']] ??
        const <Map<String, Object?>>[];
    out.writeln(
      'extension type ${name}Values(JSObject _self) '
      'implements JSObject {',
    );
    for (final member in members.where(isEmitted)) {
      final dartName = mapper.dartName(member['name']! as String);
      final rename = _jsRename(member, dartName);
      if (rename != null) {
        out.writeln("  @JS('$rename')");
      }
      out.writeln('  external int get $dartName;');
    }
    out
      ..writeln('}')
      ..writeln();
  }

  void _emitNamespace(Map<String, Object?> declaration, StringBuffer out) {
    final typeName = mapper.namespaceTypeName(declaration['name']! as String);
    out.writeln(
      'extension type $typeName(JSObject _self) '
      'implements JSObject {',
    );
    for (final child
        in mapper.childrenByParent[declaration['id']] ??
            const <Map<String, Object?>>[]) {
      if (!isEmitted(child)) {
        continue;
      }
      switch (child['kind']) {
        case 'function':
          _emitCallable(child, out, receiver: '_self');
        case 'variable':
          _emitVariable(child, out);
        default:
          throw ParityGenerationException(
            child['id']! as String,
            'no Total Mapping Rule for namespace member kind '
            "${child['kind']}",
          );
      }
    }
    out
      ..writeln('}')
      ..writeln();
  }

  void _emitVariable(Map<String, Object?> declaration, StringBuffer out) {
    final dartName = mapper.dartName(declaration['name']! as String);
    final rename = _jsRename(declaration, dartName);
    final scopes = mapper.scopesFor(declaration);
    final id = declaration['id']! as String;
    final type = mapper.mapType(
      declaration['type'],
      generic: false,
      scopes: scopes,
      context: id,
    );
    final buffer = StringBuffer();
    if (rename != null) {
      buffer.writeln("  @JS('$rename')");
    }
    buffer.writeln('  external $type get $dartName;');
    if (declaration['declarationKind'] != null &&
        declaration['declarationKind'] != 'const') {
      if (rename != null) {
        buffer.writeln("  @JS('$rename')");
      }
      buffer.writeln('  external set $dartName($type value);');
    }
    out.write(buffer);
  }

  void _emitInterface(Map<String, Object?> declaration, StringBuffer out) {
    final name = declaration['name']! as String;
    final id = declaration['id']! as String;
    final clause = mapper.typeParameterClause(declaration);
    final scopes = mapper.scopesFor(declaration);
    final children = mapper.childrenByParent[id] ?? const [];
    final hasCallSignature = children.any(
      (child) => child['kind'] == 'callSignature',
    );
    final representation = hasCallSignature ? 'JSFunction' : 'JSObject';
    final bases = <String>{
      for (final base in (declaration['extends'] as List<Object?>?) ?? const [])
        mapper.mapType(base, generic: true, scopes: scopes, context: id),
      'JSObject',
    };
    out.writeln(
      'extension type $name$clause($representation _self) '
      'implements ${bases.join(', ')} {',
    );
    if (representation == 'JSObject') {
      _emitLiteralFactory(name, children, out);
    }
    _emitMembers(children, out, receiver: '_self');
    out
      ..writeln('}')
      ..writeln();
  }

  /// The blessed creation rule: an external constructor with only named
  /// parameters produces a JS object literal. Members whose JS name is not
  /// a plain Dart identifier are excluded (authors use setProperty);
  /// method members take JSFunction so interfaces are implementable.
  void _emitLiteralFactory(
    String name,
    List<Map<String, Object?>> children,
    StringBuffer out, {
    bool eraseScopeReferences = false,
  }) {
    final parameters = <String>[];
    for (final child in children) {
      if (!isEmitted(child)) {
        continue;
      }
      final childName = child['name'];
      if (childName is! String || mapper.dartName(childName) != childName) {
        continue;
      }
      if (child['kind'] == 'property') {
        var type = mapper.nullableForGeneric(
          mapper.mapType(
            child['type'],
            generic: true,
            scopes: mapper.scopesFor(child),
            context: child['id']! as String,
            eraseScopeReferences: eraseScopeReferences,
          ),
        );
        if (!type.endsWith('?')) {
          type = '$type?';
        }
        parameters.add('$type $childName');
      } else if (child['kind'] == 'method' &&
          (child['overloadOrdinal'] ?? 0) == 0) {
        parameters.add('JSFunction? $childName');
      }
    }
    if (parameters.isEmpty) {
      return;
    }
    out.writeln(
      '  external factory $name.lit\$({${parameters.join(', ')}});',
    );
  }

  void _emitClass(Map<String, Object?> declaration, StringBuffer out) {
    final name = declaration['name']! as String;
    final id = declaration['id']! as String;
    final clause = mapper.typeParameterClause(declaration);
    final scopes = mapper.scopesFor(declaration);
    final children = mapper.childrenByParent[id] ?? const [];
    final bases = <String>{
      for (final base in [
        ...(declaration['extends'] as List<Object?>?) ?? const <Object?>[],
        ...(declaration['implements'] as List<Object?>?) ?? const <Object?>[],
      ])
        mapper.mapType(base, generic: true, scopes: scopes, context: id),
      'JSObject',
    };
    out.writeln(
      'extension type $name$clause(JSObject _self) '
      'implements ${bases.join(', ')} {',
    );
    _emitMembers(
      children.where((child) => child['static'] != true).toList(),
      out,
      receiver: '_self',
    );
    // The class object itself: constructors and statics, reached through
    // the module wrapper rather than any global.
    out
      ..writeln('}')
      ..writeln()
      ..writeln(
        'extension type ${name}Ctor(JSFunction _self) implements JSObject {',
      );
    final ownerClause = mapper.typeParameterClause(declaration);
    final ownerParameters =
        (declaration['typeParameters'] as List<Object?>?) ?? const [];
    final instantiated = ownerParameters.isEmpty
        ? name
        : '$name<${ownerParameters.map(
            (parameter) => (parameter! as Map<Object?, Object?>)['name']! as String,
          ).join(', ')}>';
    out
      ..writeln('  bool isInstance(JSAny? value) {')
      ..writeln('    if (value == null) return false;')
      ..writeln("    final prototype = _self.getProperty('prototype'.toJS);")
      ..writeln('    if (prototype is! JSObject) return false;')
      ..writeln('    return (prototype.callMethod(')
      ..writeln("      'isPrototypeOf'.toJS,")
      ..writeln('      value,')
      ..writeln('    )! as JSBoolean).toDart;')
      ..writeln('  }')
      ..writeln('  $instantiated cast$ownerClause(JSAny? value) {')
      ..writeln('    if (!isInstance(value)) {')
      ..writeln(
        "      throw ArgumentError('value is not an instance of $name');",
      )
      ..writeln('    }')
      ..writeln('    return $instantiated(value! as JSObject);')
      ..writeln('  }');
    final hasConstructor = children.any(
      (child) => child['kind'] == 'constructor' && isEmitted(child),
    );
    if (!hasConstructor) {
      out
        ..writeln('  $instantiated new\$$ownerClause() =>')
        ..writeln('      _self.callAsConstructorVarArgs<JSObject>(const [])')
        ..writeln('          as $instantiated;');
    }
    for (final child in children.where(isEmitted)) {
      if (child['kind'] == 'constructor') {
        _emitConstructor(name, child, out);
      } else if (child['static'] == true) {
        _emitMembers([child], out, receiver: '_self');
      }
    }
    out
      ..writeln('}')
      ..writeln();
  }

  void _emitConstructor(
    String className,
    Map<String, Object?> declaration,
    StringBuffer out,
  ) {
    final ordinal = declaration['overloadOrdinal'];
    final suffix = ordinal is int && ordinal > 0 ? '\$${ordinal + 1}' : '';
    final scopes = mapper.scopesFor(declaration);
    final id = declaration['id']! as String;
    final parameters =
        (declaration['parameters'] as List<Object?>?) ?? const [];
    final owner = mapper.byId[declaration['parentId']]!;
    final ownerClause = mapper.typeParameterClause(owner);
    final ownerParameters =
        (owner['typeParameters'] as List<Object?>?) ?? const [];
    final instantiated = ownerParameters.isEmpty
        ? className
        : '$className<${ownerParameters.map(
            (parameter) => (parameter! as Map<Object?, Object?>)['name']! as String,
          ).join(', ')}>';
    final signature = _helperParameters(parameters, scopes, id);
    final trimmed =
        '${signature.local}.sublist(0, ${signature.trimExpression})';
    out
      ..writeln(
        '  $instantiated new\$$suffix$ownerClause(${signature.clause}) {',
      )
      ..writeln('    final ${signature.local} = <JSAny?>[${signature.values}];')
      ..writeln(
        '    return _self.callAsConstructorVarArgs<JSObject>($trimmed)'
        ' as $instantiated;',
      )
      ..writeln('  }');
  }

  void _emitTypeLiteral(Map<String, Object?> declaration, StringBuffer out) {
    final name = mapper.hashName('JSAnon', declaration['shapeHash']);
    if (_anonTypes.containsKey(name)) {
      return;
    }
    final children =
        mapper.childrenByParent[declaration['id']] ??
        const <Map<String, Object?>>[];
    final hasCallSignature = children.any(
      (child) => child['kind'] == 'callSignature',
    );
    final representation = hasCallSignature ? 'JSFunction' : 'JSObject';
    final body = StringBuffer()
      ..writeln(
        'extension type $name($representation _self) '
        'implements JSObject {',
      );
    if (representation == 'JSObject') {
      _emitLiteralFactory(name, children, body, eraseScopeReferences: true);
    }
    _emitMembers(children, body, receiver: '_self', eraseScopeReferences: true);
    body
      ..writeln('}')
      ..writeln();
    _anonTypes[name] = body.toString();
    out.write(_anonTypes[name]);
  }

  void _emitMembers(
    List<Map<String, Object?>> children,
    StringBuffer out, {
    required String receiver,
    bool eraseScopeReferences = false,
  }) {
    var indexSignatures = 0;
    for (final child in children) {
      if (!isEmitted(child)) {
        continue;
      }
      switch (child['kind']) {
        case 'property':
          _emitProperty(child, out, eraseScopeReferences: eraseScopeReferences);
        case 'method' || 'function':
          _emitCallable(
            child,
            out,
            receiver: receiver,
            eraseScopeReferences: eraseScopeReferences,
          );
        case 'indexSignature':
          indexSignatures += 1;
          _emitIndexSignature(
            child,
            out,
            ordinal: indexSignatures,
            eraseScopeReferences: eraseScopeReferences,
          );
        case 'callSignature':
          _emitCallSignature(
            child,
            out,
            receiver: receiver,
            eraseScopeReferences: eraseScopeReferences,
          );
        case 'constructor':
          break; // Emitted on the Ctor type.
        case 'typeLiteral':
          break; // Registered literals emit as their own top-level types.
        default:
          throw ParityGenerationException(
            child['id']! as String,
            "no Total Mapping Rule for member kind ${child['kind']}",
          );
      }
    }
  }

  void _emitProperty(
    Map<String, Object?> declaration,
    StringBuffer out, {
    bool eraseScopeReferences = false,
  }) {
    final dartName = mapper.dartName(declaration['name']! as String);
    final rename = _jsRename(declaration, dartName);
    final scopes = mapper.scopesFor(declaration);
    final id = declaration['id']! as String;
    var type = mapper.mapType(
      declaration['type'],
      generic: false,
      scopes: scopes,
      context: id,
      eraseScopeReferences: eraseScopeReferences,
    );
    if (declaration['optional'] == true &&
        !type.endsWith('?') &&
        type != 'void') {
      type = '$type?';
    }
    if (type == 'void') {
      type = 'JSAny?';
    }
    if (rename != null) {
      out.writeln("  @JS('$rename')");
    }
    out.writeln('  external $type get $dartName;');
    if (declaration['readonly'] != true) {
      if (rename != null) {
        out.writeln("  @JS('$rename')");
      }
      out.writeln('  external set $dartName($type value);');
    }
  }

  void _emitCallable(
    Map<String, Object?> declaration,
    StringBuffer out, {
    required String receiver,
    bool eraseScopeReferences = false,
  }) {
    final scopes = mapper.scopesFor(declaration);
    final id = declaration['id']! as String;
    final dartName = mapper.memberName(declaration);
    final jsName = declaration['name']! as String;
    final clause = mapper.typeParameterClause(declaration);
    final parameters =
        (declaration['parameters'] as List<Object?>?) ?? const [];
    final hasRest = parameters.any(
      (parameter) => (parameter! as Map<Object?, Object?>)['rest'] == true,
    );
    final ownScopes = [
      ...scopes,
      if (declaration['typeParameters'] is List<Object?>)
        {
          for (final parameter
              in declaration['typeParameters']! as List<Object?>)
            (parameter! as Map<Object?, Object?>)['name']! as String,
        },
    ];

    if (hasRest) {
      final returnType = mapper.nullableForGeneric(
        mapper.mapType(
          declaration['returnType'],
          generic: true,
          scopes: ownScopes,
          context: id,
          eraseScopeReferences: eraseScopeReferences,
        ),
      );
      final signature = _helperParameters(
        parameters,
        ownScopes,
        id,
        eraseScopeReferences: eraseScopeReferences,
      );
      final trimmed =
          '${signature.local}.sublist(0, ${signature.trimExpression})';
      final call =
          "$receiver.callMethodVarArgs<$returnType>('$jsName'.toJS, $trimmed)";
      out
        ..writeln('  $returnType $dartName$clause(${signature.clause}) {')
        ..writeln(
          '    final ${signature.local} = <JSAny?>[${signature.values}];',
        )
        ..writeln('    return $call;')
        ..writeln('  }');
      return;
    }

    final returnType = mapper.mapType(
      declaration['returnType'],
      generic: false,
      scopes: ownScopes,
      context: id,
      eraseScopeReferences: eraseScopeReferences,
    );
    final required = <String>[];
    final optional = <String>[];
    for (final rawParameter in parameters) {
      final parameter = (rawParameter! as Map<Object?, Object?>)
          .cast<String, Object?>();
      var type = mapper.mapType(
        parameter['type'],
        generic: false,
        scopes: ownScopes,
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
      } else {
        required.add('$type $parameterName');
      }
    }
    final signature = [
      required.join(', '),
      if (optional.isNotEmpty) '[${optional.join(', ')}]',
    ].where((part) => part.isNotEmpty).join(', ');
    final rename = dartName == jsName ? null : jsName;
    if (rename != null) {
      out.writeln("  @JS('$rename')");
    }
    out.writeln('  external $returnType $dartName$clause($signature);');
  }

  void _emitIndexSignature(
    Map<String, Object?> declaration,
    StringBuffer out, {
    required int ordinal,
    bool eraseScopeReferences = false,
  }) {
    final scopes = mapper.scopesFor(declaration);
    final id = declaration['id']! as String;
    final parameters = declaration['parameters']! as List<Object?>;
    final keyType = mapper.mapType(
      (parameters.first! as Map<Object?, Object?>)['type'],
      generic: false,
      scopes: scopes,
      context: id,
      eraseScopeReferences: eraseScopeReferences,
    );
    var valueType = mapper.mapType(
      declaration['returnType'],
      generic: false,
      scopes: scopes,
      context: id,
      eraseScopeReferences: eraseScopeReferences,
    );
    if (valueType == 'void') {
      valueType = 'JSAny?';
    }
    if (!valueType.endsWith('?') && !_isPrimitiveDart(valueType)) {
      valueType = '$valueType?';
    }
    if (ordinal == 1) {
      out.writeln('  external $valueType operator []($keyType key);');
      if (declaration['readonly'] != true) {
        out.writeln(
          '  external void operator []=($keyType key, $valueType value);',
        );
      }
      return;
    }
    // Only one operator pair is expressible; later signatures become
    // deterministic named accessors.
    out.writeln(
      '  $valueType indexGet\$$ordinal($keyType key) => '
      '_self.getProperty(key.toString().toJS);',
    );
    if (declaration['readonly'] != true) {
      out.writeln(
        '  void indexSet\$$ordinal($keyType key, $valueType value) => '
        '_self.setProperty(key.toString().toJS, value as JSAny?);',
      );
    }
  }

  bool _isPrimitiveDart(String type) =>
      type == 'String' || type == 'num' || type == 'bool' || type == 'int';

  void _emitCallSignature(
    Map<String, Object?> declaration,
    StringBuffer out, {
    required String receiver,
    bool eraseScopeReferences = false,
  }) {
    final scopes = mapper.scopesFor(declaration);
    final id = declaration['id']! as String;
    final parameters =
        (declaration['parameters'] as List<Object?>?) ?? const [];
    final signature = _helperParameters(
      parameters,
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

    final local = signature.local;
    final count = '${local}Count';
    final arguments = [
      for (var index = 0; index < parameters.length; index += 1)
        '$count > $index ? $local[$index] : null',
    ].join(', ');
    final argumentTail = arguments.isEmpty ? '' : ', $arguments';
    out
      ..writeln('  $returnType call(${signature.clause}) {')
      ..writeln('    final $local = <JSAny?>[${signature.values}];')
      ..writeln('    final $count = ${signature.trimExpression};')
      ..writeln(
        '    return $receiver.callAsFunction(null$argumentTail)'
        ' as $returnType;',
      )
      ..writeln('  }');
  }

  /// Builds a JS-typed helper parameter list with trailing-optional
  /// trimming: optionals are nullable and trailing nulls are not passed.
  ({String clause, String values, String trimExpression, String local})
  _helperParameters(
    List<Object?> parameters,
    List<Set<String>> scopes,
    String context, {
    bool eraseScopeReferences = false,
  }) {
    var dollars = 1;
    bool collides(int count) => parameters.any(
      (parameter) =>
          (parameter! as Map<Object?, Object?>)['name'] ==
          'args${r'$' * count}',
    );
    while (collides(dollars)) {
      dollars += 1;
    }
    final local = 'args${r'$' * dollars}';
    final requiredParts = <String>[];
    final optionalParts = <String>[];
    final values = <String>[];
    var requiredCount = 0;
    var restValues = '';
    for (final rawParameter in parameters) {
      final parameter = (rawParameter! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final parameterName = mapper.dartName(parameter['name']! as String);
      if (parameter['rest'] == true) {
        optionalParts.add('List<JSAny?> $parameterName = const []');
        restValues = '...$parameterName';
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
      if (parameter['optional'] == true) {
        if (!type.endsWith('?')) {
          type = '$type?';
        }
        optionalParts.add('$type $parameterName');
      } else {
        requiredCount += 1;
        requiredParts.add('$type $parameterName');
      }
      values.add(parameterName);
    }
    final clause = [
      requiredParts.join(', '),
      if (optionalParts.isNotEmpty) '[${optionalParts.join(', ')}]',
    ].where((part) => part.isNotEmpty).join(', ');
    final allValues = [
      values.join(', '),
      restValues,
    ].where((v) => v.isNotEmpty).join(', ');
    final trimExpression = restValues.isNotEmpty
        ? '$local.length'
        : '_trimTrailingNulls($local, $requiredCount)';
    return (
      clause: clause,
      values: allValues,
      trimExpression: trimExpression,
      local: local,
    );
  }

  void _emitRoot(StringBuffer out) {
    out
      ..writeln('/// The VS Code API module object, as passed to activation.')
      ..writeln('///')
      ..writeln('/// The module wrapper is the only root of this layer: no')
      ..writeln('/// generated code resolves names through JS scope.')
      ..writeln(
        'extension type VscodeApi(JSObject _self) '
        'implements JSObject {',
      );
    for (final declaration in mapper.declarations) {
      if (declaration['parentId'] != 'module:vscode' ||
          !isEmitted(declaration)) {
        continue;
      }
      final name = declaration['name']! as String;
      switch (declaration['kind']) {
        case 'namespace':
          out.writeln(
            '  external ${mapper.namespaceTypeName(name)} get $name;',
          );
        case 'class':
          out.writeln('  external ${name}Ctor get $name;');
        case 'enum':
          out.writeln('  external ${name}Values get $name;');
        case 'variable':
          _emitVariable(declaration, out);
        case 'interface' || 'typeAlias':
          break; // Types have no runtime object on the module.
        default:
          throw ParityGenerationException(
            declaration['id']! as String,
            'no Total Mapping Rule for module member kind '
            "${declaration['kind']}",
          );
      }
    }
    out
      ..writeln('}')
      ..writeln()
      ..writeln('int _trimTrailingNulls(List<JSAny?> args, int floor) {')
      ..writeln('  var length = args.length;')
      ..writeln('  while (length > floor && args[length - 1] == null) {')
      ..writeln('    length -= 1;')
      ..writeln('  }')
      ..writeln('  return length;')
      ..writeln('}');
  }
}
