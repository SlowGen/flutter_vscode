import 'dart:io';

import 'package:test/test.dart';

import '../tool/binding_generator/dart_layer.dart' as dart_layer;
import '../tool/binding_generator/sdk_format.dart';
import 'support/json.dart';
import 'support/repository.dart';

final String _libraryPath = repoPath(
  'packages/dart_vscode/lib/src/generated/vscode_dart_layer.g.dart',
);
const _ledgerPath = 'tool/bindings/dart-layer-ledger.json';
const _parityLedgerPath = 'tool/bindings/parity-ledger.json';

void main() {
  test('the generated layer is formatter-canonical', () async {
    // A wholesale `dart format lib` must be a no-op on the generated
    // artifact, and a regeneration must reproduce receipted bytes either
    // way: the emitter formats its output through the pinned dart_style,
    // so canonical-by-construction is the invariant and any SDK/dart_style
    // divergence surfaces here as a red test, not a receipts incident.
    final result = await Process.run('dart', [
      'format',
      '--output=none',
      '--set-exit-if-changed',
      _libraryPath,
    ]);
    expect(
      result.exitCode,
      0,
      reason:
          'the committed generated layer must already be formatted:\n'
          '${result.stdout}\n${result.stderr}',
    );
  });

  final inventory = readJsonObject('tool/bindings/ir/vscode-1.129.1.json');

  test('D-1 checked-in dart layer matches mechanical regeneration', () async {
    final artifacts = dart_layer.emitDartLayer(inventory);
    expect(
      File(_libraryPath).readAsStringSync(),
      await formatWithSdk(artifacts.library),
      reason:
          'Regenerate with: dart tool/binding_generator/generate.dart '
          '--dart-layer .',
    );
    expect(File(_ledgerPath).readAsStringSync(), artifacts.ledger);
    expect(
      File(
        repoPath('packages/dart_vscode/lib/dart_vscode.dart'),
      ).readAsStringSync(),
      contains('src/generated/vscode_dart_layer.g.dart'),
      reason: 'the layer must be exported for Extension Authors',
    );
  });

  test('D-2 every parity declaration receives a dart-layer disposition', () {
    final ledger = readJsonObject(_ledgerPath);
    final dispositions = (ledger['dispositions']! as Map<Object?, Object?>)
        .cast<String, String>();
    final parityDispositions =
        (readJsonObject(_parityLedgerPath)['dispositions']!
                as Map<Object?, Object?>)
            .cast<String, String>();
    const allowed = {
      'emitted',
      'passthrough-identical',
      'parity:non-public',
      'parity:symbol-keyed-member',
      'parity:thenable-as-jspromise',
    };
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final missing = <String>[];
    for (final declaration in declarations) {
      final id = declaration['id']! as String;
      final disposition = dispositions[id];
      if (disposition == null) {
        missing.add(id);
        continue;
      }
      expect(allowed, contains(disposition), reason: id);
      final parityDisposition = parityDispositions[id]!;
      if (parityDisposition != 'emitted') {
        expect(
          disposition,
          'parity:$parityDisposition',
          reason: 'a parity erasure must carry through verbatim for $id',
        );
      }
    }
    expect(
      missing,
      isEmpty,
      reason: 'declarations with no recorded dart-layer disposition',
    );
    expect(
      dispositions.length,
      declarations.length,
      reason: 'ledger must cover exactly the IR',
    );
  });

  test('D-3 the generated dart layer analyzes cleanly', () {
    final result = Process.runSync(
      'dart',
      ['analyze', '--fatal-infos', _libraryPath],
    );
    expect(
      result.exitCode,
      0,
      reason: '${result.stdout}\n${result.stderr}',
    );
  });

  group('D-4 structural rules on the real output', () {
    late final String source;
    setUpAll(() {
      source = File(_libraryPath).readAsStringSync();
    });

    test('dart-layer types wrap and implement their parity types', () {
      expect(
        source,
        contains(
          r'extension type WindowNsDart(WindowNs $js) implements WindowNs {',
        ),
      );
      expect(
        source,
        contains(
          r'extension type WorkspaceNsDart(WorkspaceNs $js) '
          'implements WorkspaceNs {',
        ),
      );
    });

    test('promise returns become futures (dc:future-from-promise)', () {
      expect(
        source,
        contains(
          'Future<T?> showInformationMessage<T extends JSAny?>(',
        ),
      );
      expect(source, contains('.toDart.then((value) => value?.toDart)'));
      expect(source, contains('Future<bool> '));
    });

    test('event members gain stream accessors (dc:stream-from-event)', () {
      expect(
        source,
        contains('Stream<TextEditor?> get onDidChangeActiveTextEditorStream'),
      );
      expect(source, contains(r'Stream<S> _eventStream$<S>('));
      expect(source, contains('StreamController<S>.broadcast('));
      // EventEmitter.event carries its type parameter into the stream.
      expect(source, contains('Stream<T> get eventStream'));
    });

    test('constructor helpers take ordinary Dart scalars '
        '(dc:boundary-de-js)', () {
      expect(
        source,
        contains(
          r'Position new$(num line, num character) => '
          r'$js.new$(line.toJS, character.toJS);',
        ),
      );
    });

    test(r'lit$ factories include inherited interface members '
        '(dc:flattened-literal-factory)', () {
      final factory = RegExp(
        r'factory DecorationRenderOptionsDart\.lit\$\(\{[^}]*\}\)',
      ).firstMatch(source);
      expect(
        factory,
        isNotNull,
        reason: r'DecorationRenderOptionsDart must gain a lit$ factory',
      );
      expect(
        factory!.group(0),
        contains('backgroundColor'),
        reason:
            'the Coverage Treemap discovery: backgroundColor lives on '
            'the superinterface and must appear in the flattened factory',
      );
      expect(factory.group(0), contains('isWholeLine'));
    });

    test('the module root re-roots onto the dart layer', () {
      expect(source, contains('extension type VscodeApiDart(VscodeApi'));
      expect(source, contains('extension VscodeApiToDart on VscodeApi {'));
      expect(
        source,
        contains(r'WindowNsDart get window => WindowNsDart($js.window);'),
      );
      expect(
        source,
        contains(
          r'WorkspaceNsDart get workspace => WorkspaceNsDart($js.workspace);',
        ),
      );
    });

    test('parity types hop into the layer with a dart getter', () {
      expect(source, contains('extension TextEditorToDart on TextEditor {'));
      expect(
        source,
        contains('TextEditorDart get dart => TextEditorDart(this);'),
      );
    });
  });

  test('D-5 every dart-layer rule class has an emitter unit case', () {
    final unitSuite = File(
      'test/dart_layer_emitter_unit_test.dart',
    ).readAsStringSync();
    expect(dart_layer.dartLayerRuleClasses, isNotEmpty);
    for (final ruleClass in dart_layer.dartLayerRuleClasses) {
      expect(
        unitSuite,
        contains('dc:$ruleClass'),
        reason: 'rule class $ruleClass needs an emitter unit case',
      );
    }
  });
}
