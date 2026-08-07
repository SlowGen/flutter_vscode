import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repository.dart';

void main() {
  test(
    'a failed webview connect clears the memo so a retry reconnects',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flutter_vscode_bootstrap_retry_probe_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final probeSource = File(p.join(temporary.path, 'probe.dart'));
      final compiledProbe = File(p.join(temporary.path, 'probe.js'));
      final nodeHarness = File(p.join(temporary.path, 'harness.cjs'));

      await probeSource.writeAsString('''
import 'dart:js_interop';

import 'package:flutter_vscode/src/view_transport_web.dart';

@JS('bootstrapRetryProbe')
external set _bootstrapRetryProbe(JSFunction value);

void main() {
  _bootstrapRetryProbe = (() => _runProbe().toJS).toJS;
}

Future<JSAny?> _runProbe() async {
  final bootstrap = VSCodeViewBootstrap.acquire();
  var firstFailed = false;
  try {
    await bootstrap.connect();
  } on Object {
    firstFailed = true;
  }
  var retryConnected = false;
  try {
    final session = await bootstrap.connect();
    retryConnected = true;
    await session.close();
  } on Object {
    retryConnected = false;
  }
  return <String, Object?>{
    'firstFailed': firstFailed,
    'retryConnected': retryConnected,
  }.jsify();
}
''');
      await nodeHarness.writeAsString(r'''
const assert = require('node:assert/strict');
globalThis.self = globalThis;

// Minimal DOM/webview shim: session metadata, a postMessage that
// fails the first ready send, and a captured message listener the
// harness uses to deliver the readyAck.
const metas = {
  'flutter-vscode-session': 'session-1',
  'flutter-vscode-bootstrap-nonce': 'bootstrap-1',
};
globalThis.document = {
  scripts: [],
  currentScript: null,
  querySelector(selector) {
    const match = /meta\[name="([^"]+)"\]/.exec(selector);
    const content = match && metas[match[1]];
    return content ? {getAttribute: (n) => (n === 'content' ? content : null), content} : null;
  },
};
let messageListener = null;
globalThis.window = globalThis;
globalThis.addEventListener = (type, listener) => {
  if (type === 'message') messageListener = listener;
};
globalThis.removeEventListener = () => {};

let postCount = 0;
globalThis.acquireVsCodeApi = () => ({
  postMessage(frame) {
    postCount += 1;
    if (postCount === 1) {
      throw new Error('synthetic delivery failure');
    }
    // Reply to the ready frame with a readyAck on the next tick.
    if (frame && frame.kind === 'ready') {
      setTimeout(() => {
        messageListener({
          data: {
            protocol: 'flutter-vscode.view',
            version: 2,
            kind: 'readyAck',
            session: frame.session,
            nonce: frame.nonce,
            activeNonce: 'active-1',
          },
        });
      }, 0);
    }
  },
});

require(process.argv[2]);
(async () => {
  const report = await globalThis.bootstrapRetryProbe();
  assert.equal(report.firstFailed, true, 'first connect must fail');
  assert.equal(
    report.retryConnected,
    true,
    'a retry after a failed connect must attempt a fresh connection',
  );
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
          '--packages=${repoPath('.dart_tool/package_config.json')}',
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
