import 'dart:convert';

import 'package:test/test.dart';

import '../tool/binding_generator/dart_layer.dart' as dart_layer;
import '../tool/binding_generator/parity_layer.dart' as parity;

/// Rule-level emitter tests for the mechanical Dart-ergonomics layer
/// (developer-experience D-2): each case feeds a minimal synthetic IR
/// through the public [dart_layer.emitDartLayer] and asserts emitted (and
/// forbidden) fragments, localizing a broken dart-layer rule in a way the
/// byte-compare cannot. The alias-named-wrapper rule lands in the parity
/// emitter itself and is asserted through [parity.emitParityLayer].
void main() {
  group('dart-layer rules on synthetic IRs', () {
    for (final testCase in _ruleCases) {
      test(testCase.name, () {
        final library = dart_layer.emitDartLayer({
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

  group('alias-named literal wrappers in the parity emitter', () {
    for (final testCase in _parityRuleCases) {
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

  group('totality accounting (dc:totality-accounting)', () {
    test('every declaration receives a dart-layer disposition', () {
      final declarations = [
        _boxIface,
        _property(_boxId, 'title', _string),
        _method(
          _boxId,
          'load',
          returnType: _thenableOf(_string),
        ),
        _decl(
          'interface',
          'Hidden',
          'module:vscode',
          extra: {
            'visibility': 'private',
            'typeParameters': <Object?>[],
            'extends': <Object?>[],
          },
        ),
      ];
      final ledger =
          jsonDecode(
                dart_layer.emitDartLayer({
                  'schemaVersion': 1,
                  'declarations': declarations,
                }).ledger,
              )
              as Map<String, Object?>;
      final dispositions = (ledger['dispositions']! as Map<Object?, Object?>)
          .cast<String, String>();
      expect(dispositions.length, declarations.length);
      expect(dispositions['interface:vscode.Box'], 'emitted');
      expect(
        dispositions[r'property:interface:vscode.Box/$instance/title'],
        'passthrough-identical',
      );
      expect(
        dispositions['method:interface:vscode.Box.load@0'],
        'emitted',
      );
      expect(dispositions['interface:vscode.Hidden'], 'parity:non-public');
    });

    test(
      'a stream construct without a subscribable Event fails generation',
      () {
        // The Event interface exists but declares no call signature: the
        // stream rule has nothing to subscribe through and must fail with
        // the consuming declaration id rather than emit broken code.
        expect(
          () => dart_layer.emitDartLayer({
            'schemaVersion': 1,
            'declarations': [
              _eventIfaceWithoutCall(),
              _boxIface,
              _property(
                _boxId,
                'onDidThing',
                _eventOf(_string),
                readonly: true,
              ),
            ],
          }),
          throwsA(
            isA<dart_layer.DartLayerGenerationException>()
                .having(
                  (error) => error.declarationId,
                  'declarationId',
                  r'property:interface:vscode.Box/$instance/onDidThing',
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('call signature'),
                ),
          ),
        );
      },
    );

    test('parity-stage totality failures still carry the declaration id', () {
      expect(
        () => dart_layer.emitDartLayer({
          'schemaVersion': 1,
          'declarations': [
            _boxIface,
            _property(_boxId, 'broken', {'kind': 'conditional'}),
          ],
        }),
        throwsA(isA<parity.ParityGenerationException>()),
      );
    });
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
  List<Object?> extends$ = const [],
}) => _decl(
  'interface',
  name,
  'module:vscode',
  extra: {
    'typeParameters': typeParameters,
    'extends': extends$,
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

Map<String, Object?> _thenableOf(Object? argument) => {
  'kind': 'reference',
  'name': 'Thenable',
  'typeArguments': [argument],
};

Map<String, Object?> _eventOf(Object? argument) => {
  'kind': 'reference',
  'name': 'Event',
  'typeArguments': [argument],
};

Map<String, Object?> _eventIfaceWithoutCall() => _decl(
  'interface',
  'Event',
  'module:vscode',
  extra: {
    'typeParameters': [
      {'name': 'T'},
    ],
    'extends': <Object?>[],
  },
);

List<Map<String, Object?>> _eventSupport() => [
  _eventIfaceWithoutCall(),
  _decl(
    'callSignature',
    r'$call',
    'interface:vscode.Event',
    extra: {
      'id': r'callSignature:interface:vscode.Event.$call@0',
      'parameters': [
        _param('listener', {
          'kind': 'function',
          'typeParameters': <Object?>[],
          'parameters': <Object?>[],
          'returnType': {'kind': 'primitive', 'name': 'any'},
          'canonicalSignature': '{}',
        }),
      ],
      'returnType': {
        'kind': 'reference',
        'name': 'Disposable',
        'typeArguments': <Object?>[],
      },
      'typeParameters': <Object?>[],
      'overloadOrdinal': 0,
      'canonicalSignature': '{}',
    },
  ),
  _class('Disposable'),
  _method('class:vscode.Disposable', 'dispose'),
];

const Map<String, Object?> _string = {'kind': 'primitive', 'name': 'string'};
const Map<String, Object?> _number = {'kind': 'primitive', 'name': 'number'};
const Map<String, Object?> _boolean = {'kind': 'primitive', 'name': 'boolean'};
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
    'constructor helpers de-JS scalar parameters (dc:boundary-de-js)',
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
    ],
    [
      r'extension type PointCtorDart(PointCtor $js) implements PointCtor {',
      r'Point new$(num x) => $js.new$(x.toJS);',
      'extension PointCtorToDart on PointCtor {',
      'PointCtorDart get dart => PointCtorDart(this);',
    ],
    [r'Point new$(JSNumber x) => '],
  ),
  _RuleCase(
    'rest helpers de-JS scalar parameters (dc:boundary-de-js)',
    [
      _boxIface,
      _method(
        _boxId,
        'push',
        parameters: [
          _param('first', _string),
          _param(
            'rest',
            {'kind': 'array', 'elementType': _string},
            rest: true,
          ),
        ],
      ),
    ],
    [
      r'JSAny? push(String first, [List<JSAny?> rest = const []]) => $js.push(first.toJS, rest);',
    ],
  ),
  _RuleCase(
    r'dart-layer lit$ factories de-JS scalar parameters (dc:boundary-de-js)',
    [
      _boxIface,
      _property(_boxId, 'language', _string, optional: true),
    ],
    [
      r'factory BoxDart.lit$({String? language}) {',
      r'final object$ = JSObject();',
      r"object$.setProperty('language'.toJS, language.toJS);",
      r'return BoxDart(Box(object$));',
    ],
    [r'factory BoxDart.lit$({JSString? language})'],
  ),
  _RuleCase(
    'tuple accessors de-JS scalar elements (dc:boundary-de-js)',
    [
      _boxIface,
      _property(_boxId, 'pair', {
        'kind': 'tuple',
        'elements': [_string, _number],
      }),
    ],
    [
      r'String get $1 => $js.$1.toDart;',
      r'num get $2 => $js.$2.toDartDouble;',
      'Dart get dart => ',
    ],
  ),
  _RuleCase(
    'promise returns become futures with de-JSed values (dc:future-from-promise)',
    [
      _boxIface,
      _method(
        _boxId,
        'load',
        returnType: _thenableOf({
          'kind': 'union',
          'types': [
            _string,
            {'kind': 'primitive', 'name': 'undefined'},
          ],
        }),
      ),
    ],
    [
      r'Future<String?> load() => $js.load().toDart.then((value) => value?.toDart);',
    ],
  ),
  _RuleCase(
    'promise conversions preserve trailing-optional trimming (dc:future-from-promise)',
    [
      _boxIface,
      _method(
        _boxId,
        'find',
        parameters: [
          _param('query', _string),
          _param('limit', _number, optional: true),
        ],
        returnType: _thenableOf(_boolean),
      ),
    ],
    [
      r'Future<bool> find(String query, [num? limit]) => (limit != null ? $js.find(query, limit) : $js.find(query)).toDart.then((value) => value.toDart);',
    ],
  ),
  _RuleCase(
    'non-scalar promise arguments pass through unchanged (dc:future-from-promise)',
    [
      _uriClass,
      _boxIface,
      _method(_boxId, 'locate', returnType: _thenableOf(_uriRef)),
    ],
    [r'Future<Uri> locate() => $js.locate().toDart;'],
    [r'Future<Uri> locate() => $js.locate().toDart.then'],
  ),
  _RuleCase(
    'event properties gain broadcast stream accessors (dc:stream-from-event)',
    [
      ..._eventSupport(),
      _boxIface,
      _property(_boxId, 'onDidThing', _eventOf(_string), readonly: true),
    ],
    [
      r'Stream<String> get onDidThingStream => _eventStream$(',
      r'(listener) => $js.onDidThing.call(listener),',
      '(raw) => (raw! as JSString).toDart,',
      r'Stream<S> _eventStream$<S>(',
      'StreamController<S>.broadcast(',
      "callMethod('dispose'.toJS)",
    ],
  ),
  _RuleCase(
    'optional event properties gain nullable stream accessors (dc:stream-from-event)',
    [
      ..._eventSupport(),
      _uriClass,
      _boxIface,
      _property(_boxId, 'onMaybe', _eventOf(_uriRef), optional: true),
    ],
    [
      'Stream<Uri>? get onMaybeStream {',
      r'final event$ = $js.onMaybe;',
      r'if (event$ == null) return null;',
      '(raw) => raw as Uri,',
    ],
  ),
  _RuleCase(
    r'dart-layer lit$ factories flatten inherited interface members (dc:flattened-literal-factory)',
    [
      _iface('Base'),
      _property(
        'interface:vscode.Base',
        'backgroundColor',
        _string,
        optional: true,
      ),
      _iface(
        'Derived',
        extends$: [
          {
            'kind': 'reference',
            'name': 'Base',
            'typeArguments': <Object?>[],
          },
        ],
      ),
      _property(
        'interface:vscode.Derived',
        'isWholeLine',
        _boolean,
        optional: true,
      ),
    ],
    [
      r'factory DerivedDart.lit$({bool? isWholeLine, String? backgroundColor}) {',
      r"object$.setProperty('backgroundColor'.toJS, backgroundColor.toJS);",
    ],
  ),
  _RuleCase(
    r'dart-layer lit$ factories flatten members of extended classes (dc:flattened-literal-factory)',
    [
      _class('Disposable'),
      _method('class:vscode.Disposable', 'dispose'),
      _iface(
        'Watcher',
        extends$: [
          {
            'kind': 'reference',
            'name': 'Disposable',
            'typeArguments': <Object?>[],
          },
        ],
      ),
    ],
    [
      r'factory WatcherDart.lit$({JSFunction? dispose}) {',
      r"object$.setProperty('dispose'.toJS, dispose);",
    ],
  ),
  _RuleCase(
    'namespaces and the module root re-root onto the dart layer (dc:future-from-promise)',
    [
      _decl('namespace', 'zone', 'module:vscode'),
      _decl(
        'function',
        'fetch',
        'namespace:vscode.zone',
        extra: {
          'id': 'function:vscode.zone.fetch@0',
          'parameters': <Object?>[],
          'returnType': _thenableOf(_string),
          'typeParameters': <Object?>[],
          'overloadOrdinal': 0,
        },
      ),
    ],
    [
      r'extension type ZoneNsDart(ZoneNs $js) implements ZoneNs {',
      r'Future<String> fetch() => $js.fetch().toDart.then((value) => value.toDart);',
      r'ZoneNsDart get zone => ZoneNsDart($js.zone);',
      'extension VscodeApiToDart on VscodeApi {',
      'VscodeApiDart get dart => VscodeApiDart(this);',
    ],
  ),
];

final List<_RuleCase> _parityRuleCases = <_RuleCase>[
  _RuleCase(
    'an all-string-literal alias names its wrapper after the alias (dc:alias-named-wrapper)',
    [
      _decl(
        'typeAlias',
        'Align',
        'module:vscode',
        extra: {
          'typeParameters': <Object?>[],
          'type': {
            'kind': 'union',
            'types': [
              {'kind': 'literal', 'value': 'left'},
              {'kind': 'literal', 'value': 'right'},
            ],
          },
        },
      ),
      _boxIface,
      _property(
        _boxId,
        'align',
        {'kind': 'reference', 'name': 'Align', 'typeArguments': <Object?>[]},
      ),
    ],
    [
      'extension type const Align(String value) {',
      "static const left = Align('left');",
      "static const right = Align('right');",
      'external Align get align;',
    ],
    [
      'typedef Align = JSString;',
      'JSLit_',
    ],
  ),
];
