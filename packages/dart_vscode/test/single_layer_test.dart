import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repository.dart';

/// SL-1: one self-contained generated API artifact.
///
/// The mechanical dart layer carries the substrate (the former standalone
/// Parity Layer emission) inside `vscode_dart_layer.g.dart` instead of
/// importing it, the standalone parity artifact and its
/// `package:flutter_vscode/vscode_parity.dart` export retire, and
/// `flutter_vscode build` emits exactly one API artifact into projects.
void main() {
  const layerArtifact =
      'packages/dart_vscode/lib/src/generated/vscode_dart_layer.g.dart';
  final artifactPath = repoPath(layerArtifact);

  group('the merged artifact is self-contained', () {
    late final String source;
    setUpAll(() {
      source = File(artifactPath).readAsStringSync();
    });

    test('it inlines the substrate types', () {
      expect(
        source,
        contains('extension type Position(JSObject _self)'),
        reason: 'substrate class wrappers must live inside the artifact',
      );
      expect(
        source,
        contains('extension type VscodeApi(JSObject _self)'),
        reason: 'the substrate module root must live inside the artifact',
      );
      expect(
        source,
        contains('typedef Thenable<T extends JSAny?> = JSPromise<T>;'),
        reason: 'substrate typedefs must live inside the artifact',
      );
      expect(
        source,
        contains('int _trimTrailingNulls('),
        reason: 'the substrate trimming helper must live inside the artifact',
      );
    });

    test('it keeps the dart-layer types beside the substrate', () {
      expect(source, contains('extension type VscodeApiDart(VscodeApi'));
      expect(source, contains(r'Stream<S> _eventStream$<S>('));
    });

    test('it imports no parity artifact', () {
      expect(
        source,
        isNot(contains('vscode_parity_layer')),
        reason: 'the artifact must not reference the retired parity file',
      );
    });
  });

  test('the standalone parity artifact and its export are retired', () {
    expect(
      File('lib/vscode_parity.dart').existsSync(),
      isFalse,
      reason: 'the parity export retires with its artifact',
    );
    expect(
      File('lib/src/generated/vscode_parity_layer.g.dart').existsSync(),
      isFalse,
      reason: 'the standalone parity artifact retires',
    );
    final generated =
        Directory(repoPath('packages/dart_vscode/lib/src/generated'))
            .listSync()
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toList()
          ..sort();
    expect(
      generated,
      ['vscode_dart_layer.g.dart'],
      reason: 'dart_vscode must hold exactly one generated API artifact',
    );
    expect(
      File(
        repoPath('packages/dart_vscode/lib/dart_vscode.dart'),
      ).readAsStringSync(),
      isNot(contains('vscode_parity_layer.g.dart')),
      reason: 'the one API export must not re-export the retired artifact',
    );
  });

  test('built project trees carry no standalone parity artifact', () {
    for (final generatedRoot in [
      '../flutter_vscode/test/fixtures/host_extension/host/lib/generated',
      repoPath('extensions/coverage_treemap/host/lib/generated'),
    ]) {
      final names = Directory(
        generatedRoot,
      ).listSync().whereType<File>().map((file) => p.basename(file.path));
      expect(
        names,
        isNot(contains('vscode_parity_layer.g.dart')),
        reason: '$generatedRoot must not carry the retired parity artifact',
      );
      expect(
        names,
        isNot(contains('vscode_dart_layer.g.dart')),
        reason:
            '$generatedRoot must not carry a copy of the API layer: '
            'the layer ships in the framework package and projects import '
            'it from there',
      );
    }
    expect(
      File(
        '../flutter_vscode/lib/src/cli/build_command.dart',
      ).readAsStringSync(),
      isNot(contains('vscode_parity_layer.g.dart')),
      reason: 'build must emit only the merged artifact',
    );
  });

  /// SL-2: the walking-slice facade and its parity-slice sibling retire.
  ///
  /// The generator stops emitting `vscode_facade.g.dart` and
  /// `vscode_parity.g.dart`; every importer (fixture host, example host,
  /// scaffold, FlutterViewHost template) speaks the single layer plus the
  /// runtime and host-exports modules.
  group('SL-2: the walking-slice facade and parity sibling retire', () {
    test('built project trees carry no facade or walking-slice parity', () {
      for (final generatedRoot in [
        '../flutter_vscode/test/fixtures/host_extension/host/lib/generated',
        repoPath('extensions/coverage_treemap/host/lib/generated'),
      ]) {
        final names = Directory(generatedRoot)
            .listSync()
            .whereType<File>()
            .map((file) => p.basename(file.path))
            .toList();
        expect(
          names,
          isNot(contains('vscode_facade.g.dart')),
          reason: '$generatedRoot must not carry the retired facade',
        );
        expect(
          names,
          isNot(contains('vscode_parity.g.dart')),
          reason:
              '$generatedRoot must not carry the retired walking-slice parity',
        );
        expect(
          names,
          containsAll(['host_exports.g.dart', 'vscode_runtime.g.dart']),
          reason: '$generatedRoot keeps the runtime and host-exports modules',
        );
      }
    });

    test('the generator no longer emits the retired artifacts', () {
      expect(
        File('tool/binding_generator/generator.dart').readAsStringSync(),
        allOf(
          isNot(contains('vscode_facade.g.dart')),
          isNot(contains('vscode_parity.g.dart')),
        ),
        reason: 'the emit dispatch must not name the retired artifacts',
      );
      expect(
        File(
          '../flutter_vscode/lib/src/cli/project_artifacts.dart',
        ).readAsStringSync(),
        allOf(
          isNot(contains('walkingSliceFacadeTemplate')),
          isNot(contains('walkingSliceParityTemplate')),
        ),
        reason: 'the facade and walking-slice parity templates retire',
      );
    });

    test('hosts, scaffold, and view-host template import no facade', () {
      for (final source in [
        '../flutter_vscode/test/fixtures/host_extension/host/lib/extension.dart',
        repoPath('extensions/coverage_treemap/host/lib/extension.dart'),
        '../flutter_vscode/lib/src/cli/create_command.dart',
        repoPath('packages/dart_vscode/lib/src/flutter_view_host.dart'),
      ]) {
        expect(
          File(source).readAsStringSync(),
          isNot(contains('vscode_facade')),
          reason: '$source must consume the single layer, not the facade',
        );
      }
    });
  });

  /// SL-3: living docs describe one generated API layer.
  ///
  /// Prose truth for the single-layer world: no living document may keep
  /// routing readers to the retired facade artifact, the retired standalone
  /// parity artifact, or its retired package export. ADR text is history
  /// (amended, never rewritten) and stays exempt; so do archived plans,
  /// which live outside the scanned roots.
  group('SL-3: living docs describe one generated API layer', () {
    test('no retired artifact references survive in living docs', () {
      const retiredReferences = [
        'vscode_facade.g.dart',
        'vscode_parity_layer.g.dart',
        'package:flutter_vscode/vscode_parity.dart',
      ];
      final livingDocs = <File>[
        File('README.md'),
        File(repoPath('CONTEXT.md')),
        for (final root in ['docs', 'specs/architecture', 'skills'])
          ...Directory(repoPath(root))
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.md')),
      ];
      final violations = <String>[];
      for (final doc in livingDocs) {
        if (p.split(doc.path).contains('adr')) {
          continue;
        }
        final text = doc.readAsStringSync();
        for (final reference in retiredReferences) {
          if (text.contains(reference)) {
            violations.add('${doc.path}: $reference');
          }
        }
      }
      expect(
        violations,
        isEmpty,
        reason:
            'living docs must describe the one generated API layer, '
            'never the retired artifacts: $violations',
      );
    });
  });
}
