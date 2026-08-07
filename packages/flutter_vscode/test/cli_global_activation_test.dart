import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'locally activated CLI creates, builds, and packages an extension',
    () async {
      final temporary = await Directory.systemTemp.createTemp(
        'flutter_vscode_global_activation_',
      );
      addTearDown(() => temporary.delete(recursive: true));
      final cache = Directory(p.join(temporary.path, 'pub-cache'));
      final workspace = Directory(p.join(temporary.path, 'workspace'));
      final packageCopy = Directory(p.join(temporary.path, 'package'));
      await workspace.create();
      await _copyPackage(Directory.current, packageCopy);
      // A published workspace member carries `resolution: workspace`. Hosted
      // installs ignore it; a path-source copy has no workspace root above it,
      // so drop it to mimic what pub.dev actually resolves.
      final copiedManifest = File(p.join(packageCopy.path, 'pubspec.yaml'));
      // `dart_vscode` carries the generated VS Code API and is not published
      // yet, so a path-source activation cannot resolve it from pub.dev. Copy
      // it beside the package and override; once both packages ship together
      // this override goes away and hosted resolution covers it.
      final layerCopy = Directory(p.join(temporary.path, 'dart_vscode'));
      await _copyPackage(
        Directory(p.join(Directory.current.parent.path, 'dart_vscode')),
        layerCopy,
      );
      File(p.join(layerCopy.path, 'pubspec.yaml')).writeAsStringSync(
        File(
          p.join(layerCopy.path, 'pubspec.yaml'),
        ).readAsStringSync().replaceAll('resolution: workspace\n', ''),
      );
      copiedManifest.writeAsStringSync(
        '${copiedManifest.readAsStringSync().replaceAll('resolution: workspace\n', '')}\n'
        'dependency_overrides:\n'
        '  dart_vscode:\n'
        '    path: ${layerCopy.path}\n',
      );
      final environment = <String, String>{
        ...Platform.environment,
        'PUB_CACHE': cache.path,
      };

      final activate = await Process.run(
        'dart',
        [
          'pub',
          'global',
          'activate',
          '--source',
          'path',
          packageCopy.path,
        ],
        environment: environment,
      );
      expect(
        activate.exitCode,
        0,
        reason: '${activate.stdout}\n${activate.stderr}',
      );

      final executable = p.join(
        cache.path,
        'bin',
        Platform.isWindows ? 'flutter_vscode.bat' : 'flutter_vscode',
      );
      final create = await Process.run(
        executable,
        const ['create', 'activated_extension'],
        workingDirectory: workspace.path,
        environment: environment,
      );

      expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
      final project = Directory(
        p.join(workspace.path, 'activated_extension'),
      );
      expect(
        File(
          p.join(
            project.path,
            'host',
            'lib',
            'extension.dart',
          ),
        ).existsSync(),
        isTrue,
      );
      final build = await Process.run(
        executable,
        const ['build'],
        workingDirectory: project.path,
        environment: environment,
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');
      final package = await Process.run(
        executable,
        const ['package'],
        workingDirectory: project.path,
        environment: environment,
      );
      expect(
        package.exitCode,
        0,
        reason: '${package.stdout}\n${package.stderr}',
      );
      expect(
        File(
          p.join(
            project.path,
            'build',
            'activated-extension-0.0.1.vsix',
          ),
        ).existsSync(),
        isTrue,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}

Future<void> _copyPackage(Directory source, Directory destination) async {
  const excludedNames = {
    '.dart_tool',
    '.git',
    'build',
    'node_modules',
    'out',
  };
  await destination.create(recursive: true);
  await for (final entity in source.list()) {
    final name = p.basename(entity.path);
    if (excludedNames.contains(name)) {
      continue;
    }
    final target = p.join(destination.path, name);
    if (entity is Directory) {
      await _copyPackage(entity, Directory(target));
    } else if (entity is File) {
      await entity.copy(target);
    }
  }
}
