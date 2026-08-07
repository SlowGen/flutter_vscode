/// The IR index and type-mapping half of the binding emitters.
///
/// [IrTypeMapper] owns the ctor-built declaration indexes and every Total
/// Mapping Rule that turns an IR type node into a Dart type, together with
/// the name mangling and the helper-type registries (tuples, literal
/// wrappers, intersection operand sets) those rules populate. Both the
/// Parity Layer emitter (`parity_layer.dart`) and the dart-layer emitter
/// (`dart_layer.dart`) consume one shared mapper, so the two layers see
/// identical indexes and mapped types. Scope-reference erasure — active
/// inside registered helper types, which hoist to the top level where no
/// type parameters are in scope — is a per-call parameter of
/// [IrTypeMapper.mapType], never mutable state on the mapper.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';

/// A construct reached the emitter without a Total Mapping Rule.
final class ParityGenerationException implements Exception {
  /// Creates an actionable totality failure.
  ParityGenerationException(this.declarationId, this.message);

  /// The IR declaration that could not be mapped.
  final String declarationId;

  /// What rule is missing.
  final String message;

  @override
  String toString() => 'PARITY_TOTALITY_ERROR: $declarationId: $message';
}

const _reservedWords = {
  'assert', 'break', 'case', 'catch', 'class', 'const', 'continue',
  'default', 'do', 'else', 'enum', 'extends', 'false', 'final', 'finally',
  'for', 'if', 'in', 'is', 'new', 'null', 'rethrow', 'return', 'super',
  'switch', 'this', 'throw', 'true', 'try', 'var', 'void', 'while', 'with',
  // Object core members that extension types may not redeclare compatibly.
  'toString', 'hashCode', 'runtimeType', 'noSuchMethod',
};

/// The IR index and Total Mapping Rules for types, shared by both emitters.
final class IrTypeMapper {
  /// Indexes the IR declarations for emission.
  IrTypeMapper(Map<String, Object?> inventory)
    : declarations = [
        for (final declaration in inventory['declarations']! as List<Object?>)
          (declaration! as Map<Object?, Object?>).cast<String, Object?>(),
      ] {
    for (final declaration in declarations) {
      byId[declaration['id']! as String] = declaration;
      childrenByParent
          .putIfAbsent(declaration['parentId']! as String, () => [])
          .add(declaration);
    }
    for (final declaration in declarations) {
      final parent = declaration['parentId']! as String;
      if (parent == 'module:vscode' || parent == 'global:global') {
        topLevelByName[declaration['name']! as String] = declaration;
      }
    }
  }

  /// The IR declarations in pinned order.
  final List<Map<String, Object?>> declarations;

  /// Declarations indexed by IR id.
  final byId = <String, Map<String, Object?>>{};

  /// Child declarations indexed by their parent id.
  final childrenByParent = <String, List<Map<String, Object?>>>{};

  /// Module- and global-rooted declarations indexed by name.
  final topLevelByName = <String, Map<String, Object?>>{};

  /// Generated tuple extension types by name.
  final tupleTypes = <String, String>{};

  /// Mapped element types of each generated tuple, by tuple name.
  final tupleElements = <String, List<String>>{};

  /// Generated string-literal wrapper types by name.
  final literalWrappers = <String, String>{};

  /// Mapped operand types of each registered intersection, by hash name.
  ///
  /// The mapper registers the operand sets; the parity emitter builds the
  /// hoisted extension-type bodies from them, because conflict members are
  /// redeclared with the emitter's member rules.
  final intersectionOperands = <String, List<String>>{};

  static const _externalReferenceMap = {
    'Uint8Array': 'JSUint8Array',
    'Uint32Array': 'JSUint32Array',
    'Record': 'JSObject',
    'RegExp': 'JSObject',
    'Error': 'JSObject',
    'Iterable': 'JSObject',
    'AsyncIterable': 'JSObject',
    'IterableIterator': 'JSObject',
    'Date': 'JSObject',
  };

  // ----------------------------------------------------------------- names

  /// Maps a JS name to its mangled Dart name (reserved words, underscores).
  String dartName(String jsName) {
    var name = jsName;
    if (name.startsWith('_')) {
      name = '\$$name';
    }
    if (_reservedWords.contains(name)) {
      name = '$name\$';
    }
    return name;
  }

  /// The Dart member name for [declaration], including overload suffixes.
  String memberName(Map<String, Object?> declaration) {
    final base = dartName(declaration['name']! as String);
    final ordinal = declaration['overloadOrdinal'];
    if (ordinal is int && ordinal > 0) {
      return '$base\$${ordinal + 1}';
    }
    return base;
  }

  /// The generated extension-type name for a namespace.
  String namespaceTypeName(String name) =>
      '${name[0].toUpperCase()}${name.substring(1)}Ns';

  /// A deterministic hash-derived type name for a canonical shape.
  String hashName(String prefix, Object? shape) {
    final digest = sha256.convert(utf8.encode(jsonEncode(shape))).toString();
    return '${prefix}_${digest.substring(0, 12)}';
  }

  /// The type-parameter scopes visible from [declaration].
  List<Set<String>> scopesFor(Map<String, Object?> declaration) {
    final scopes = <Set<String>>[];
    Map<String, Object?>? cursor = declaration;
    while (cursor != null) {
      final parameters = cursor['typeParameters'];
      if (parameters is List<Object?>) {
        scopes.add({
          for (final parameter in parameters)
            (parameter! as Map<Object?, Object?>)['name']! as String,
        });
      }
      cursor = byId[cursor['parentId']];
    }
    return scopes;
  }

  /// The Dart type-parameter clause for [declaration], or the empty string.
  String typeParameterClause(Map<String, Object?> declaration) {
    final parameters = declaration['typeParameters'];
    if (parameters is! List<Object?> || parameters.isEmpty) {
      return '';
    }
    final names = [
      for (final parameter in parameters)
        (parameter! as Map<Object?, Object?>)['name']! as String,
    ];
    return '<${names.map((name) => '$name extends JSAny?').join(', ')}>';
  }

  // ----------------------------------------------------------------- types

  /// Maps one IR type node to a Dart type.
  ///
  /// [generic] selects JS-typed form (valid inside generics and helpers)
  /// over the primitive-friendly external form. [eraseScopeReferences]
  /// erases in-scope type-parameter references to `JSAny?`; callers pass
  /// it while mapping registered helper types, which hoist to the top
  /// level where no type parameters are in scope.
  String mapType(
    Object? node, {
    required bool generic,
    required List<Set<String>> scopes,
    required String context,
    bool eraseScopeReferences = false,
  }) {
    if (node is! Map<Object?, Object?>) {
      throw ParityGenerationException(context, 'non-object type node');
    }
    final type = node.cast<String, Object?>();
    switch (type['kind']) {
      case 'primitive':
        return _mapPrimitive(type['name']! as String, generic, context);
      case 'literal':
        final value = type['value'];
        if (value is String) {
          return generic ? 'JSString' : 'String';
        }
        if (value is num) {
          return generic ? 'JSNumber' : 'num';
        }
        if (value is bool) {
          return generic ? 'JSBoolean' : 'bool';
        }
        return 'JSAny?';
      case 'reference':
        return _mapReference(
          type,
          generic: generic,
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        );
      case 'array':
        final element = mapType(
          type['elementType'],
          generic: true,
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        );
        return 'JSArray<${nullableForGeneric(element)}>';
      case 'union':
        return _mapUnion(
          type,
          generic: generic,
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        );
      case 'intersection':
        return _registerIntersection(type, scopes: scopes, context: context);
      case 'tuple':
        return _registerTuple(type, scopes: scopes, context: context);
      case 'typeLiteral':
        final id = type['id'];
        if (id is String) {
          final declaration = byId[id];
          if (declaration == null) {
            throw ParityGenerationException(
              context,
              'reference to unregistered type literal $id',
            );
          }
          return hashName('JSAnon', declaration['shapeHash']);
        }
        return 'JSObject';
      case 'function':
        return 'JSFunction';
      case 'operator':
        if (type['operator'] == 'readonly') {
          return mapType(
            type['type'],
            generic: generic,
            scopes: scopes,
            context: context,
            eraseScopeReferences: eraseScopeReferences,
          );
        }
        throw ParityGenerationException(
          context,
          'no Total Mapping Rule for type operator ${type['operator']}',
        );
      default:
        throw ParityGenerationException(
          context,
          'no Total Mapping Rule for type kind ${type['kind']}',
        );
    }
  }

  String _mapPrimitive(String name, bool generic, String context) {
    switch (name) {
      case 'string':
        return generic ? 'JSString' : 'String';
      case 'number':
        return generic ? 'JSNumber' : 'num';
      case 'boolean':
        return generic ? 'JSBoolean' : 'bool';
      case 'void':
        return generic ? 'JSAny?' : 'void';
      case 'any' || 'unknown' || 'null' || 'undefined' || 'never':
        return 'JSAny?';
      case 'object':
        return 'JSObject';
      case 'symbol':
        return 'JSSymbol';
      case 'bigint':
        return 'JSBigInt';
      default:
        throw ParityGenerationException(
          context,
          'no Total Mapping Rule for primitive $name',
        );
    }
  }

  String _mapReference(
    Map<String, Object?> type, {
    required bool generic,
    required List<Set<String>> scopes,
    required String context,
    required bool eraseScopeReferences,
  }) {
    final name = type['name']! as String;
    final arguments = (type['typeArguments'] as List<Object?>?) ?? const [];

    for (final scope in scopes) {
      if (scope.contains(name)) {
        return eraseScopeReferences ? 'JSAny?' : name;
      }
    }
    if (name.contains('.')) {
      final prefix = name.split('.').first;
      final target = topLevelByName[prefix];
      if (target != null && target['kind'] == 'enum') {
        return generic ? 'JSNumber' : 'int';
      }
      throw ParityGenerationException(
        context,
        'no Total Mapping Rule for dotted reference $name',
      );
    }
    if (name == 'Thenable' || name == 'PromiseLike' || name == 'Promise') {
      final argument = arguments.isEmpty
          ? 'JSAny?'
          : mapType(
              arguments.first,
              generic: true,
              scopes: scopes,
              context: context,
              eraseScopeReferences: eraseScopeReferences,
            );
      return 'JSPromise<${nullableForGeneric(argument)}>';
    }
    if (name == 'Array' || name == 'ReadonlyArray') {
      final argument = arguments.isEmpty
          ? 'JSAny?'
          : mapType(
              arguments.first,
              generic: true,
              scopes: scopes,
              context: context,
              eraseScopeReferences: eraseScopeReferences,
            );
      return 'JSArray<${nullableForGeneric(argument)}>';
    }
    if (name == 'Readonly' && arguments.isNotEmpty) {
      return mapType(
        arguments.first,
        generic: generic,
        scopes: scopes,
        context: context,
        eraseScopeReferences: eraseScopeReferences,
      );
    }
    final external = _externalReferenceMap[name];
    if (external != null) {
      return external;
    }

    final target = topLevelByName[name];
    if (target == null) {
      throw ParityGenerationException(
        context,
        'no Total Mapping Rule for reference $name',
      );
    }
    switch (target['kind']) {
      case 'enum':
        return generic ? 'JSNumber' : 'int';
      case 'typeAlias':
        return _mapAliasReference(
          target,
          arguments,
          generic: generic,
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        );
      case 'interface' || 'class':
        final parameters =
            (target['typeParameters'] as List<Object?>?) ?? const [];
        if (parameters.isEmpty) {
          return name;
        }
        final mappedArguments = <String>[
          for (var index = 0; index < parameters.length; index += 1)
            index < arguments.length
                ? nullableForGeneric(
                    mapType(
                      arguments[index],
                      generic: true,
                      scopes: scopes,
                      context: context,
                      eraseScopeReferences: eraseScopeReferences,
                    ),
                  )
                : 'JSAny?',
        ];
        return '$name<${mappedArguments.join(', ')}>';
      default:
        throw ParityGenerationException(
          context,
          'no Total Mapping Rule for reference to ${target['kind']} $name',
        );
    }
  }

  /// Alias references are expanded position-correctly by substitution; the
  /// emitted typedef exists for Extension Authors, not for internal use.
  ///
  /// The one exception is an alias whose body is a union consisting only
  /// of string literals: its zero-cost wrapper is named after the alias
  /// (parity-runtime ledger entry 6), so non-generic positions keep the
  /// upstream name instead of a shape-hash name.
  String _mapAliasReference(
    Map<String, Object?> alias,
    List<Object?> arguments, {
    required bool generic,
    required List<Set<String>> scopes,
    required String context,
    required bool eraseScopeReferences,
  }) {
    final literalUnion = stringLiteralUnion(alias['type']);
    if (literalUnion != null && !generic) {
      final name = registerLiteralWrapper(
        literalUnion.members,
        name: alias['name']! as String,
      );
      return literalUnion.nullable ? '$name?' : name;
    }
    final parameters = (alias['typeParameters'] as List<Object?>?) ?? const [];
    var body = alias['type'];
    if (parameters.isNotEmpty) {
      final substitutions = <String, Object?>{
        for (var index = 0; index < parameters.length; index += 1)
          (parameters[index]! as Map<Object?, Object?>)['name']!
              as String: index < arguments.length
              ? arguments[index]
              : {'kind': 'primitive', 'name': 'any'},
      };
      body = substitute(body, substitutions);
    }
    return mapType(
      body,
      generic: generic,
      scopes: scopes,
      context: context,
      eraseScopeReferences: eraseScopeReferences,
    );
  }

  /// Substitutes type-parameter references in an IR type node.
  Object? substitute(Object? node, Map<String, Object?> substitutions) {
    if (node is List<Object?>) {
      return [for (final item in node) substitute(item, substitutions)];
    }
    if (node is! Map<Object?, Object?>) {
      return node;
    }
    final map = node.cast<String, Object?>();
    if (map['kind'] == 'reference' &&
        substitutions.containsKey(map['name']) &&
        ((map['typeArguments'] as List<Object?>?) ?? const []).isEmpty) {
      return substitutions[map['name']];
    }
    return {
      for (final entry in map.entries)
        entry.key: substitute(entry.value, substitutions),
    };
  }

  String _mapUnion(
    Map<String, Object?> type, {
    required bool generic,
    required List<Set<String>> scopes,
    required String context,
    required bool eraseScopeReferences,
  }) {
    final members = (type['types']! as List<Object?>)
        .map(
          (member) =>
              (member! as Map<Object?, Object?>).cast<String, Object?>(),
        )
        .toList();
    var nullable = false;
    final rest = <Map<String, Object?>>[];
    for (final member in members) {
      if (member['kind'] == 'primitive' &&
          (member['name'] == 'null' || member['name'] == 'undefined')) {
        nullable = true;
      } else {
        rest.add(member);
      }
    }
    if (rest.isEmpty) {
      return 'JSAny?';
    }
    final allStringLiterals =
        rest.length > 1 &&
        rest.every(
          (member) => member['kind'] == 'literal' && member['value'] is String,
        );
    if (allStringLiterals && !generic) {
      final name = registerLiteralWrapper(rest);
      return nullable ? '$name?' : name;
    }
    String base;
    if (rest.length == 1) {
      base = mapType(
        rest.single,
        generic: generic,
        scopes: scopes,
        context: context,
        eraseScopeReferences: eraseScopeReferences,
      );
    } else {
      final categories = {
        for (final member in rest)
          _lubCategory(
            member,
            scopes: scopes,
            context: context,
            eraseScopeReferences: eraseScopeReferences,
          ),
      };
      if (categories.length == 1) {
        base = switch (categories.single) {
          'S' => generic ? 'JSString' : 'String',
          'N' => generic ? 'JSNumber' : 'num',
          'B' => generic ? 'JSBoolean' : 'bool',
          'O' => 'JSObject',
          _ => 'JSAny?',
        };
      } else {
        base = 'JSAny';
      }
    }
    if (nullable && !base.endsWith('?') && base != 'void') {
      base = '$base?';
    }
    return base;
  }

  String _lubCategory(
    Map<String, Object?> member, {
    required List<Set<String>> scopes,
    required String context,
    required bool eraseScopeReferences,
  }) {
    switch (member['kind']) {
      case 'primitive':
        return switch (member['name']) {
          'string' => 'S',
          'number' => 'N',
          'boolean' => 'B',
          'object' => 'O',
          _ => 'A',
        };
      case 'literal':
        final value = member['value'];
        if (value is String) return 'S';
        if (value is num) return 'N';
        if (value is bool) return 'B';
        return 'A';
      case 'reference':
        final name = member['name']! as String;
        for (final scope in scopes) {
          if (scope.contains(name)) {
            return 'A';
          }
        }
        if (name.contains('.')) {
          return 'N';
        }
        final target = topLevelByName[name];
        if (target != null && target['kind'] == 'enum') {
          return 'N';
        }
        if (target != null && target['kind'] == 'typeAlias') {
          final mapped = _mapAliasReference(
            target,
            (member['typeArguments'] as List<Object?>?) ?? const [],
            generic: true,
            scopes: scopes,
            context: context,
            eraseScopeReferences: eraseScopeReferences,
          );
          return _categoryOfMapped(mapped);
        }
        return 'O';
      case 'array' || 'tuple' || 'typeLiteral' || 'function' || 'intersection':
        return 'O';
      case 'union':
        final mapped = _mapUnion(
          member.cast<String, Object?>(),
          generic: true,
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        );
        return _categoryOfMapped(mapped);
      case 'operator':
        return _lubCategory(
          (member['type']! as Map<Object?, Object?>).cast<String, Object?>(),
          scopes: scopes,
          context: context,
          eraseScopeReferences: eraseScopeReferences,
        );
      default:
        return 'A';
    }
  }

  String _categoryOfMapped(String mapped) {
    final bare = mapped.endsWith('?')
        ? mapped.substring(0, mapped.length - 1)
        : mapped;
    if (bare == 'JSString' || bare == 'String') return 'S';
    if (bare == 'JSNumber' || bare == 'num' || bare == 'int') return 'N';
    if (bare == 'JSBoolean' || bare == 'bool') return 'B';
    if (bare == 'JSAny') return 'A';
    return 'O';
  }

  /// Rewrites `void` to `JSAny?` so a type is valid in generic positions.
  String nullableForGeneric(String type) => type == 'void' ? 'JSAny?' : type;

  // ------------------------------------------------------------ registries

  /// Detects a union type consisting only of string literals (plus an
  /// optional `null`/`undefined` member), the construct behind zero-cost
  /// literal wrappers; returns `null` for every other type node.
  ({List<Map<String, Object?>> members, bool nullable})? stringLiteralUnion(
    Object? node,
  ) {
    if (node is! Map<Object?, Object?>) {
      return null;
    }
    final type = node.cast<String, Object?>();
    if (type['kind'] != 'union') {
      return null;
    }
    var nullable = false;
    final rest = <Map<String, Object?>>[];
    for (final rawMember in type['types']! as List<Object?>) {
      final member = (rawMember! as Map<Object?, Object?>)
          .cast<String, Object?>();
      if (member['kind'] == 'primitive' &&
          (member['name'] == 'null' || member['name'] == 'undefined')) {
        nullable = true;
      } else {
        rest.add(member);
      }
    }
    final allStringLiterals =
        rest.length > 1 &&
        rest.every(
          (member) => member['kind'] == 'literal' && member['value'] is String,
        );
    if (!allStringLiterals) {
      return null;
    }
    return (members: rest, nullable: nullable);
  }

  /// Zero-cost typed wrapper for a union of string literals: the value
  /// IS the string; one generated constant per literal. Anonymous unions
  /// take a shape-hash name; an all-string-literal alias passes its own
  /// [name] so the wrapper keeps the upstream name.
  String registerLiteralWrapper(
    List<Map<String, Object?>> members, {
    String? name,
  }) {
    final values = [for (final member in members) member['value']! as String]
      ..sort();
    final wrapperName = name ?? hashName('JSLit', values);
    literalWrappers.putIfAbsent(wrapperName, () {
      final buffer = StringBuffer()
        ..writeln('extension type const $wrapperName(String value) {');
      for (var index = 0; index < values.length; index += 1) {
        final literal = values[index];
        final identifier =
            RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(literal) &&
                dartName(literal) == literal
            ? literal
            : 'value\$${index + 1}';
        buffer.writeln(
          "  static const $identifier = $wrapperName('$literal');",
        );
      }
      buffer
        ..writeln('}')
        ..writeln();
      return buffer.toString();
    });
    return wrapperName;
  }

  String _registerTuple(
    Map<String, Object?> type, {
    required List<Set<String>> scopes,
    required String context,
  }) {
    final elements = type['elements']! as List<Object?>;
    final mapped = <String>[
      for (final element in elements)
        nullableForGeneric(
          mapType(
            element is Map<Object?, Object?> && element['type'] != null
                ? element['type']
                : element,
            generic: true,
            scopes: scopes,
            context: context,
            eraseScopeReferences: true,
          ),
        ),
    ];
    final name = hashName('JSTuple', mapped);
    tupleElements.putIfAbsent(name, () => mapped);
    tupleTypes.putIfAbsent(name, () {
      final buffer = StringBuffer()
        ..writeln(
          'extension type $name(JSArray<JSAny?> _self) '
          'implements JSObject {',
        );
      for (var index = 0; index < mapped.length; index += 1) {
        final cast = mapped[index] == 'JSAny?' ? '' : ' as ${mapped[index]}';
        buffer.writeln(
          '  ${mapped[index]} get \$${index + 1} => _self[$index]$cast;',
        );
      }
      buffer
        ..writeln('}')
        ..writeln();
      return buffer.toString();
    });
    return name;
  }

  String _registerIntersection(
    Map<String, Object?> type, {
    required List<Set<String>> scopes,
    required String context,
  }) {
    final operands = type['types']! as List<Object?>;
    final mapped = <String>[
      for (final operand in operands)
        mapType(
          operand,
          generic: true,
          scopes: scopes,
          context: context,
          eraseScopeReferences: true,
        ),
    ];
    final name = hashName('JSIntersection', mapped);
    intersectionOperands.putIfAbsent(name, () => mapped);
    return name;
  }
}
