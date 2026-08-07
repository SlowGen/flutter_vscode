import 'dart:convert';
import 'dart:io';

import 'package:dart_vscode/contributions.dart';
import 'package:flutter_vscode/src/cli/project_artifacts.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> descriptor() => <String, Object?>{
    'schemaVersion': 1,
    'name': 'fixture',
    'displayName': 'Fixture',
    'description': 'Fixture.',
    'version': '0.0.0',
    'publisher': 'test',
    'activationEvents': <Object?>[],
  };

  test('emission is one module: the templates are implementation', () {
    // templates.dart had exactly one importer, so its seam separated
    // nothing; the template bodies now live behind emitProjectArtifacts.
    expect(
      File('lib/src/cli/templates.dart').existsSync(),
      isFalse,
      reason: 'the single-importer template module fails the deletion test',
    );
  });

  test('emits exactly the Project-Derived Artifacts', () {
    final files = emitProjectArtifacts(descriptor());

    expect(
      files.keys.toSet(),
      {
        'host/lib/generated/vscode_runtime.g.dart',
        'host/lib/generated/host_exports.g.dart',
        'host/bootstrap.cjs',
        'package.json',
      },
      reason:
          'the API surface ships in package:dart_vscode; a build emits '
          'only what is derived from the project itself',
    );
    expect(files, emitProjectArtifacts(descriptor()));
  });

  test('uses one extension identity hash in Dart exports and bootstrap', () {
    final files = emitProjectArtifacts(descriptor());
    const key =
        'e_f4529a9f7129de4b2f063d5b0c34ffb960319d0e59975008828117c7271de9c4';

    expect(
      files['host/lib/generated/host_exports.g.dart'],
      allOf(
        contains('__flutterVscode.hosts.$key'),
        contains('const generatedExtensionId = "test.fixture";'),
      ),
    );
    expect(
      files['host/bootstrap.cjs'],
      allOf(
        contains('const emittedExtensionKey = "$key";'),
        contains(".createHash('sha256')"),
        contains('extensionKey !== emittedExtensionKey'),
      ),
    );
  });

  test('the generated runtime wires the dart_vscode host runtime', () {
    final runtime =
        emitProjectArtifacts(descriptor())['host/lib/generated/'
            'vscode_runtime.g.dart']!;

    expect(runtime, contains('installGeneratedHostRuntime'));
    expect(runtime, contains('stackMappers'));
    expect(runtime, contains('callbackWrappers'));
    expect(runtime, contains('package:dart_vscode/host_runtime.dart'));
    expect(runtime, isNot(contains('observeHostBindings')));
    expect(runtime, isNot(contains('observeHostCallback')));
  });

  test('generated Dart modules stay typed and interop-clean', () {
    final files = emitProjectArtifacts(descriptor());
    final bootstrap = files['host/bootstrap.cjs']!;
    expect(bootstrap, isNot(contains('bindingObservers')));
    expect(bootstrap, isNot(contains('observedBindingIds')));
    expect(bootstrap, isNot(contains('FLUTTER_VSCODE_HOST_EVIDENCE_PATH')));

    for (final entry in files.entries.where(
      (entry) => entry.key.endsWith('.dart'),
    )) {
      expect(entry.value, isNot(contains('dynamic')), reason: entry.key);
      expect(entry.value, isNot(contains('dart:js_util')), reason: entry.key);
      // The runtime module alone may use unsafe property access: its
      // hostFetch helper builds WHATWG fetch init objects dynamically.
      if (!entry.key.endsWith('vscode_runtime.g.dart')) {
        expect(
          entry.value,
          isNot(contains('dart:js_interop_unsafe')),
          reason: entry.key,
        );
      }
    }
  });

  test('emitted Dart modules are formatter-stable', () async {
    // An Extension Author running `dart format .` must not dirty
    // Framework-Managed Artifacts, and a rebuild must reproduce the
    // receipted bytes even after such a format: the templates are written
    // in the exact style the pinned SDK's formatter produces.
    final temporary = await Directory.systemTemp.createTemp(
      'flutter_vscode_template_format_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final files = emitProjectArtifacts(descriptor());
    for (final entry in files.entries.where(
      (entry) => entry.key.endsWith('.dart'),
    )) {
      final artifact = File('${temporary.path}/${entry.key.split('/').last}')
        ..writeAsStringSync(entry.value);
      final result = await Process.run('dart', [
        'format',
        '--output=none',
        '--set-exit-if-changed',
        artifact.path,
      ]);
      expect(
        result.exitCode,
        0,
        reason:
            '${entry.key} must already be formatted:\n'
            '${result.stdout}\n${result.stderr}',
      );
    }
  });

  test('emits the manifest byte-for-byte from project data and the pin', () {
    expect(
      emitProjectArtifacts(descriptor())['package.json'],
      '''
{
  "name": "fixture",
  "displayName": "Fixture",
  "description": "Fixture.",
  "version": "0.0.0",
  "publisher": "test",
  "engines": {
    "vscode": "1.129.1"
  },
  "main": "./out/bootstrap.cjs",
  "activationEvents": []
}
''',
    );
  });

  test('manifest emission fails closed on rejected author data', () {
    expect(
      () => emitProjectArtifacts(descriptor()..['version'] = 'not-semver'),
      throwsA(
        isA<Exception>().having(
          (error) => '$error',
          'message',
          startsWith('INVALID_PROJECT_MANIFEST:'),
        ),
      ),
    );
  });

  test('decodes as JSON and matches the projected manifest shape', () {
    final manifest =
        jsonDecode(
              emitProjectArtifacts(descriptor())['package.json']!,
            )
            as Map<String, Object?>;
    expect(manifest['engines'], {'vscode': vscodeApiVersion});
    expect(manifest.containsKey('contributes'), isFalse);
  });
}
