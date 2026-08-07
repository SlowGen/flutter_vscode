import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dart_vscode/contributions.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/doctor_command.dart';
import 'package:flutter_vscode/src/cli/packaging.dart';
import 'package:flutter_vscode/src/cli/project_layout.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:xml/xml.dart';

/// A-1: the deep CLI modules are callable in-process, without spawning the
/// `bin/flutter_vscode.dart` adapter as a subprocess.
void main() {
  group('packaging', () {
    test('content types cover defaults, extra extensions, and overrides', () {
      final contentTypes = contentTypesForParts([
        'extension.vsixmanifest',
        'extension/package.json',
        'extension/out/bootstrap.cjs',
        'extension/out/extension.dart.js',
        'extension/out/extension.dart.js.map',
        'extension/out/views/main/index.html',
        'extension/out/views/main/main.dart.wasm',
        'extension/out/views/main/assets/NOTICES',
      ]);

      expect(
        contentTypes,
        startsWith('<?xml version="1.0" encoding="utf-8"?>'),
      );
      expect(XmlDocument.parse(contentTypes).rootElement.name.local, 'Types');
      expect(
        contentTypes,
        contains('<Default Extension="vsixmanifest" ContentType="text/xml" />'),
      );
      expect(
        contentTypes,
        contains(
          '<Default Extension="json" ContentType="application/json" />',
        ),
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
          '<Override PartName="/extension/out/views/main/assets/NOTICES" '
          'ContentType="text/plain" />',
        ),
      );
    });

    test('VSIX validation accepts the exact assembled archive', () {
      final contents = _vsixContents();

      expect(
        () => validateAssembledVsix(_assembleVsix(contents), contents),
        returnsNormally,
      );
    });

    test('VSIX validation rejects tampered entry bytes', () {
      final contents = _vsixContents();
      final tampered = Map<String, List<int>>.of(contents)
        ..['extension/package.json'] = utf8.encode('{"name":"tampered"}\n');

      expect(
        () => validateAssembledVsix(_assembleVsix(tampered), contents),
        _throwsCliException('INVALID_VSIX'),
      );
    });

    test('VSIX validation rejects unexpected archive entries', () {
      final contents = _vsixContents();
      final extra = Map<String, List<int>>.of(contents)
        ..['extension/smuggled.txt'] = utf8.encode('smuggled\n');

      expect(
        () => validateAssembledVsix(_assembleVsix(extra), contents),
        _throwsCliException('INVALID_VSIX'),
      );
    });

    test('VSIX validation rejects compressed entries', () {
      final contents = _vsixContents();
      final archive = Archive();
      for (final path in contents.keys.toList()..sort()) {
        final bytes = contents[path]!;
        // Deflated instead of the required stored encoding.
        final file = ArchiveFile(path, bytes.length, bytes)..mode = 0x1a4;
        archive.addFile(file);
      }
      final bytes = ZipEncoder().encode(archive, modified: DateTime.utc(1980));

      expect(
        () => validateAssembledVsix(bytes, contents),
        _throwsCliException('INVALID_VSIX'),
      );
    });

    test('VSIX validation rejects malformed manifest XML', () {
      final contents = _vsixContents()
        ..['extension.vsixmanifest'] = utf8.encode('<PackageManifest');

      expect(
        () => validateAssembledVsix(_assembleVsix(contents), contents),
        _throwsCliException('INVALID_VSIX'),
      );
    });
  });

  group('project layout', () {
    test('accepts a scaffold-shaped Extension Project', () async {
      final root = await _scaffoldProject();

      expect(() => validateProjectLayout(root), returnsNormally);
      expect(missingRequiredProjectPaths(root), isEmpty);
    });

    test('rejects a symbolic-link escape with a real symlink', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_modules_layout_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final root = await _scaffoldProject(workspace: workspace);
      final outside = Directory(p.join(workspace.path, 'outside_lib'))
        ..createSync();
      final hostLib = Directory(p.join(root.path, 'host', 'lib'))
        ..deleteSync(recursive: true);
      await Link(hostLib.path).create(outside.path);

      expect(
        () => validateProjectLayout(root),
        _throwsCliException('UNSAFE_PROJECT_LAYOUT', containing: 'host/lib'),
      );
    });

    test('safe walks enumerate real files and reject symlinks', () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_modules_walk_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final tree = Directory(p.join(workspace.path, 'tree'))..createSync();
      File(p.join(tree.path, 'a.txt')).writeAsStringSync('a\n');
      Directory(p.join(tree.path, 'sub')).createSync();
      File(p.join(tree.path, 'sub', 'b.txt')).writeAsStringSync('b\n');
      Directory(p.join(tree.path, 'build')).createSync();
      File(p.join(tree.path, 'build', 'ignored.txt')).writeAsStringSync('x\n');

      final files = safeFiles(
        tree,
        description: 'module test tree',
        excludedTopLevelNames: const {'build'},
      );
      expect(
        files.map((file) => p.relative(file.path, from: tree.path)).toList(),
        [p.join('a.txt'), p.join('sub', 'b.txt')],
      );

      final outsideFile = File(p.join(workspace.path, 'outside.txt'))
        ..writeAsStringSync('outside\n');
      await Link(p.join(tree.path, 'linked.txt')).create(outsideFile.path);
      expect(
        () => safeFiles(tree, description: 'module test tree'),
        _throwsCliException(
          'UNSAFE_PROJECT_LAYOUT',
          containing: 'symbolic link',
        ),
      );
    });
  });

  group('baselines', () {
    test(
      'the baseline lives in dart_vscode and the framework carries none',
      () {
        expect(vscodeApiVersion, '1.129.1');
        // Binding generation is a dart_vscode maintainer operation: this
        // package must hold no generator, IR, or pinned inputs to read.
        expect(
          Directory(p.join('tool', 'bindings')).existsSync(),
          isFalse,
          reason: 'pinned binding inputs are dart_vscode maintainer state',
        );
        expect(
          Directory(p.join('tool', 'binding_generator')).existsSync(),
          isFalse,
          reason: 'the generator is dart_vscode maintainer tooling',
        );
      },
    );
  });

  group('host import boundary', () {
    test('the checker is CLI implementation, not a toolchain seam', () {
      // One adapter ever justified no seam: the BindingToolchain existed
      // only because the checker lived outside lib/. With the checker in
      // lib/src/cli the seam, its bin-side wiring shim, and the duplicate
      // exception type all fail the deletion test.
      expect(
        File(
          p.join('lib', 'src', 'cli', 'check_host_imports.dart'),
        ).existsSync(),
        isTrue,
        reason: 'the boundary checker is ordinary CLI implementation',
      );
      expect(
        File(
          p.join('lib', 'src', 'cli', 'binding_toolchain.dart'),
        ).existsSync(),
        isFalse,
        reason: 'the toolchain seam fails the deletion test',
      );
      expect(
        File(p.join('tool', 'check_host_imports.dart')).existsSync(),
        isFalse,
        reason: 'nothing under tool/ feeds the build path anymore',
      );
    });
  });

  group('doctor', () {
    test(
      'doctor and layout validation share one required-paths list',
      () async {
        for (final broken in requiredProjectPaths) {
          final root = await _scaffoldProject();
          final target = p.join(root.path, p.joinAll(p.posix.split(broken)));
          if (FileSystemEntity.typeSync(target) ==
              FileSystemEntityType.directory) {
            Directory(target).deleteSync(recursive: true);
          } else {
            File(target).deleteSync();
          }

          final missing = missingRequiredProjectPaths(root);
          expect(missing, contains(broken), reason: broken);

          final out = StringBuffer();
          final failures = await doctorProject(
            root,
            out: out,
            probeTool: (executable) async => (true, 'stubbed $executable'),
            packageRoot: Directory.current,
          );
          final report = out.toString();
          expect(failures, greaterThan(0), reason: broken);
          expect(report, contains('[!!] Project layout'), reason: broken);
          for (final path in missing) {
            expect(report, contains(path), reason: broken);
          }
        }
      },
    );

    test(
      'doctor reports the shared validator verdict on unsafe layouts',
      () async {
        final workspace = await Directory.systemTemp.createTemp(
          'flutter_vscode_modules_doctor_',
        );
        addTearDown(() => workspace.delete(recursive: true));
        final root = await _scaffoldProject(workspace: workspace);
        final outside = Directory(p.join(workspace.path, 'outside_views'))
          ..createSync();
        final views = Directory(p.join(root.path, 'views'))..deleteSync();
        await Link(views.path).create(outside.path);

        final out = StringBuffer();
        final failures = await doctorProject(
          root,
          out: out,
          probeTool: (executable) async => (true, 'stubbed $executable'),
          packageRoot: Directory.current,
        );

        expect(failures, greaterThan(0));
        final report = out.toString();
        expect(report, contains('[!!] Project layout'));
        expect(report, contains('symbolic-link'));
      },
    );

    test('doctor passes a healthy scaffold with stubbed tools', () async {
      final root = await _scaffoldProject();

      final out = StringBuffer();
      final failures = await doctorProject(
        root,
        out: out,
        probeTool: (executable) async => (true, 'stubbed $executable'),
        packageRoot: Directory.current,
      );

      expect(failures, 0, reason: out.toString());
      final report = out.toString();
      expect(report, contains('[ok] Project layout'));
      expect(
        report,
        contains('[ok] VS Code baseline $vscodeApiVersion'),
      );
      expect(report, contains('No issues found.'));
    });
  });
}

/// Builds the exact stored-entry archive the packaging module emits.
List<int> _assembleVsix(Map<String, List<int>> contents) {
  final archive = Archive();
  for (final path in contents.keys.toList()..sort()) {
    final bytes = contents[path]!;
    final file = ArchiveFile.noCompress(path, bytes.length, bytes)
      ..mode = 0x1a4;
    archive.addFile(file);
  }
  return ZipEncoder().encode(archive, modified: DateTime.utc(1980));
}

Map<String, List<int>> _vsixContents() {
  final parts = [
    'extension/package.json',
    'extension/out/bootstrap.cjs',
  ];
  const manifest =
      '<?xml version="1.0" encoding="utf-8"?>\n'
      '<PackageManifest Version="2.0.0" />\n';
  return <String, List<int>>{
    '[Content_Types].xml': utf8.encode(
      contentTypesForParts(['extension.vsixmanifest', ...parts]),
    ),
    'extension.vsixmanifest': utf8.encode(manifest),
    'extension/package.json': utf8.encode('{"name":"my-extension"}\n'),
    'extension/out/bootstrap.cjs': utf8.encode('// bootstrap\n'),
  };
}

/// Creates a scaffold-shaped Extension Project without running the CLI.
Future<Directory> _scaffoldProject({Directory? workspace}) async {
  final parent =
      workspace ??
      await Directory.systemTemp.createTemp('flutter_vscode_modules_project_');
  if (workspace == null) {
    addTearDown(() => parent.delete(recursive: true));
  }
  final root = Directory(p.join(parent.path, 'my_extension'))..createSync();
  Directory(p.join(root.path, 'host', 'lib')).createSync(recursive: true);
  Directory(p.join(root.path, 'shared', 'lib')).createSync(recursive: true);
  Directory(p.join(root.path, 'views')).createSync();
  File(p.join(root.path, 'extension.dart')).writeAsStringSync('''
import 'package:flutter_vscode/manifest.dart';

const extension = ExtensionManifest(
  name: 'my-extension',
  displayName: 'My Extension',
  description: 'A VS Code extension written in Dart.',
  version: '0.0.1',
  publisher: 'local',
  activationEvents: [],
);
''');
  File(
    p.join(root.path, 'host', 'lib', 'extension.dart'),
  ).writeAsStringSync('void main() {}\n');
  File(
    p.join(root.path, 'shared', 'lib', 'shared.dart'),
  ).writeAsStringSync("const helloMessage = 'Hello from Dart';\n");
  return root;
}

Matcher _throwsCliException(String code, {String? containing}) => throwsA(
  isA<CliException>()
      .having((error) => error.code, 'code', code)
      .having(
        (error) => error.message,
        'message',
        containing == null ? isNotEmpty : contains(containing),
      ),
);
