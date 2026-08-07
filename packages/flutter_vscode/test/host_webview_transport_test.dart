import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repository.dart';

void main() {
  test(
    'failed native listener disposal stays owned until close retries',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flutter_vscode_transport_dispose_probe_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final probeSource = File(p.join(temporary.path, 'probe.dart'));
      final compiledProbe = File(p.join(temporary.path, 'probe.js'));
      final nodeHarness = File(p.join(temporary.path, 'harness.cjs'));
      // The fixture host package is a member of the repository's pub
      // workspace, so it resolves through the workspace root's config.
      final hostPackageConfig = repoPath(
        p.join('.dart_tool', 'package_config.json'),
      );

      await probeSource.writeAsString('''
import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart';
import 'package:dart_vscode/flutter_view_host.dart';

@JS('transportDisposeProbe')
external set _transportDisposeProbe(JSFunction value);

void main() {
  _transportDisposeProbe = ((JSObject rawWebview) =>
      _runProbe(Webview(rawWebview)).toJS).toJS;
}

Future<JSAny?> _runProbe(Webview webview) async {
  final transport = HostWebviewTransport(webview);
  var firstCloseThrew = false;
  try {
    await transport.close();
  } on Object {
    firstCloseThrew = true;
  }
  final countAfterFailure = transport.receivingSubscriptionCount;

  await transport.close();
  final countAfterRetry = transport.receivingSubscriptionCount;

  await transport.close();
  final countAfterIdempotentClose = transport.receivingSubscriptionCount;

  return <String, Object?>{
    'firstCloseThrew': firstCloseThrew,
    'countAfterFailure': countAfterFailure,
    'countAfterRetry': countAfterRetry,
    'countAfterIdempotentClose': countAfterIdempotentClose,
  }.jsify();
}
''');
      await nodeHarness.writeAsString('''
'use strict';

const assert = require('node:assert/strict');

let disposeCalls = 0;
let listenerActive = true;
globalThis.self = globalThis;
require(process.argv[2]);

(async () => {
  const report = await globalThis.transportDisposeProbe({
    onDidReceiveMessage() {
      return {
        dispose() {
          disposeCalls += 1;
          if (disposeCalls === 1) {
            throw new Error('injected native listener disposal failure');
          }
          listenerActive = false;
        },
      };
    },
    postMessage() {
      return Promise.resolve(true);
    },
  });

  assert.equal(report.firstCloseThrew, true);
  assert.equal(report.countAfterFailure, 1);
  assert.equal(report.countAfterRetry, 0);
  assert.equal(report.countAfterIdempotentClose, 0);
  assert.equal(disposeCalls, 2);
  assert.equal(listenerActive, false);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
''');

      final compile = await Process.run(
        'dart',
        [
          'compile',
          'js',
          '--packages=$hostPackageConfig',
          probeSource.path,
          '-o',
          compiledProbe.path,
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
        [nodeHarness.path, compiledProbe.path],
        workingDirectory: Directory.current.path,
      );
      expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    },
  );

  test(
    'a false native acceptance rejects the transport send future',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flutter_vscode_transport_reject_probe_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final probeSource = File(p.join(temporary.path, 'probe.dart'));
      final compiledProbe = File(p.join(temporary.path, 'probe.js'));
      final nodeHarness = File(p.join(temporary.path, 'harness.cjs'));
      // The fixture host package is a member of the repository's pub
      // workspace, so it resolves through the workspace root's config.
      final hostPackageConfig = repoPath(
        p.join('.dart_tool', 'package_config.json'),
      );

      await probeSource.writeAsString('''
import 'dart:async';
import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart';
import 'package:dart_vscode/flutter_view_host.dart';

@JS('transportRejectProbe')
external set _transportRejectProbe(JSFunction value);

void main() {
  _transportRejectProbe = ((JSObject rawWebview) =>
      _runProbe(Webview(rawWebview)).toJS).toJS;
}

Future<JSAny?> _runProbe(Webview webview) async {
  final transport = HostWebviewTransport(webview);
  unawaited(
    transport.failure.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    ),
  );
  var sendRejected = false;
  var errorMentionsRejection = false;
  try {
    await transport.send(const <String, Object?>{'kind': 'probe'});
  } on StateError catch (error) {
    sendRejected = true;
    errorMentionsRejection = error.message.contains('rejected');
  }
  return <String, Object?>{
    'sendRejected': sendRejected,
    'errorMentionsRejection': errorMentionsRejection,
  }.jsify();
}
''');
      await nodeHarness.writeAsString('''
'use strict';

const assert = require('node:assert/strict');

globalThis.self = globalThis;
require(process.argv[2]);

(async () => {
  const report = await globalThis.transportRejectProbe({
    onDidReceiveMessage() {
      return {
        dispose() {},
      };
    },
    postMessage() {
      return Promise.resolve(false);
    },
  });

  assert.equal(report.sendRejected, true);
  assert.equal(report.errorMentionsRejection, true);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
''');

      final compile = await Process.run(
        'dart',
        [
          'compile',
          'js',
          '--packages=$hostPackageConfig',
          probeSource.path,
          '-o',
          compiledProbe.path,
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
        [nodeHarness.path, compiledProbe.path],
        workingDirectory: Directory.current.path,
      );
      expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    },
  );
  test(
    'an unobserved delivery failure never escapes as an uncaught error',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flutter_vscode_transport_unobserved_probe_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final probeSource = File(p.join(temporary.path, 'probe.dart'));
      final compiledProbe = File(p.join(temporary.path, 'probe.js'));
      final nodeHarness = File(p.join(temporary.path, 'harness.cjs'));
      // The fixture host package is a member of the repository's pub
      // workspace, so it resolves through the workspace root's config.
      final hostPackageConfig = repoPath(
        p.join('.dart_tool', 'package_config.json'),
      );

      await probeSource.writeAsString('''
import 'dart:async';
import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart';
import 'package:dart_vscode/flutter_view_host.dart';

@JS('transportUnobservedProbe')
external set _transportUnobservedProbe(JSFunction value);

void main() {
  _transportUnobservedProbe = ((JSObject rawWebview) =>
      _runProbe(Webview(rawWebview)).toJS).toJS;
}

Future<JSAny?> _runProbe(Webview webview) async {
  // The FlutterViewHost composition never listens to transport.failure;
  // a rejected push must not surface as an uncaught zone error.
  var uncaughtErrors = 0;
  var sendRejected = false;
  await runZonedGuarded(() async {
    final transport = HostWebviewTransport(webview);
    try {
      await transport.send(const <String, Object?>{'kind': 'probe'});
    } on StateError {
      sendRejected = true;
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }, (error, stackTrace) {
    uncaughtErrors += 1;
  })!;
  return <String, Object?>{
    'sendRejected': sendRejected,
    'uncaughtErrors': uncaughtErrors,
  }.jsify();
}
''');
      await nodeHarness.writeAsString('''
const assert = require('node:assert/strict');
globalThis.self = globalThis;
require(process.argv[2]);
(async () => {
  const report = await globalThis.transportUnobservedProbe({
    onDidReceiveMessage() {
      return {
        dispose() {},
      };
    },
    postMessage() {
      return Promise.resolve(false);
    },
  });

  assert.equal(report.sendRejected, true);
  assert.equal(report.uncaughtErrors, 0);
})().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
''');

      final compile = await Process.run(
        'dart',
        [
          'compile',
          'js',
          '--packages=$hostPackageConfig',
          probeSource.path,
          '-o',
          compiledProbe.path,
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
        [nodeHarness.path, compiledProbe.path],
        workingDirectory: Directory.current.path,
      );
      expect(probe.exitCode, 0, reason: '${probe.stdout}\n${probe.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
