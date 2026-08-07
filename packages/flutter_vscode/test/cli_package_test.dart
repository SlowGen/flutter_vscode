import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

void main() {
  test(
    'package emits an installable VSIX layout',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_package_',
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
      expect(vsix.existsSync(), isTrue);
      final archive = ZipDecoder().decodeBytes(await vsix.readAsBytes());
      const expectedPaths = <String>[
        '[Content_Types].xml',
        'extension.vsixmanifest',
        'extension/out/bootstrap.cjs',
        'extension/out/extension.dart.js',
        'extension/out/extension.dart.js.map',
        'extension/package.json',
      ];
      expect(
        archive.map((entry) => entry.name),
        orderedEquals(expectedPaths),
      );
      for (final entry in archive) {
        expect(entry.isFile, isTrue, reason: entry.name);
        expect(entry.isSymbolicLink, isFalse, reason: entry.name);
        expect(entry.compression, CompressionType.none, reason: entry.name);
        expect(entry.unixPermissions, 0x1a4, reason: entry.name);
      }
      for (final paths in <(String, String)>[
        ('extension/package.json', 'package.json'),
        ('extension/out/bootstrap.cjs', 'out/bootstrap.cjs'),
        ('extension/out/extension.dart.js', 'out/extension.dart.js'),
        ('extension/out/extension.dart.js.map', 'out/extension.dart.js.map'),
      ]) {
        expect(
          archive.findFile(paths.$1)!.readBytes(),
          await File(p.join(project.path, paths.$2)).readAsBytes(),
          reason: paths.$1,
        );
      }
      final vsixManifest = utf8.decode(
        archive.findFile('extension.vsixmanifest')!.readBytes()!,
      );
      final contentTypes = utf8.decode(
        archive.findFile('[Content_Types].xml')!.readBytes()!,
      );
      const xmlDeclaration = '<?xml version="1.0" encoding="utf-8"?>';
      expect(contentTypes, startsWith(xmlDeclaration));
      expect(vsixManifest, startsWith(xmlDeclaration));
      expect(XmlDocument.parse(contentTypes).rootElement.name.local, 'Types');
      expect(
        XmlDocument.parse(vsixManifest).rootElement.name.local,
        'PackageManifest',
      );
      expect(vsixManifest, contains('Id="my-extension"'));
      expect(vsixManifest, contains('Publisher="local"'));
      expect(vsixManifest, contains('Version="0.0.1"'));

      final firstBytes = await vsix.readAsBytes();
      final repeat = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );
      expect(
        repeat.exitCode,
        0,
        reason: '${repeat.stdout}\n${repeat.stderr}',
      );
      expect(await vsix.readAsBytes(), firstBytes);
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'package rejects stale or malformed Framework-Managed Artifacts',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_stale_package_',
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
      File(
        p.join(project.path, 'out', 'extension.dart.js'),
      ).writeAsStringSync(
        '\n// changed after build\n',
        mode: FileMode.append,
      );

      final package = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );

      expect(
        package.exitCode,
        1,
        reason: '${package.stdout}\n${package.stderr}',
      );
      expect(
        package.stderr,
        contains('Framework-Managed Artifacts are stale or malformed'),
      );
      expect(package.stderr, startsWith('STALE_BUILD_ARTIFACTS:'));
      expect(package.stderr, contains('out/extension.dart.js'));
      expect(
        Directory(p.join(project.path, 'build')).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'package rejects XML-forbidden extension metadata',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_invalid_xml_',
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
      final descriptor = File(p.join(project.path, 'extension.dart'));
      descriptor.writeAsStringSync(
        descriptor.readAsStringSync().replaceFirst(
          'My Extension',
          r'My\u0001Extension',
        ),
      );
      final build = await Process.run(
        'dart',
        [executable, 'build'],
        workingDirectory: project.path,
      );
      expect(build.exitCode, 0, reason: '${build.stdout}\n${build.stderr}');

      final package = await Process.run(
        'dart',
        [executable, 'package'],
        workingDirectory: project.path,
      );

      expect(
        package.exitCode,
        1,
        reason: '${package.stdout}\n${package.stderr}',
      );
      expect(package.stderr, startsWith('INVALID_PROJECT_MANIFEST:'));
      expect(package.stderr, contains('displayName'));
      expect(package.stderr, contains('forbidden by XML 1.0'));
      expect(package.stderr, contains('extension.dart'));
      expect(
        File(
          p.join(project.path, 'build', 'my-extension-0.0.1.vsix'),
        ).existsSync(),
        isFalse,
      );
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );

  test(
    'package rejects artifacts built by a different framework toolchain',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_cli_toolchain_receipt_',
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
      final receiptFile = File(
        p.join(
          project.path,
          '.dart_tool',
          'flutter_vscode',
          'build.json',
        ),
      );
      final receipt =
          jsonDecode(await receiptFile.readAsString()) as Map<String, Object?>;
      // The framework digest is the only tool identity left: binding
      // generation is a dart_vscode maintainer operation, so a build has
      // no generator or pinned-input identity of its own.
      expect(receipt, isNot(contains('generatorSha256')));
      expect(receipt, isNot(contains('bindingInputsSha256')));
      const identities = <String, String>{
        'frameworkSha256': 'flutter_vscode framework changed since build',
      };

      for (final identity in identities.entries) {
        final original = receipt[identity.key];
        expect(
          original,
          isA<String>().having(
            (value) => value,
            identity.key,
            matches(RegExp(r'^[0-9a-f]{64}$')),
          ),
        );
        receipt[identity.key] = '0' * 64;
        await receiptFile.writeAsString(jsonEncode(receipt));

        final package = await Process.run(
          'dart',
          [executable, 'package'],
          workingDirectory: project.path,
        );

        expect(
          package.exitCode,
          1,
          reason: '${package.stdout}\n${package.stderr}',
        );
        expect(package.stderr, startsWith('STALE_BUILD_ARTIFACTS:'));
        expect(package.stderr, contains(identity.value));
        receipt[identity.key] = original;
        await receiptFile.writeAsString(jsonEncode(receipt));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
