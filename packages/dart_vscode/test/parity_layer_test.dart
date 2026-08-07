import 'dart:io';

import 'package:test/test.dart';

import '../tool/binding_generator/parity_layer.dart' as parity;
import 'support/json.dart';
import 'support/repository.dart';

const _ledgerPath = 'tool/bindings/parity-ledger.json';

/// Returns the source of exactly one `extension type <name><...>(` block.
String _typeBlock(String source, String name) {
  final start = source.indexOf(RegExp('extension type $name[<(]'));
  if (start < 0) {
    fail('extension type $name not found');
  }
  final open = source.indexOf('{', start);
  var depth = 0;
  for (var index = open; index < source.length; index += 1) {
    if (source[index] == '{') depth += 1;
    if (source[index] == '}') {
      depth -= 1;
      if (depth == 0) {
        return source.substring(start, index + 1);
      }
    }
  }
  fail('unterminated block for $name');
}

void main() {
  final inventory = readJsonObject('tool/bindings/ir/vscode-1.129.1.json');

  test('P-1 checked-in substrate ledger matches mechanical regeneration', () {
    // The standalone parity artifact retired into the self-contained
    // dart-layer artifact (SL-1); the substrate emission survives
    // in-memory and its totality ledger stays checked in.
    final artifacts = parity.emitParityLayer(inventory);
    expect(
      File(_ledgerPath).readAsStringSync(),
      artifacts.ledger,
      reason:
          'Regenerate with: dart tool/binding_generator/generate.dart '
          '--dart-layer .',
    );
  });

  test('P-2 every public declaration is emitted or explicitly erased', () {
    final ledger = readJsonObject(_ledgerPath);
    final dispositions = (ledger['dispositions']! as Map<Object?, Object?>)
        .cast<String, String>();
    const allowedErasures = {
      'emitted',
      'symbol-keyed-member',
      'thenable-as-jspromise',
      'non-public',
    };
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final missing = <String>[];
    for (final declaration in declarations) {
      final id = declaration['id']! as String;
      final disposition = dispositions[id];
      if (disposition == null) {
        missing.add(id);
      } else {
        expect(allowedErasures, contains(disposition), reason: id);
        if (declaration['visibility'] != 'public') {
          expect(disposition, 'non-public', reason: id);
        }
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'declarations with no recorded disposition',
    );
    expect(
      dispositions.length,
      declarations.length,
      reason: 'ledger must cover exactly the IR',
    );
  });

  // P-3 (artifact byte-compare and analyze) retired with the standalone
  // artifact: the substrate now ships inside vscode_dart_layer.g.dart,
  // whose byte-compare and analyze gates live in test/dart_layer_test.dart
  // (D-1/D-3, frozen).

  group('P-4 structural rules on the real substrate emission', () {
    late final String source;
    setUpAll(() {
      source = parity.emitParityLayer(inventory).library;
    });

    test('reserved words are mangled and JS-bound', () {
      expect(source, contains("@JS('with')"));
      expect(source, contains(r'with$'));
      expect(source, contains("@JS('toString')"));
      expect(source, contains(r'toString$'));
    });

    test('overload sets expand with deterministic suffixes', () {
      expect(source, contains("@JS('showQuickPick')"));
      expect(source, matches(RegExp(r'showQuickPick\$2')));
    });

    test('numeric enums are int typedefs with module-rooted values', () {
      expect(source, contains('typedef ViewColumn = int;'));
      expect(source, matches(RegExp(r'external\s+int\s+get\s+File;')));
    });

    test('Thenable maps to JSPromise', () {
      expect(
        source,
        contains('typedef Thenable<T extends JSAny?> = JSPromise<T>;'),
      );
    });

    test('tuples get typed accessors over JSArray', () {
      expect(source, contains('typedef CharacterPair = JSTuple_'));
      expect(
        source,
        matches(RegExp(r'JSTuple_\w+\(JSArray<JSAny\?> _self\)')),
      );
    });

    test('index signatures use the only blessed operators', () {
      expect(source, contains('external JSAny? operator []('));
    });

    test('intersections implement both operands', () {
      expect(
        source,
        matches(
          RegExp(
            r'extension type JSIntersection_\w+[^{]*implements[^{]*Memento',
          ),
        ),
      );
    });

    test('the module wrapper is the only root', () {
      expect(source, contains('extension type VscodeApi'));
      expect(source, matches(RegExp(r'external\s+WindowNs\s+get\s+window;')));
      expect(source, isNot(contains('globalThis')));
      expect(source, isNot(contains("@JS('vscode')")));
    });

    test('constructors go through the module class object', () {
      expect(source, matches(RegExp(r'Position\s+new\$\(')));
      expect(source, contains('callAsConstructorVarArgs'));
    });

    test('call-signature interfaces wrap JSFunction', () {
      expect(
        source,
        matches(
          RegExp(r'extension type Event<T extends JSAny\?>[^{]*JSFunction'),
        ),
      );
    });

    test('LUB union erasure holds at external boundaries', () {
      expect(source, contains('typedef DocumentSelector = JSAny;'));
      expect(source, contains('typedef Declaration = JSObject;'));
      expect(source, contains('typedef GlobPattern = JSAny;'));
    });

    test('registered type literals are extension types with typed members', () {
      expect(source, matches(RegExp(r'extension type JSAnon_\w+\(JSObject')));
      expect(
        'extension type JSAnon_'.allMatches(source).length,
        greaterThan(50),
      );
    });

    test('ctor-less classes still construct through the class object', () {
      final block = _typeBlock(source, 'EventEmitterCtor');
      expect(block, contains(r'new$'));
      final workspaceEdit = _typeBlock(source, 'WorkspaceEditCtor');
      expect(workspaceEdit, contains(r'new$'));
    });

    test('interfaces and type literals get object-literal factories', () {
      final documentFilter = _typeBlock(source, 'DocumentFilter');
      expect(
        documentFilter,
        contains(r'external factory DocumentFilter.lit$('),
      );
      expect(documentFilter, contains('String? language'));
      expect(source, matches(RegExp(r'external factory JSAnon_\w+\.lit\$\(')));
    });

    test('index signatures include the setter operator', () {
      expect(source, contains('external void operator []=('));
    });

    test('Promise and Thenable references map to JSPromise in signatures', () {
      expect(source, matches(RegExp('external JSPromise<[^>]+> ')));
    });

    test('overload suffixes sit directly on their JS binding', () {
      expect(
        source,
        matches(
          RegExp(r"@JS\('showQuickPick'\)\n  external [^\n]+showQuickPick\$2"),
        ),
      );
    });

    test('enum value objects are module-rooted on VscodeApi', () {
      final api = _typeBlock(source, 'VscodeApi');
      expect(api, contains('FileTypeValues get FileType;'));
      expect(api, contains('ViewColumnValues get ViewColumn;'));
    });

    test('optionality is nullable, readonly is getter-only', () {
      // The only mention of undefined is the documented conflation note.
      expect('undefined'.allMatches(source).length, 1);
      expect(source, contains('external String? get placeHolder;'));
      final document = _typeBlock(source, 'TextDocument');
      expect(document, contains('external Uri get uri;'));
      expect(
        document,
        isNot(contains('external set uri(')),
        reason: 'readonly properties must not emit setters',
      );
      final selectionGetter = RegExp(
        r'external\s+Selection\s+get\s+selection;',
      );
      expect(source, matches(selectionGetter));
    });
  });

  test('C-3 every non-exempt construct class has a tagged live probe', () {
    final harness = File(
      '../flutter_vscode/test/fixtures/host_extension/test/run.cjs',
    ).readAsStringSync();
    final unitSuite = File(
      'test/parity_emitter_unit_test.dart',
    ).readAsStringSync();
    for (final constructClass in parity.parityConstructClasses) {
      expect(
        unitSuite,
        anyOf(contains("'$constructClass'"), contains('cc:$constructClass')),
        reason: 'construct class $constructClass needs an emitter unit case',
      );
      if (parity.parityLiveExemptions.containsKey(constructClass)) {
        continue;
      }
      expect(
        harness,
        contains('cc:$constructClass'),
        reason:
            'construct class $constructClass needs a tagged live probe '
            'in the real-host smoke',
      );
    }
    for (final exemption in parity.parityLiveExemptions.values) {
      expect(exemption, isNotEmpty);
    }
  });

  test('V-4 the live smoke covers every API namespace family', () {
    final namespaces = [
      for (final declaration
          in (inventory['declarations']! as List<Object?>)
              .cast<Map<Object?, Object?>>())
        if (declaration['kind'] == 'namespace') declaration['name']! as String,
    ];
    expect(namespaces, isNotEmpty);
    final harness = File(
      '../flutter_vscode/test/fixtures/host_extension/test/run.cjs',
    ).readAsStringSync();
    for (final namespace in namespaces) {
      expect(
        harness,
        contains("'$namespace'"),
        reason:
            'the real-host smoke must exercise a representative of '
            'the $namespace family',
      );
    }
  });

  test(
    'C-4 the parity report states machine-derived two-axis live coverage',
    () {
      final report = File(
        repoPath('docs/reference/parity.md'),
      ).readAsStringSync();
      expect(
        report,
        contains('two axes'),
        reason: 'the report must define live coverage on both axes',
      );
      final namespaces = [
        for (final declaration
            in (inventory['declarations']! as List<Object?>)
                .cast<Map<Object?, Object?>>())
          if (declaration['kind'] == 'namespace')
            declaration['name']! as String,
      ];
      for (final namespace in namespaces) {
        expect(
          report,
          contains('`$namespace`'),
          reason:
              'the family axis must list the $namespace family, '
              'derived from the IR',
        );
      }
      for (final constructClass in parity.parityConstructClasses) {
        expect(
          report,
          contains('`$constructClass`'),
          reason:
              'the construct-class axis must list $constructClass, '
              'derived from the emitter constant',
        );
      }
      for (final reason in parity.parityLiveExemptions.values) {
        expect(
          report,
          contains(reason),
          reason: 'every live exemption must carry its recorded reason',
        );
      }
    },
  );

  test('P-5 unmapped constructs fail generation with an actionable error', () {
    final synthetic = <String, Object?>{
      'schemaVersion': 1,
      'declarations': [
        {
          'id': 'typeAlias:vscode.Broken',
          'kind': 'typeAlias',
          'name': 'Broken',
          'qualifiedName': 'vscode.Broken',
          'parentId': 'module:vscode',
          'deprecated': false,
          'visibility': 'public',
          'typeParameters': <Object?>[],
          'type': {'kind': 'conditional'},
        },
      ],
    };
    expect(
      () => parity.emitParityLayer(synthetic),
      throwsA(
        isA<parity.ParityGenerationException>()
            .having((e) => e.declarationId, 'id', 'typeAlias:vscode.Broken')
            .having((e) => e.message, 'message', contains('conditional')),
      ),
    );
  });
}
