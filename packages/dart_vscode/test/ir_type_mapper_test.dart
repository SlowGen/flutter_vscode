import 'dart:io';

import 'package:test/test.dart';

import '../tool/binding_generator/ir_type_mapper.dart';

/// A-3: the IR-index + type-mapping half of the parity emitter as a
/// standalone module. [IrTypeMapper] owns the ctor-built indexes, the
/// Total Mapping Rules for types, and the name mangling both emitters
/// share; scope-reference erasure is a per-call parameter, never
/// mutable state on the mapper.
void main() {
  final mapper = IrTypeMapper({
    'schemaVersion': 1,
    'declarations': [
      _class('Uri'),
      _iface('Box'),
      _property(_boxId, 'with', _string),
      _property(_boxId, '_inner', _string),
      _method(_boxId, 'open', parameters: [_param('a', _string)]),
      _method(
        _boxId,
        'open',
        parameters: [_param('a', _number)],
        overloadOrdinal: 1,
      ),
    ],
  });

  group('ctor-built indexes', () {
    test('byId resolves declarations by IR id', () {
      expect(mapper.byId[_boxId]!['name'], 'Box');
      expect(mapper.byId['class:vscode.Uri']!['kind'], 'class');
    });

    test('childrenByParent groups member declarations', () {
      final names = [
        for (final child in mapper.childrenByParent[_boxId]!)
          child['name']! as String,
      ];
      expect(names, ['with', '_inner', 'open', 'open']);
    });

    test('topLevelByName indexes module-rooted declarations', () {
      expect(mapper.topLevelByName['Uri']!['kind'], 'class');
      expect(mapper.topLevelByName['Box']!['kind'], 'interface');
      expect(mapper.topLevelByName, isNot(contains('with')));
    });
  });

  group('mapType Total Mapping Rules', () {
    test('scalars take the primitive-friendly or JS-typed form', () {
      expect(
        mapper.mapType(
          _string,
          generic: false,
          scopes: const [],
          context: 'spec',
        ),
        'String',
      );
      expect(
        mapper.mapType(
          _string,
          generic: true,
          scopes: const [],
          context: 'spec',
        ),
        'JSString',
      );
      expect(
        mapper.mapType(
          const {'kind': 'primitive', 'name': 'boolean'},
          generic: false,
          scopes: const [],
          context: 'spec',
        ),
        'bool',
      );
    });

    test('null union members produce nullability on the LUB', () {
      expect(
        mapper.mapType(
          const {
            'kind': 'union',
            'types': [
              _uriRef,
              {'kind': 'primitive', 'name': 'null'},
            ],
          },
          generic: false,
          scopes: const [],
          context: 'spec',
        ),
        'Uri?',
      );
    });

    test('mixed-category unions erase to JSAny, not JSAny?', () {
      expect(
        mapper.mapType(
          const {
            'kind': 'union',
            'types': [_string, _uriRef],
          },
          generic: false,
          scopes: const [],
          context: 'spec',
        ),
        'JSAny',
      );
    });

    test('Thenable references map to JSPromise', () {
      expect(
        mapper.mapType(
          const {
            'kind': 'reference',
            'name': 'Thenable',
            'typeArguments': [_string],
          },
          generic: false,
          scopes: const [],
          context: 'spec',
        ),
        'JSPromise<JSString>',
      );
    });

    test('tuples register their element types on the mapper', () {
      final name = mapper.mapType(
        const {
          'kind': 'tuple',
          'elements': [_string, _number],
        },
        generic: false,
        scopes: const [],
        context: 'spec',
      );
      expect(name, startsWith('JSTuple_'));
      expect(mapper.tupleElements[name], ['JSString', 'JSNumber']);
    });
  });

  group('name mangling', () {
    test('reserved words gain a dollar suffix', () {
      expect(mapper.dartName('with'), r'with$');
    });

    test('leading underscores become public with a dollar prefix', () {
      expect(mapper.dartName('_inner'), r'$_inner');
    });

    test('overload ordinals suffix the member name', () {
      final overloads = mapper.childrenByParent[_boxId]!
          .where((child) => child['name'] == 'open')
          .toList();
      expect(mapper.memberName(overloads.first), 'open');
      expect(mapper.memberName(overloads.last), r'open$2');
    });
  });

  test('substitute rewrites type-parameter references position-correctly', () {
    expect(
      mapper.substitute(
        const {
          'kind': 'array',
          'elementType': {
            'kind': 'reference',
            'name': 'T',
            'typeArguments': <Object?>[],
          },
        },
        const {'T': _string},
      ),
      const {'kind': 'array', 'elementType': _string},
    );
  });

  group('erasure is a call parameter, not mapper state', () {
    const scopedReference = {
      'kind': 'reference',
      'name': 'T',
      'typeArguments': <Object?>[],
    };
    final scopes = [
      {'T'},
    ];

    test('two calls differing only in the erase argument differ', () {
      expect(
        mapper.mapType(
          scopedReference,
          generic: true,
          scopes: scopes,
          context: 'spec',
        ),
        'T',
      );
      expect(
        mapper.mapType(
          scopedReference,
          generic: true,
          scopes: scopes,
          context: 'spec',
          eraseScopeReferences: true,
        ),
        'JSAny?',
      );
    });

    test('an erased call leaves no state behind on the mapper', () {
      expect(
        mapper.mapType(
          scopedReference,
          generic: true,
          scopes: scopes,
          context: 'spec',
          eraseScopeReferences: true,
        ),
        'JSAny?',
      );
      expect(
        mapper.mapType(
          scopedReference,
          generic: true,
          scopes: scopes,
          context: 'spec',
        ),
        'T',
      );
      expect(
        mapper.mapType(
          scopedReference,
          generic: true,
          scopes: scopes,
          context: 'spec',
          // The explicit default is the point: erasure is per-call.
          // ignore: avoid_redundant_argument_values
          eraseScopeReferences: false,
        ),
        'T',
      );
    });
  });

  test('the dart-layer emitter no longer touches parity mutable state', () {
    final source = File(
      'tool/binding_generator/dart_layer.dart',
    ).readAsStringSync();
    expect(
      RegExp(r'eraseScopeReferences\s*=').hasMatch(source),
      isFalse,
      reason:
          'erasure must be threaded as a call parameter; the dart-layer '
          'emitter may not assign (or default) an eraseScopeReferences '
          'variable',
    );
    expect(
      source,
      isNot(contains('parity.eraseScopeReferences')),
      reason: 'the save/restore dance over shared parity state is retired',
    );
  });
}

const Map<String, Object?> _string = {'kind': 'primitive', 'name': 'string'};
const Map<String, Object?> _number = {'kind': 'primitive', 'name': 'number'};
const Map<String, Object?> _uriRef = {
  'kind': 'reference',
  'name': 'Uri',
  'typeArguments': <Object?>[],
};
const _boxId = 'interface:vscode.Box';

Map<String, Object?> _decl(
  String kind,
  String name,
  String parentId, {
  Map<String, Object?> extra = const {},
}) => {
  'id': '$kind:vscode.$name',
  'kind': kind,
  'name': name,
  'qualifiedName': 'vscode.$name',
  'parentId': parentId,
  'visibility': 'public',
  'deprecated': false,
  ...extra,
};

Map<String, Object?> _iface(String name) => _decl(
  'interface',
  name,
  'module:vscode',
  extra: {
    'typeParameters': <Object?>[],
    'extends': <Object?>[],
  },
);

Map<String, Object?> _class(String name) => _decl(
  'class',
  name,
  'module:vscode',
  extra: {
    'typeParameters': <Object?>[],
    'extends': <Object?>[],
    'implements': <Object?>[],
    'abstract': false,
  },
);

Map<String, Object?> _property(String owner, String name, Object? type) =>
    _decl(
      'property',
      name,
      owner,
      extra: {
        'id': 'property:$owner/\$instance/$name',
        'type': type,
        'optional': false,
        'readonly': false,
        'static': false,
        'abstract': false,
      },
    );

Map<String, Object?> _method(
  String owner,
  String name, {
  List<Object?> parameters = const [],
  int overloadOrdinal = 0,
}) => _decl(
  'method',
  name,
  owner,
  extra: {
    'id': 'method:$owner.$name@$overloadOrdinal',
    'parameters': parameters,
    'returnType': const {'kind': 'primitive', 'name': 'void'},
    'typeParameters': <Object?>[],
    'overloadOrdinal': overloadOrdinal,
    'optional': false,
    'static': false,
    'abstract': false,
  },
);

Map<String, Object?> _param(String name, Object? type) => {
  'name': name,
  'type': type,
  'optional': false,
  'rest': false,
};
