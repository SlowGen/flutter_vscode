import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_vscode/src/cli/artifact_writer.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/json_object.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'build rejects a linked host/lib before changing the link target',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_linked_host_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final create = await Process.run(
        'dart',
        [_cliPath, 'create', 'my_extension'],
        workingDirectory: workspace.path,
      );
      expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
      final project = Directory(p.join(workspace.path, 'my_extension'));
      final hostLib = Directory(p.join(project.path, 'host', 'lib'));
      final outside = Directory(p.join(workspace.path, 'outside_host_lib'));
      await hostLib.rename(outside.path);
      final sentinel = File(p.join(outside.path, 'generated', 'sentinel.txt'));
      await sentinel.parent.create();
      await sentinel.writeAsString('do not change\n');
      await Link(hostLib.path).create(outside.path);

      final build = await Process.run(
        'dart',
        [_cliPath, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, contains('UNSAFE_PROJECT_LAYOUT:'));
      expect(build.stderr, contains('host/lib'));
      expect(await sentinel.readAsString(), 'do not change\n');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test('the artifact writer rejects linked output ancestors', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'flutter_vscode_linked_writer_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final project = Directory(p.join(workspace.path, 'project'))..createSync();
    final outside = Directory(p.join(workspace.path, 'outside'))..createSync();
    final sentinel = File(
      p.join(outside.path, 'lib', 'generated', 'binding.g.dart'),
    );
    sentinel.parent.createSync(recursive: true);
    sentinel.writeAsStringSync('do not change\n');
    await Link(p.join(project.path, 'host')).create(outside.path);

    await expectLater(
      writeProjectArtifacts(
        {'host/lib/generated/binding.g.dart': '// generated\n'},
        project,
      ),
      throwsA(
        isA<CliException>()
            .having((error) => error.code, 'code', 'UNSAFE_OUTPUT_PATH')
            .having(
              (error) => error.message,
              'message',
              contains('host'),
            ),
      ),
    );
    expect(await sentinel.readAsString(), 'do not change\n');
  });

  test(
    'create, build, and package failures expose stable CLI codes',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_error_codes_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final cases = <(List<String>, int, String, String)>[
        (
          ['create', '../unsafe'],
          64,
          'INVALID_PROJECT_NAME:',
          'lowercase_with_underscores',
        ),
        (
          ['create', 'my__extension'],
          64,
          'INVALID_PROJECT_NAME:',
          'lowercase_with_underscores',
        ),
        (
          ['create', 'my_extension_'],
          64,
          'INVALID_PROJECT_NAME:',
          'lowercase_with_underscores',
        ),
        (
          ['build'],
          64,
          'BUILD_NOT_EXTENSION_PROJECT:',
          'extension.dart',
        ),
        (
          ['package'],
          64,
          'PACKAGE_NOT_EXTENSION_PROJECT:',
          'extension.dart',
        ),
      ];
      for (final cliCase in cases) {
        final result = await Process.run(
          'dart',
          [_cliPath, ...cliCase.$1],
          workingDirectory: workspace.path,
        );

        expect(result.exitCode, cliCase.$2, reason: cliCase.$1.join(' '));
        expect(
          result.stderr,
          startsWith(cliCase.$3),
          reason: cliCase.$1.join(' '),
        );
        expect(
          result.stderr,
          contains(cliCase.$4),
          reason: cliCase.$1.join(' '),
        );
      }
    },
    // Several real CLI invocations: the 30-second default is tight enough to
    // fail on a loaded machine, which is a flaky red for a reason that has
    // nothing to do with the behaviour under test.
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'tool startup failures expose a stable CLI code',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_missing_tool_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final create = await Process.run(
        _dartExecutable,
        [_cliPath, 'create', 'my_extension'],
        workingDirectory: workspace.path,
      );
      expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
      final emptyPath = Directory(p.join(workspace.path, 'empty_path'))
        ..createSync();

      final build = await Process.run(
        _dartExecutable,
        [_cliPath, 'build'],
        workingDirectory: p.join(workspace.path, 'my_extension'),
        environment: <String, String>{'PATH': emptyPath.path},
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, startsWith('TOOL_COMMAND_START_FAILED:'));
      expect(build.stderr, contains('dart'));
      expect(build.stderr, isNot(contains('Unhandled exception')));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'package rejects a traversing manifest name without escaping build',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_package_escape_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final create = await Process.run(
        'dart',
        [_cliPath, 'create', 'my_extension'],
        workingDirectory: workspace.path,
      );
      expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
      final project = Directory(p.join(workspace.path, 'my_extension'));
      final build = await Process.run(
        'dart',
        [_cliPath, 'build'],
        workingDirectory: project.path,
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');

      final manifestFile = File(p.join(project.path, 'package.json'));
      final manifest = decodeJsonObject(
        await manifestFile.readAsString(),
        'package.json',
      )..['name'] = '../../escaped';
      const encoder = JsonEncoder.withIndent('  ');
      await manifestFile.writeAsString('${encoder.convert(manifest)}\n');
      final receiptFile = File(
        p.join(project.path, '.dart_tool', 'flutter_vscode', 'build.json'),
      );
      final receipt = decodeJsonObject(
        await receiptFile.readAsString(),
        'build.json',
      );
      final artifacts = (receipt['artifacts']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      artifacts['package.json'] = sha256
          .convert(await manifestFile.readAsBytes())
          .toString();
      await receiptFile.writeAsString('${encoder.convert(receipt)}\n');
      final outside = File(p.join(workspace.path, 'escaped-0.0.1.vsix'));
      await outside.writeAsString('do not change\n');

      final package = await Process.run(
        'dart',
        [_cliPath, 'package'],
        workingDirectory: project.path,
      );

      expect(
        package.exitCode,
        1,
        reason: '${package.stdout}\n${package.stderr}',
      );
      expect(package.stderr, startsWith('INVALID_PROJECT_MANIFEST:'));
      expect(package.stderr, contains('../../escaped'));
      expect(package.stderr, contains('lower-kebab'));
      expect(await outside.readAsString(), 'do not change\n');
      expect(Directory(p.join(project.path, 'build')).existsSync(), isFalse);

      manifest
        ..['name'] = 'my-extension'
        ..['version'] = '0/../../../escaped-version';
      await manifestFile.writeAsString('${encoder.convert(manifest)}\n');
      artifacts['package.json'] = sha256
          .convert(await manifestFile.readAsBytes())
          .toString();
      await receiptFile.writeAsString('${encoder.convert(receipt)}\n');
      final versionEscape = File(
        p.join(workspace.path, 'escaped-version.vsix'),
      );
      await versionEscape.writeAsString('do not change\n');

      final unsafeOutput = await Process.run(
        'dart',
        [_cliPath, 'package'],
        workingDirectory: project.path,
      );

      expect(
        unsafeOutput.exitCode,
        1,
        reason: '${unsafeOutput.stdout}\n${unsafeOutput.stderr}',
      );
      expect(unsafeOutput.stderr, startsWith('UNSAFE_PACKAGE_OUTPUT:'));
      expect(unsafeOutput.stderr, contains('managed build directory'));
      expect(await versionEscape.readAsString(), 'do not change\n');
      expect(Directory(p.join(project.path, 'build')).existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

String get _cliPath => p.join(
  Directory.current.path,
  'bin',
  'flutter_vscode.dart',
);

String get _dartExecutable {
  final executableName = Platform.isWindows ? 'dart.exe' : 'dart';
  final pathSeparator = Platform.isWindows ? ';' : ':';
  for (final directory in (Platform.environment['PATH'] ?? '').split(
    pathSeparator,
  )) {
    final flutterSdkCandidate = File(
      p.join(directory, 'cache', 'dart-sdk', 'bin', executableName),
    );
    if (flutterSdkCandidate.existsSync()) {
      return flutterSdkCandidate.absolute.path;
    }
    final candidate = File(p.join(directory, executableName));
    if (candidate.existsSync()) {
      return candidate.absolute.path;
    }
  }
  throw StateError('Could not resolve dart from PATH for the CLI test.');
}
