import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('create scaffolds a host-only Extension Project', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'flutter_vscode_cli_create_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final executable = p.join(
      Directory.current.path,
      'bin',
      'flutter_vscode.dart',
    );

    final result = await Process.run(
      'dart',
      [executable, 'create', 'my_extension'],
      workingDirectory: workspace.path,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final project = Directory(p.join(workspace.path, 'my_extension'));
    expect(
      [
        p.join('host', 'lib', 'extension.dart'),
        p.join('host', 'pubspec.yaml'),
        p.join('shared', 'lib', 'shared.dart'),
        p.join('shared', 'pubspec.yaml'),
        'extension.dart',
        'pubspec.yaml',
      ],
      everyElement(
        predicate<String>(
          (path) => File(p.join(project.path, path)).existsSync(),
          'is a scaffolded file',
        ),
      ),
    );
    expect(Directory(p.join(project.path, 'views')).existsSync(), isTrue);
    expect(File(p.join(project.path, 'extension.json')).existsSync(), isFalse);

    final hostPubspec = File(
      p.join(project.path, 'host', 'pubspec.yaml'),
    ).readAsStringSync();
    expect(hostPubspec, contains('my_extension_shared:'));
    expect(hostPubspec, contains('path: ../shared'));
    final hostSource = File(
      p.join(project.path, 'host', 'lib', 'extension.dart'),
    ).readAsStringSync();
    expect(
      hostSource,
      contains("import 'package:my_extension_shared/shared.dart';"),
    );

    final authorFiles = await project
        .list(recursive: true)
        .where((entity) => entity is File)
        .cast<File>()
        .map((file) => p.relative(file.path, from: project.path))
        .toList();
    expect(
      authorFiles.where(
        (path) =>
            path.endsWith('.js') ||
            path.endsWith('.ts') ||
            path == 'package.json',
      ),
      isEmpty,
    );
  });

  test('create keeps extension metadata in Dart', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'flutter_vscode_cli_dart_metadata_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final executable = p.join(
      Directory.current.path,
      'bin',
      'flutter_vscode.dart',
    );

    final result = await Process.run(
      'dart',
      [executable, 'create', 'my_extension'],
      workingDirectory: workspace.path,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final source = File(
      p.join(workspace.path, 'my_extension', 'extension.dart'),
    ).readAsStringSync();
    expect(
      source,
      contains("import 'package:flutter_vscode/manifest.dart';"),
    );
    expect(source, contains('const extension = ExtensionManifest('));
    expect(
      source,
      isNot(contains('apiTarget')),
      reason: 'the package release is the baseline; projects do not select',
    );
    expect(source, contains("name: 'my-extension'"));
    expect(source, contains("publisher: 'local'"));
    expect(source, contains("activationEvents: ['onLanguage:json']"));
    expect(source, contains('ExtensionCommand('));
    expect(source, isNot(contains('<String, Object?>{')));

    final rootPubspec = File(
      p.join(workspace.path, 'my_extension', 'pubspec.yaml'),
    );
    expect(
      rootPubspec.existsSync(),
      isTrue,
      reason:
          'The project root needs a pubspec so the typed descriptor '
          'resolves package:flutter_vscode/manifest.dart in the editor.',
    );
    expect(rootPubspec.readAsStringSync(), contains('flutter_vscode:'));
  });

  test('create puts command and hover behavior in Host Dart', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'flutter_vscode_cli_host_source_',
    );
    addTearDown(() => workspace.delete(recursive: true));
    final executable = p.join(
      Directory.current.path,
      'bin',
      'flutter_vscode.dart',
    );

    final result = await Process.run(
      'dart',
      [executable, 'create', 'my_extension'],
      workingDirectory: workspace.path,
    );

    expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
    final source = File(
      p.join(
        workspace.path,
        'my_extension',
        'host',
        'lib',
        'extension.dart',
      ),
    ).readAsStringSync();
    expect(source, contains("'my-extension.hello'"));
    expect(source, contains('registerCommand'));
    expect(source, isNot(contains('vscode_facade')));
    expect(source, contains('registerHoverProvider'));
    expect(source, contains("registerHoverProvider('json'.toJS"));
    expect(source, contains('registerHostExports'));
    expect(
      source,
      isNot(contains('Future<JSAny?>(()')),
      reason: 'Provider registration must not be deferred past activation.',
    );
    expect(
      source,
      contains(
        'activate(\n'
        '    JSObject rawContext,\n'
        '    JSObject rawVscode,\n'
        '  )',
      ),
    );
    expect(source, isNot(contains('failActivation')));
  });

  test(
    'create emits an analyzable Extension Project before its first build',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_create_analyze_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final executable = p.join(
        Directory.current.path,
        'bin',
        'flutter_vscode.dart',
      );

      final create = await Process.run(
        'dart',
        [executable, 'create', 'my_extension'],
        workingDirectory: workspace.path,
      );
      expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
      final project = Directory(p.join(workspace.path, 'my_extension'));
      final rootGet = await Process.run(
        'dart',
        const ['pub', 'get'],
        workingDirectory: project.path,
      );
      expect(
        rootGet.exitCode,
        0,
        reason: '${rootGet.stdout}\n${rootGet.stderr}',
      );
      final host = Directory(p.join(project.path, 'host'));
      final get = await Process.run(
        'dart',
        const ['pub', 'get'],
        workingDirectory: host.path,
      );
      expect(get.exitCode, 0, reason: '${get.stdout}\n${get.stderr}');

      final analyze = await Process.run(
        'dart',
        const ['analyze'],
        workingDirectory: project.path,
      );

      expect(
        analyze.exitCode,
        0,
        reason: '${analyze.stdout}\n${analyze.stderr}',
      );
      expect(analyze.stdout, contains('No issues found!'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
