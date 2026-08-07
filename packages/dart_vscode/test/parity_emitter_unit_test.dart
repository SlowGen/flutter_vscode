import 'package:test/test.dart';

import '../tool/binding_generator/parity_layer.dart' as parity;

/// Rule-level emitter tests: each case feeds a minimal synthetic IR
/// through the public [parity.emitParityLayer] and asserts emitted (and
/// forbidden) fragments, localizing a broken Total Mapping Rule in a way
/// the byte-compare cannot.
void main() {
  group('Total Mapping Rules on synthetic IRs', () {
    for (final testCase in [
      ..._ruleCases,
      ..._extraRuleCases,
      ..._coverageRuleCases,
    ]) {
      test(testCase.name, () {
        final library = parity.emitParityLayer({
          'schemaVersion': 1,
          'declarations': testCase.declarations,
        }).library;
        for (final fragment in testCase.expects) {
          expect(library, contains(fragment), reason: testCase.name);
        }
        for (final fragment in testCase.forbids) {
          expect(
            library,
            isNot(contains(fragment)),
            reason: '${testCase.name} (forbidden fragment)',
          );
        }
      });
    }
  });

  group('totality throw sites', () {
    for (final testCase in _throwCases) {
      test(testCase.name, () {
        expect(
          () => parity.emitParityLayer({
            'schemaVersion': 1,
            'declarations': testCase.declarations,
          }),
          throwsA(
            isA<parity.ParityGenerationException>().having(
              (error) => error.toString(),
              'message',
              contains(testCase.messageFragment),
            ),
          ),
          reason: testCase.name,
        );
      });
    }
  });
}

final class _RuleCase {
  const _RuleCase(
    this.name,
    this.declarations,
    this.expects, [
    this.forbids = const [],
  ]);
  final String name;
  final List<Map<String, Object?>> declarations;
  final List<String> expects;
  final List<String> forbids;
}

final class _ThrowCase {
  const _ThrowCase(this.name, this.declarations, this.messageFragment);
  final String name;
  final List<Map<String, Object?>> declarations;
  final String messageFragment;
}

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

Map<String, Object?> _iface(
  String name, {
  List<Object?> typeParameters = const [],
}) => _decl(
  'interface',
  name,
  'module:vscode',
  extra: {
    'typeParameters': typeParameters,
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

Map<String, Object?> _property(
  String owner,
  String name,
  Object? type, {
  bool optional = false,
  bool readonly = false,
}) => _decl(
  'property',
  name,
  owner,
  extra: {
    'id': 'property:$owner/\$instance/$name',
    'type': type,
    'optional': optional,
    'readonly': readonly,
    'static': false,
    'abstract': false,
  },
);

Map<String, Object?> _method(
  String owner,
  String name, {
  List<Object?> parameters = const [],
  Object? returnType = const {'kind': 'primitive', 'name': 'void'},
  int overloadOrdinal = 0,
}) => _decl(
  'method',
  name,
  owner,
  extra: {
    'id': 'method:$owner.$name@$overloadOrdinal',
    'parameters': parameters,
    'returnType': returnType,
    'typeParameters': <Object?>[],
    'overloadOrdinal': overloadOrdinal,
    'optional': false,
    'static': false,
    'abstract': false,
  },
);

Map<String, Object?> _param(
  String name,
  Object? type, {
  bool optional = false,
  bool rest = false,
}) => {'name': name, 'type': type, 'optional': optional, 'rest': rest};

const Map<String, Object?> _string = {'kind': 'primitive', 'name': 'string'};
const Map<String, Object?> _number = {'kind': 'primitive', 'name': 'number'};
const Map<String, Object?> _uriRef = {
  'kind': 'reference',
  'name': 'Uri',
  'typeArguments': [],
};

final Map<String, Object?> _uriClass = _class('Uri');
final Map<String, Object?> _boxIface = _iface('Box');
const _boxId = 'interface:vscode.Box';

final List<_RuleCase> _ruleCases = <_RuleCase>[
  _RuleCase(
    'mixed-category unions erase to JSAny, not JSAny? (cc:mixed-union)',
    [
      _uriClass,
      _boxIface,
      _property(_boxId, 'value', {
        'kind': 'union',
        'types': [_string, _uriRef],
      }),
    ],
    ['external JSAny get value;'],
    ['external JSAny? get value;'],
  ),
  _RuleCase(
    'null union members produce nullability on the LUB (cc:mixed-union)',
    [
      _uriClass,
      _boxIface,
      _property(_boxId, 'target', {
        'kind': 'union',
        'types': [
          _uriRef,
          {'kind': 'primitive', 'name': 'null'},
        ],
      }),
    ],
    ['external Uri? get target;'],
  ),
  _RuleCase(
    'overload sets expand with suffixes bound via @JS (cc:overload-set)',
    [
      _boxIface,
      _method(_boxId, 'open', parameters: [_param('a', _string)]),
      _method(
        _boxId,
        'open',
        parameters: [_param('a', _number)],
        overloadOrdinal: 1,
      ),
    ],
    ["@JS('open')", r'open$2(num a);'],
  ),
  _RuleCase(
    'reserved words mangle with a dollar and keep the JS name (cc:reserved-name)',
    [
      _boxIface,
      _property(_boxId, 'with', _string),
    ],
    ["@JS('with')", r'get with$;'],
  ),
  _RuleCase(
    'leading-underscore names become public with a dollar prefix (cc:underscore-name)',
    [
      _boxIface,
      _property(_boxId, '_inner', _string),
    ],
    ["@JS('_inner')", r'get $_inner;'],
  ),
  _RuleCase(
    'numeric enums typedef to int with module-rooted values (cc:numeric-enum)',
    [
      _decl('enum', 'Kind', 'module:vscode', extra: {'constant': false}),
      _decl(
        'enumMember',
        'Alpha',
        'enum:vscode.Kind',
        extra: {
          'id': 'enumMember:enum:vscode.Kind/Alpha',
          'initializer': {'kind': 'literal', 'value': 1},
        },
      ),
    ],
    [
      'typedef Kind = int;',
      'extension type KindValues(JSObject _self)',
      'external int get Alpha;',
      'external KindValues get Kind;',
    ],
  ),
  _RuleCase(
    'readonly properties emit no setter (cc:readonly-property)',
    [
      _boxIface,
      _property(_boxId, 'uri', _uriRef, readonly: true),
      _uriClass,
    ],
    ['external Uri get uri;'],
    ['set uri('],
  ),
  _RuleCase(
    'optional properties and parameters are nullable (cc:optional-member)',
    [
      _boxIface,
      _property(_boxId, 'label', _string, optional: true),
      _method(
        _boxId,
        'find',
        parameters: [
          _param('query', _string),
          _param('limit', _number, optional: true),
        ],
      ),
    ],
    ['external String? get label;', '[num? limit]'],
  ),
  _RuleCase(
    'rest parameters route through callMethodVarArgs (cc:rest-parameter)',
    [
      _boxIface,
      _method(
        _boxId,
        'push',
        parameters: [
          _param('first', _string),
          _param('rest', {'kind': 'array', 'elementType': _string}, rest: true),
        ],
      ),
    ],
    ['callMethodVarArgs', 'List<JSAny?>'],
  ),
  _RuleCase(
    'Promise and Thenable references map to JSPromise (cc:promise-thenable)',
    [
      _boxIface,
      _method(
        _boxId,
        'load',
        returnType: {
          'kind': 'reference',
          'name': 'Thenable',
          'typeArguments': [_string],
        },
      ),
    ],
    ['JSPromise<JSString> load();'],
  ),
  _RuleCase(
    'arrays carry generic-form element types (cc:array)',
    [
      _boxIface,
      _property(_boxId, 'names', {'kind': 'array', 'elementType': _string}),
    ],
    ['external JSArray<JSString> get names;'],
  ),
  _RuleCase(
    'declared constructors and ctor-less classes both construct (cc:declared-constructor cc:default-constructor)',
    [
      _class('Point'),
      _decl(
        'constructor',
        'constructor',
        'class:vscode.Point',
        extra: {
          'id': 'constructor:vscode.Point.constructor@0',
          'parameters': [_param('x', _number)],
          'returnType': {
            'kind': 'reference',
            'name': 'Point',
            'typeArguments': <Object?>[],
          },
          'typeParameters': <Object?>[],
          'overloadOrdinal': 0,
        },
      ),
      _class('Bag'),
    ],
    [
      r'Point new$(JSNumber x)',
      r'Bag new$() =>',
      'callAsConstructorVarArgs',
    ],
  ),
  _RuleCase(
    r'interfaces gain object-literal lit$ factories (cc:object-literal-factory)',
    [
      _boxIface,
      _property(_boxId, 'language', _string, optional: true),
    ],
    [r'external factory Box.lit$({JSString? language});'],
  ),
  _RuleCase(
    'index signatures use the blessed operators (cc:index-signature)',
    [
      _boxIface,
      _decl(
        'indexSignature',
        r'$index',
        _boxId,
        extra: {
          'id': 'indexSignature:$_boxId.\$index@0',
          'parameters': [_param('key', _string)],
          'returnType': _string,
          'typeParameters': <Object?>[],
          'overloadOrdinal': 0,
          'readonly': false,
          'canonicalSignature': '{}',
        },
      ),
    ],
    ['operator [](String key);', 'operator []=(String key'],
  ),
  // V-1: derived stable typedefs for registered type literals.
  _RuleCase(
    'registered literals get derived stable typedefs (cc:stable-typedef)',
    [
      _class('Position'),
      _method(
        'class:vscode.Position',
        'with',
        parameters: [
          _param('change', {
            'kind': 'typeLiteral',
            'id': r'typeLiteral:method:vscode.Position.with@0/$shape@aaaa',
            'shapeHash': 'a' * 64,
          }),
        ],
      ),
      _decl(
        'typeLiteral',
        r'$type',
        'method:class:vscode.Position.with@0',
        extra: {
          'id': r'typeLiteral:method:vscode.Position.with@0/$shape@aaaa',
          'shapeHash': 'a' * 64,
          'shape': {
            'members': [
              {
                'kind': 'property',
                'name': 'line',
                'optional': true,
                'readonly': false,
                'type': _number,
              },
            ],
          },
        },
      ),
      _property(
        r'typeLiteral:method:vscode.Position.with@0/$shape@aaaa',
        'line',
        _number,
        optional: true,
      ),
    ],
    [r'typedef PositionWith$1 = JSAnon_'],
  ),
  // V-2: module-rooted narrowing on every Ctor type.
  _RuleCase(
    'class objects narrow with isInstance and cast (cc:narrowing)',
    [_class('Uri')],
    [
      'bool isInstance(JSAny? value)',
      'Uri cast(JSAny? value)',
      'isPrototypeOf',
    ],
  ),
  // V-2: string-literal unions become zero-cost typed wrappers.
  _RuleCase(
    'string-literal unions emit typed wrappers (cc:string-literal-union)',
    [
      _boxIface,
      _property(_boxId, 'align', {
        'kind': 'union',
        'types': [
          {'kind': 'literal', 'value': 'left'},
          {'kind': 'literal', 'value': 'right'},
        ],
      }),
    ],
    [
      'extension type const JSLit_',
      'static const left',
      'static const right',
    ],
  ),
];

final List<_RuleCase> _extraRuleCases = <_RuleCase>[
  _RuleCase(
    'intersection types implement both operands (cc:intersection)',
    [
      _iface('Left'),
      _iface('Right'),
      _iface('Holder'),
      _property('interface:vscode.Holder', 'both', {
        'kind': 'intersection',
        'types': [
          {'kind': 'reference', 'name': 'Left', 'typeArguments': <Object?>[]},
          {'kind': 'reference', 'name': 'Right', 'typeArguments': <Object?>[]},
        ],
      }),
    ],
    ['extension type JSIntersection_', 'implements Left, Right, JSObject'],
  ),
  _RuleCase(
    'call-signature interfaces wrap JSFunction (cc:call-signature)',
    [
      _iface('Listener'),
      _decl(
        'callSignature',
        r'$call',
        'interface:vscode.Listener',
        extra: {
          'id': r'callSignature:interface:vscode.Listener.$call@0',
          'parameters': [_param('value', _string)],
          'returnType': const {'kind': 'primitive', 'name': 'void'},
          'typeParameters': <Object?>[],
          'overloadOrdinal': 0,
          'canonicalSignature': '{}',
        },
      ),
    ],
    ['extension type Listener(JSFunction _self)', 'call('],
  ),
  _RuleCase(
    'mutable properties emit external setters (cc:external-setter)',
    [
      _iface('Holder'),
      _property('interface:vscode.Holder', 'value', _string),
    ],
    ['external String get value;', 'external set value(String value);'],
  ),
];

final List<_RuleCase> _coverageRuleCases = <_RuleCase>[
  _RuleCase(
    'tuples become typed accessors over JSArray (cc:tuple)',
    [
      _iface('Holder'),
      _property('interface:vscode.Holder', 'pair', {
        'kind': 'tuple',
        'elements': [_string, _number],
      }),
    ],
    ['extension type JSTuple_', r'$1', r'$2'],
  ),
  _RuleCase(
    'registered type literals emit typed extension types (cc:type-literal)',
    [
      _iface('Holder'),
      _property('interface:vscode.Holder', 'options', {
        'kind': 'typeLiteral',
        'id': r'typeLiteral:interface:vscode.Holder/$shape@cccc',
        'shapeHash': 'c' * 64,
      }),
      _decl(
        'typeLiteral',
        r'$type',
        'interface:vscode.Holder',
        extra: {
          'id': r'typeLiteral:interface:vscode.Holder/$shape@cccc',
          'shapeHash': 'c' * 64,
          'shape': {
            'members': [
              {
                'kind': 'property',
                'name': 'flag',
                'optional': true,
                'readonly': false,
                'type': {'kind': 'primitive', 'name': 'boolean'},
              },
            ],
          },
        },
      ),
      _property(
        r'typeLiteral:interface:vscode.Holder/$shape@cccc',
        'flag',
        const {'kind': 'primitive', 'name': 'boolean'},
        optional: true,
      ),
    ],
    ['extension type JSAnon_', 'external bool? get flag;'],
  ),
  _RuleCase(
    'function types erase to JSFunction (cc:function-type)',
    [
      _iface('Holder'),
      _property('interface:vscode.Holder', 'onDone', {
        'kind': 'function',
        'typeParameters': <Object?>[],
        'parameters': <Object?>[],
        'returnType': {'kind': 'primitive', 'name': 'void'},
        'canonicalSignature': '{}',
      }),
    ],
    ['external JSFunction get onDone;'],
  ),
];

final List<_ThrowCase> _throwCases = <_ThrowCase>[
  _ThrowCase(
    'unknown declaration kinds fail',
    [_decl('mystery', 'X', 'module:vscode')],
    'declaration kind mystery',
  ),
  _ThrowCase(
    'unknown type kinds fail',
    [
      _boxIface,
      _property(_boxId, 'x', {'kind': 'conditional'}),
    ],
    'type kind conditional',
  ),
  _ThrowCase(
    'unknown primitives fail',
    [
      _boxIface,
      _property(_boxId, 'x', {'kind': 'primitive', 'name': 'quux'}),
    ],
    'primitive quux',
  ),
  _ThrowCase(
    'unknown references fail',
    [
      _boxIface,
      _property(
        _boxId,
        'x',
        {'kind': 'reference', 'name': 'Nope', 'typeArguments': <Object?>[]},
      ),
    ],
    'reference Nope',
  ),
  _ThrowCase(
    'dotted references to non-enums fail',
    [
      _boxIface,
      _property(_boxId, 'x', {
        'kind': 'reference',
        'name': 'Foo.Bar',
        'typeArguments': <Object?>[],
      }),
    ],
    'dotted reference Foo.Bar',
  ),
  _ThrowCase(
    'unregistered literal references fail',
    [
      _boxIface,
      _property(_boxId, 'x', {
        'kind': 'typeLiteral',
        'id': 'typeLiteral:ghost',
        'shapeHash': 'b' * 64,
      }),
    ],
    'unregistered type literal',
  ),
  _ThrowCase(
    'unsupported type operators fail',
    [
      _boxIface,
      _property(_boxId, 'x', {
        'kind': 'operator',
        'operator': 'keyof',
        'type': _string,
      }),
    ],
    'type operator keyof',
  ),
  _ThrowCase(
    'unsupported namespace member kinds fail',
    [
      _decl('namespace', 'zone', 'module:vscode'),
      _decl(
        'enum',
        'Nested',
        'namespace:vscode.zone',
        extra: {'constant': false},
      ),
    ],
    'namespace member kind enum',
  ),
];
