import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'build and package include one optional Flutter View',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_view_',
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
      final view = Directory(p.join(project.path, 'views', 'main_panel'));
      _writeMinimalFlutterView(view);

      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      final generatedProtocol = File(
        p.join(
          project.path,
          'shared',
          'lib',
          'generated',
          'view_protocol.g.dart',
        ),
      );
      // Both runtimes type against package:dart_vscode; a view project
      // receives no copy of the protocol to keep in sync.
      expect(generatedProtocol.existsSync(), isFalse);
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
        reason:
            'the host imports package:dart_vscode/view_protocol.dart '
            'directly; there is no re-export of a copy',
      );
      final viewOutput = Directory(
        p.join(project.path, 'out', 'views', 'main_panel'),
      );
      expect(File(p.join(viewOutput.path, 'index.html')).existsSync(), isTrue);
      expect(
        File(p.join(viewOutput.path, 'flutter_bootstrap.js')).existsSync(),
        isTrue,
      );
      expect(
        File(p.join(viewOutput.path, 'main.dart.js')).existsSync(),
        isTrue,
      );
      expect(
        Directory(p.join(project.path, 'node_modules')).existsSync(),
        isFalse,
      );
      expect(
        Directory(p.join(view.path, 'node_modules')).existsSync(),
        isFalse,
      );

      final firstViewFiles =
          viewOutput
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final firstViewPaths = [
        for (final file in firstViewFiles)
          p.relative(file.path, from: viewOutput.path),
      ];
      final firstViewBytes = <String, List<int>>{
        for (var index = 0; index < firstViewFiles.length; index += 1)
          firstViewPaths[index]: await firstViewFiles[index].readAsBytes(),
      };

      final repeatedBuild = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );

      expect(
        repeatedBuild.exitCode,
        0,
        reason: '${repeatedBuild.stdout}\n${repeatedBuild.stderr}',
      );
      final repeatedViewFiles =
          viewOutput
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final repeatedViewPaths = [
        for (final file in repeatedViewFiles)
          p.relative(file.path, from: viewOutput.path),
      ];
      expect(repeatedViewPaths, orderedEquals(firstViewPaths));
      for (var index = 0; index < repeatedViewFiles.length; index += 1) {
        final path = repeatedViewPaths[index];
        expect(
          await repeatedViewFiles[index].readAsBytes(),
          firstViewBytes[path],
          reason: 'Flutter View output changed across identical builds: $path',
        );
      }
      expect(
        generatedProtocol.existsSync(),
        isFalse,
        reason: 'a rebuild must not start emitting a protocol copy',
      );

      final package = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );
      expect(
        package.exitCode,
        0,
        reason: '${package.stdout}\n${package.stderr}',
      );
      final vsix = File(
        p.join(project.path, 'build', 'my-extension-0.0.1.vsix'),
      );
      final firstBytes = await vsix.readAsBytes();
      final archive = ZipDecoder().decodeBytes(firstBytes);
      final outputFiles =
          viewOutput
              .listSync(recursive: true, followLinks: false)
              .whereType<File>()
              .toList()
            ..sort((left, right) => left.path.compareTo(right.path));
      final expectedViewEntries = <String>[
        for (final file in outputFiles)
          'extension/${p.relative(file.path, from: project.path).split(p.separator).join('/')}',
      ];
      expect(
        archive
            .map((entry) => entry.name)
            .where((name) => name.startsWith('extension/out/views/')),
        orderedEquals(expectedViewEntries),
      );
      for (var index = 0; index < outputFiles.length; index += 1) {
        expect(
          archive.findFile(expectedViewEntries[index])!.readBytes(),
          await outputFiles[index].readAsBytes(),
          reason: expectedViewEntries[index],
        );
      }
      final contentTypes = utf8.decode(
        archive.findFile('[Content_Types].xml')!.readBytes()!,
      );
      expect(
        contentTypes,
        contains('<Default Extension="html" ContentType="text/html" />'),
      );
      expect(
        contentTypes,
        contains(
          '<Default Extension="wasm" ContentType="application/wasm" />',
        ),
      );
      expect(
        contentTypes,
        contains(
          '<Default Extension="frag" ContentType="application/octet-stream" />',
        ),
      );
      expect(
        contentTypes,
        contains(
          '<Override PartName="/extension/out/views/main_panel/.last_build_id" ContentType="text/plain" />',
        ),
      );
      expect(
        contentTypes,
        contains(
          '<Override PartName="/extension/out/views/main_panel/assets/NOTICES" ContentType="text/plain" />',
        ),
      );

      final repeat = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );
      expect(repeat.exitCode, 0, reason: '${repeat.stdout}\n${repeat.stderr}');
      expect(await vsix.readAsBytes(), firstBytes);

      final viewBundle = File(p.join(viewOutput.path, 'main.dart.js'));
      final viewBundleBytes = await viewBundle.readAsBytes();
      viewBundle.writeAsStringSync(
        '\n// changed after build\n',
        mode: FileMode.append,
      );
      final staleAssetPackage = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );
      expect(
        staleAssetPackage.exitCode,
        1,
        reason: '${staleAssetPackage.stdout}\n${staleAssetPackage.stderr}',
      );
      expect(
        staleAssetPackage.stderr,
        contains('out/views/main_panel/main.dart.js'),
      );
      expect(staleAssetPackage.stderr, contains('changed after build'));
      await viewBundle.writeAsBytes(viewBundleBytes, flush: true);

      File(p.join(view.path, 'lib', 'main.dart')).writeAsStringSync(
        '\n// changed after build\n',
        mode: FileMode.append,
      );
      final stalePackage = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );
      expect(
        stalePackage.exitCode,
        1,
        reason: '${stalePackage.stdout}\n${stalePackage.stderr}',
      );
      expect(stalePackage.stderr, contains('views/main_panel/lib/main.dart'));
      expect(stalePackage.stderr, contains('changed after build'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test('build rejects unsafe Flutter View names before building', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'flutter_vscode_cli_unsafe_view_',
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
    _writeMinimalFlutterView(
      Directory(p.join(project.path, 'views', 'Unsafe-Panel')),
    );

    final build = await Process.run(
      'dart',
      [executable, 'build'],
      workingDirectory: project.path,
    );

    expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
    expect(build.stderr, contains('views/Unsafe-Panel'));
    expect(build.stderr, contains('lowercase_with_underscores'));
    expect(Directory(p.join(project.path, 'out')).existsSync(), isFalse);
  });

  test('build rejects symbolic links in Flutter View sources', () async {
    final workspace = await Directory.systemTemp.createTemp(
      'flutter_vscode_cli_linked_view_',
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
    final view = Directory(p.join(project.path, 'views', 'main_panel'));
    _writeMinimalFlutterView(view);
    final linkedTarget = File(p.join(workspace.path, 'outside.dart'))
      ..writeAsStringSync('void outside() {}\n');
    await Link(p.join(view.path, 'lib', 'outside.dart')).create(
      linkedTarget.path,
    );

    final build = await Process.run(
      'dart',
      [executable, 'build'],
      workingDirectory: project.path,
    );

    expect(build.exitCode, 1, reason: '${build.stdout}\n${build.stderr}');
    expect(build.stderr, contains('symbolic link'));
    expect(build.stderr, contains('lib/outside.dart'));
    expect(Directory(p.join(project.path, 'out')).existsSync(), isFalse);
  });
}

void _writeMinimalFlutterView(Directory view) {
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
