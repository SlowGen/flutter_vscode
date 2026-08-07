import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../tool/binding_generator/parity_report.dart' as parity;
import 'support/repository.dart';

void main() {
  test('checked-in parity report matches mechanical regeneration', () {
    final coverage =
        (jsonDecode(
                  File('tool/bindings/coverage-ledger.json').readAsStringSync(),
                )
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    final inventory =
        (jsonDecode(
                  File(
                    'tool/bindings/ir/vscode-1.129.1.json',
                  ).readAsStringSync(),
                )
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    expect(
      File(repoPath('docs/reference/parity.md')).readAsStringSync(),
      parity.buildParityReport(coverage, inventory),
      reason:
          'The parity report is a maintainer-managed doc. Refresh it '
          'with: dart tool/binding_generator/generate.dart --parity '
          '<repository root>.',
    );
  });

  test(
    'the maintainer CLI regenerates the shipped layer byte-for-byte',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flutter_vscode_binding_cli_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      // A minimal repository shape: the pinned inputs are the only reads,
      // and every write lands beneath packages/dart_vscode.
      final packageRoot = p.join(temporary.path, 'packages', 'dart_vscode');
      for (final relative in [
        'tool/bindings/ir/vscode-1.129.1.json',
        'tool/bindings/overrides/vscode-1.129.1.json',
      ]) {
        final copy = File(p.join(packageRoot, relative));
        copy.parent.createSync(recursive: true);
        File(relative).copySync(copy.path);
      }

      final result = await Process.run(
        'dart',
        [
          'tool/binding_generator/generate.dart',
          '--dart-layer',
          temporary.path,
        ],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');

      for (final relative in [
        'lib/src/generated/vscode_dart_layer.g.dart',
        'tool/bindings/dart-layer-ledger.json',
        'tool/bindings/parity-ledger.json',
        'tool/bindings/coverage-ledger.json',
      ]) {
        expect(
          File(p.join(packageRoot, relative)).readAsBytesSync(),
          File(relative).readAsBytesSync(),
          reason:
              'Checked-in $relative is stale. Run '
              'dart tool/binding_generator/generate.dart --dart-layer '
              '<repository root>.',
        );
      }
    },
  );

  test(
    'the maintainer CLI rejects unknown modes with usage guidance',
    () async {
      final result = await Process.run(
        'dart',
        ['tool/binding_generator/generate.dart', '--project'],
        workingDirectory: Directory.current.path,
      );
      expect(result.exitCode, 1);
      expect('${result.stderr}', contains('INVALID_ARGUMENTS'));
      expect(
        '${result.stderr}',
        contains('--dart-layer|--parity|--contract'),
        reason: 'the retired per-project generation mode must not return',
      );
    },
  );

  test('the runtime host fetch helper performs a real HTTP request', () async {
    final temporary = await Directory.systemTemp.createTemp(
      'flutter_vscode_host_fetch_probe_',
    );
    addTearDown(() => temporary.delete(recursive: true));
    final auditSource = File(p.join(temporary.path, 'audit.dart'));
    final compiledAudit = File(p.join(temporary.path, 'audit.js'));
    final nodeProbe = File(p.join(temporary.path, 'probe.cjs'));
    // The fixture host package is a member of the repository's pub
    // workspace, so it resolves through the workspace root's config.
    final hostPackageConfig = repoPath(
      p.join('.dart_tool', 'package_config.json'),
    );

    await auditSource.writeAsString(r'''
import 'dart:js_interop';

import 'package:dart_vscode/host_runtime.dart';

@JS('fetchProbe')
external set _fetchProbe(JSFunction value);

void main() {
  _fetchProbe = ((JSString url) => toHostPromise(
        hostFetch(url.toDart).then(
          (response) => '${response.status}:${response.body}'.toJS,
        ),
      )).toJS;
}
''');
    await nodeProbe.writeAsString(r'''
const http = require('node:http');
globalThis.self = globalThis;
require(process.argv[2]);
const server = http.createServer((request, response) => {
  response.writeHead(200, {'content-type': 'text/plain'});
  response.end('pong-body');
});
server.listen(0, '127.0.0.1', async () => {
  try {
    const port = server.address().port;
    const result =
      await globalThis.fetchProbe(`http://127.0.0.1:${port}/ping`);
    if (result !== '200:pong-body') {
      console.error(`unexpected: ${result}`);
      process.exitCode = 1;
    }
  } catch (error) {
    console.error(error);
    process.exitCode = 1;
  } finally {
    server.close();
  }
});
''');

    final compile = await Process.run(
      'dart',
      [
        'compile',
        'js',
        '--packages=$hostPackageConfig',
        auditSource.path,
        '-o',
        compiledAudit.path,
      ],
      workingDirectory: Directory.current.path,
    );
    expect(
      compile.exitCode,
      0,
      reason: '${compile.stdout}\n${compile.stderr}',
    );

    final probe = await Process.run(
      'node',
      [nodeProbe.path, compiledAudit.path],
      workingDirectory: Directory.current.path,
    );
    expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
  });
}
