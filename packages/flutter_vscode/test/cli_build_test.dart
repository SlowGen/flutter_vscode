import 'dart:convert';
import 'dart:io';

import 'package:dart_vscode/contributions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'build assembles a runnable host extension',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_build_',
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

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      for (final path in [
        'package.json',
        p.join('host', 'bootstrap.cjs'),
        p.join('host', 'lib', 'generated', 'host_exports.g.dart'),
        p.join('host', 'lib', 'generated', 'vscode_runtime.g.dart'),
        p.join('out', 'bootstrap.cjs'),
        p.join('out', 'extension.dart.js'),
        p.join('out', 'extension.dart.js.map'),
        p.join('.vscode', 'launch.json'),
      ]) {
        expect(
          File(p.join(project.path, path)).existsSync(),
          isTrue,
          reason: 'Expected build artifact $path',
        );
      }
      expect(
        File(
          p.join(
            project.path,
            'host',
            'lib',
            'generated',
            'view_protocol.g.dart',
          ),
        ).existsSync(),
        isFalse,
      );
      // The coverage ledger is maintainer evidence for the shipped API
      // layer, identical for every project; a build emits only artifacts
      // derived from the project itself.
      expect(
        File(p.join(project.path, 'coverage.json')).existsSync(),
        isFalse,
      );

      final manifest =
          jsonDecode(
                File(p.join(project.path, 'package.json')).readAsStringSync(),
              )
              as Map<String, Object?>;
      expect(manifest['main'], './out/bootstrap.cjs');
      expect(manifest['name'], 'my-extension');
      expect(
        manifest['engines'],
        <String, Object?>{'vscode': vscodeApiVersion},
      );
      expect(
        Directory(p.join(project.path, 'node_modules')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'build regenerates the managed artifact tree byte for byte',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_regeneration_',
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
      final firstBuild = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );
      expect(
        firstBuild.exitCode,
        0,
        reason: '${firstBuild.stdout}\n${firstBuild.stderr}',
      );
      final managedPaths = <String>[
        '.dart_tool/flutter_vscode/build.json',
        '.vscode/launch.json',
        'host/bootstrap.cjs',
        'host/lib/generated/host_exports.g.dart',
        'host/lib/generated/vscode_runtime.g.dart',
        'out/bootstrap.cjs',
        'out/extension.dart.js',
        'out/extension.dart.js.map',
        'package.json',
      ];
      final firstBytes = <String, List<int>>{
        for (final path in managedPaths)
          path: await File(p.join(project.path, path)).readAsBytes(),
      };
      File(p.join(project.path, 'package.json')).writeAsStringSync('{}\n');
      File(
        p.join(project.path, 'host', 'lib', 'generated', 'stale.g.dart'),
      ).writeAsStringSync('// stale\n');
      File(
        p.join(project.path, 'out', 'stale.js'),
      ).writeAsStringSync('// stale\n');

      final secondBuild = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(
        secondBuild.exitCode,
        0,
        reason: '${secondBuild.stdout}\n${secondBuild.stderr}',
      );
      expect(
        File(
          p.join(project.path, 'host', 'lib', 'generated', 'stale.g.dart'),
        ).existsSync(),
        isFalse,
      );
      expect(
        File(p.join(project.path, 'out', 'stale.js')).existsSync(),
        isFalse,
      );
      for (final path in managedPaths) {
        expect(
          await File(p.join(project.path, path)).readAsBytes(),
          firstBytes[path],
          reason: '$path changed across identical builds',
        );
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'build parses Dart-owned metadata without executing project code',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_descriptor_',
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
      final marker = File(p.join(workspace.path, 'descriptor-executed'));
      File(p.join(project.path, 'extension.dart')).writeAsStringSync('''
import 'dart:io';

final extension = _createExtension();

Map<String, Object?> _createExtension() {
  File(${jsonEncode(marker.path)}).writeAsStringSync('executed');
  return <String, Object?>{
    'schemaVersion': 1,
    'name': 'my-extension',
    'displayName': 'My Extension',
    'description': 'A VS Code extension written in Dart.',
    'version': '0.0.1',
    'publisher': 'local',
    'activationEvents': <String>[],
    'commands': <Map<String, Object?>>[],
  };
}
''');

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(marker.existsSync(), isFalse);
      expect(
        build.stderr,
        contains('package:flutter_vscode/manifest.dart'),
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'build emits the Flutter View host module for view projects',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_view_host_',
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

      final hostOnlyBuild = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );
      expect(
        hostOnlyBuild.exitCode,
        0,
        reason: '${hostOnlyBuild.stdout}\n${hostOnlyBuild.stderr}',
      );
      final module = File(
        p.join(
          project.path,
          'host',
          'lib',
          'generated',
          'flutter_view_host.g.dart',
        ),
      );
      expect(
        module.existsSync(),
        isFalse,
        reason: 'A host-only project must not carry the view host module',
      );

      _writeMinimalFlutterViewInto(
        Directory(p.join(project.path, 'views', 'main_panel')),
      );
      final viewBuild = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );
      expect(
        viewBuild.exitCode,
        0,
        reason: '${viewBuild.stdout}\n${viewBuild.stderr}',
      );
      // The Flutter View host module is a library in package:dart_vscode,
      // not a file emitted into the project, so nothing is copied here.
      expect(module.existsSync(), isFalse);
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );

  test(
    'build ignores package test directories in the boundary check',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_shared_tests_',
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
      final sharedTests = Directory(p.join(project.path, 'shared', 'test'))
        ..createSync(recursive: true);
      // Author tests for shared code depend on packages (like test) that
      // never run inside the Extension Host and must not fail the build.
      File(p.join(sharedTests.path, 'shared_test.dart')).writeAsStringSync(
        "import 'package:test/test.dart';\nvoid main() {}\n",
      );

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'build reports Host Dart dependency violations',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_boundary_',
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
      File(
        p.join(project.path, 'host', 'lib', 'extension.dart'),
      ).writeAsStringSync("import 'dart:io';\nvoid main() {}\n");

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(
        build.stderr,
        contains('Host Dart dependency boundary check failed'),
      );
      expect(build.stderr, contains('dart:io'));
      expect(build.stderr, contains('Move this code to a Flutter View'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'build reports malformed Host Dart with a stable source diagnostic',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_host_syntax_',
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
      File(
        p.join(project.path, 'host', 'lib', 'extension.dart'),
      ).writeAsStringSync("import 'dart:js_interop'\nvoid main() {}\n");

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, startsWith('INVALID_HOST_DART:'));
      expect(
        build.stderr,
        contains('host/lib/extension.dart:1:'),
      );
      expect(build.stderr, contains("Expected to find ';'"));
      expect(
        build.stderr,
        contains('Fix the Dart syntax and rerun flutter_vscode build.'),
      );
      expect(build.stderr, isNot(contains('Unhandled exception')));
      expect(build.stderr, isNot(matches(RegExp(r'^#\d+', multiLine: true))));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'build scans unreachable Dart files across host and shared packages',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_unreachable_boundary_',
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
      File(
        p.join(project.path, 'host', 'lib', 'unused_platform.dart'),
      ).writeAsStringSync("import 'dart:io';\n");
      File(
        p.join(project.path, 'shared', 'lib', 'unused_browser.dart'),
      ).writeAsStringSync("import 'package:web/web.dart';\n");

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
      expect(build.stderr, contains('unused_platform.dart'));
      expect(build.stderr, contains('dart:io'));
      expect(build.stderr, contains('unused_browser.dart'));
      expect(build.stderr, contains('package:web/web.dart'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

void _writeMinimalFlutterViewInto(Directory view) {
  Directory(p.join(view.path, 'lib')).createSync(recursive: true);
  Directory(p.join(view.path, 'web')).createSync(recursive: true);
  File(p.join(view.path, 'pubspec.yaml')).writeAsStringSync('''
name: main_panel
publish_to: none

environment:
  sdk: ^3.12.0

dependencies:
  flutter:
    sdk: flutter
''');
  File(p.join(view.path, 'lib', 'main.dart')).writeAsStringSync('''
import 'package:flutter/widgets.dart';

void main() {
  runApp(
    const Directionality(
      textDirection: TextDirection.ltr,
      child: Text('Flutter View ready'),
    ),
  );
}
''');
  File(p.join(view.path, 'web', 'index.html')).writeAsStringSync(r'''
<!DOCTYPE html>
<html>
<head>
  <base href="$FLUTTER_BASE_HREF">
  <meta charset="UTF-8">
  <title>Main Panel</title>
</head>
<body>
  <script src="flutter_bootstrap.js" async></script>
</body>
</html>
''');
}
