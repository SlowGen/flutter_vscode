import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repository.dart';

/// The command-registration module is a library in `package:dart_vscode`, so
/// the analyzer proves it compiles and this proves it behaves. It used to be
/// a `const` string, which left assertions about its *source text* as the
/// only thing a test could reach.
void main() {
  group('ExtensionCommands', () {
    test('a host-only project receives no command module', () async {
      // It is a library now, so `build` has nothing to copy.
      for (final project in [
        'test/fixtures/host_extension',
        repoPath('extensions/pubspec_lens'),
      ]) {
        expect(
          File(
            p.join(project, 'host', 'lib', 'generated', 'host_commands.g.dart'),
          ).existsSync(),
          isFalse,
          reason: project,
        );
      }
    });

    test(
      'a registered handler receives dartified arguments and its Future '
      'result round-trips to the host',
      () async {
        final temporary = await Directory.systemTemp.createTemp(
          'flutter_vscode_host_commands_probe_',
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
        final extensionKey = RegExp(r'stackMappers\.(e_[0-9a-f]{64})')
            .firstMatch(
              File(
                'test/fixtures/host_extension/host/lib/generated/'
                'vscode_runtime.g.dart',
              ).readAsStringSync(),
            )!
            .group(1)!;

        await probeSource.writeAsString('''
import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart';
import 'package:dart_vscode/host_commands.dart';

@JS('hostCommandsProbe')
external set _hostCommandsProbe(JSFunction value);

void main() {
  _hostCommandsProbe = ((JSObject rawContext, JSObject rawVscode) {
    final commands = ExtensionCommands(
      context: ExtensionContext(rawContext),
      api: VscodeApi(rawVscode).dart,
    );
    commands.register('probe.echo', (arguments) async {
      await Future<void>.delayed(Duration.zero);
      return <String, Object?>{
        'argumentCount': arguments.length,
        'arguments': arguments,
      };
    });
    commands.register('probe.fail', (arguments) async {
      throw StateError('deliberate probe failure');
    });
    return commands.register('probe.text', (arguments) => 'plain text').isA<JSObject>();
  }).toJS;
}
''');
        await nodeHarness.writeAsString('''
'use strict';

const assert = require('node:assert/strict');

globalThis.self = globalThis;
globalThis.__flutterVscode = {
  stackMappers: { $extensionKey: (stack) => stack },
  callbackWrappers: {
    $extensionKey: (callback) =>
      function (...args) {
        return Reflect.apply(callback, this, args);
      },
  },
};
require(process.argv[2]);

const read = (value, key) =>
  value instanceof Map ? value.get(key) : value[key];

(async () => {
  const subscriptions = [];
  const registered = new Map();
  const registrationIsDisposable = globalThis.hostCommandsProbe(
    { subscriptions },
    {
      commands: {
        registerCommand(name, callback) {
          registered.set(name, callback);
          return { dispose() {} };
        },
      },
    },
  );

  assert.equal(registrationIsDisposable, true);
  assert.equal(registered.size, 3);
  assert.equal(subscriptions.length, 3);
  for (const subscription of subscriptions) {
    assert.equal(typeof subscription.dispose, 'function');
  }

  const echoed = await registered.get('probe.echo')(41, {
    linesFound: 7,
    tags: ['a', true],
  });
  assert.equal(read(echoed, 'argumentCount'), 2);
  const echoedArguments = read(echoed, 'arguments');
  assert.equal(echoedArguments[0], 41);
  assert.equal(read(echoedArguments[1], 'linesFound'), 7);
  assert.deepEqual([...read(echoedArguments[1], 'tags')], ['a', true]);

  const bare = await registered.get('probe.echo')();
  assert.equal(read(bare, 'argumentCount'), 0);
  assert.deepEqual([...read(bare, 'arguments')], []);

  assert.equal(await registered.get('probe.text')(), 'plain text');

  let rejection;
  try {
    await registered.get('probe.fail')();
  } catch (error) {
    rejection = error;
  }
  assert.ok(rejection, 'a throwing handler must reject the host promise');
  assert.match(String(rejection.message), /deliberate probe failure/);
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
  });
}
