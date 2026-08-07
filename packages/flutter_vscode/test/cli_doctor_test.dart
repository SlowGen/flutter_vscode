import 'dart:io';

import 'package:dart_vscode/contributions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<ProcessResult> _cli(
  List<String> arguments, {
  required String workingDirectory,
}) {
  final executable = p.join(
    Directory.current.path,
    'bin',
    'flutter_vscode.dart',
  );
  return Process.run(
    'dart',
    [executable, ...arguments],
    workingDirectory: workingDirectory,
  );
}

Future<Directory> _createProject(Directory workspace) async {
  final create = await _cli(
    ['create', 'my_extension'],
    workingDirectory: workspace.path,
  );
  expect(create.exitCode, 0, reason: '${create.stdout}\n${create.stderr}');
  return Directory(p.join(workspace.path, 'my_extension'));
}

void main() {
  test(
    'doctor reports a healthy toolchain and project',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_doctor_ok_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final project = await _createProject(workspace);

      final doctor = await _cli(['doctor'], workingDirectory: project.path);

      expect(doctor.exitCode, 0, reason: '${doctor.stdout}\n${doctor.stderr}');
      final output = '${doctor.stdout}';
      expect(output, contains('[ok] Dart SDK'));
      expect(output, contains('[ok] Flutter SDK'));
      expect(output, contains('[ok] Project layout'));
      expect(output, contains('[ok] VS Code baseline $vscodeApiVersion'));
      expect(output, contains('No issues found'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'doctor fails actionably on a broken project layout',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_doctor_broken_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final project = await _createProject(workspace);
      Directory(p.join(project.path, 'host')).deleteSync(recursive: true);

      final doctor = await _cli(['doctor'], workingDirectory: project.path);

      expect(doctor.exitCode, 1, reason: '${doctor.stdout}\n${doctor.stderr}');
      final output = '${doctor.stdout}';
      expect(output, contains('[!!] Project layout'));
      expect(output, contains('host'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'doctor accepts a json-descriptor project',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_doctor_json_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final project = await _createProject(workspace);
      // Convert the scaffold to the json descriptor form.
      File(p.join(project.path, 'extension.dart')).deleteSync();
      File(p.join(project.path, 'extension.json')).writeAsStringSync('''
{
  "schemaVersion": 1,
  "name": "my-extension",
  "displayName": "My Extension",
  "description": "A VS Code extension written in Dart.",
  "version": "0.0.1",
  "publisher": "local",
  "activationEvents": ["onLanguage:json"],
  "commands": [
    {"command": "my-extension.hello", "title": "Say Hello from Dart"}
  ]
}
''');

      final doctor = await _cli(['doctor'], workingDirectory: project.path);

      expect(doctor.exitCode, 0, reason: '${doctor.stdout}\n${doctor.stderr}');
      expect(
        '${doctor.stdout}',
        contains('[ok] VS Code baseline $vscodeApiVersion'),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'doctor outside a project checks the toolchain only',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_doctor_outside_',
      );
      addTearDown(() => workspace.delete(recursive: true));

      final doctor = await _cli(['doctor'], workingDirectory: workspace.path);

      expect(doctor.exitCode, 0, reason: '${doctor.stdout}\n${doctor.stderr}');
      final output = '${doctor.stdout}';
      expect(output, contains('[ok] Dart SDK'));
      expect(output, contains('not an Extension Project'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'test runs the shared suite and fails on a failing test',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_test_cmd_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final project = await _createProject(workspace);
      final sharedTests = Directory(p.join(project.path, 'shared', 'test'))
        ..createSync(recursive: true);
      File(p.join(project.path, 'shared', 'pubspec.yaml')).writeAsStringSync('''
name: my_extension_shared
publish_to: none

environment:
  sdk: ^3.12.0

dev_dependencies:
  test: ^1.25.0
''');
      final sharedTest = File(p.join(sharedTests.path, 'shared_test.dart'))
        ..writeAsStringSync('''
import 'package:test/test.dart';

void main() {
  test('passes', () {});
}
''');

      final passing = await _cli(['test'], workingDirectory: project.path);
      expect(
        passing.exitCode,
        0,
        reason: '${passing.stdout}\n${passing.stderr}',
      );
      expect('${passing.stdout}', contains('shared'));

      sharedTest.writeAsStringSync('''
import 'package:test/test.dart';

void main() {
  test('fails', () => fail('boom'));
}
''');
      final failing = await _cli(['test'], workingDirectory: project.path);
      expect(
        failing.exitCode,
        1,
        reason: '${failing.stdout}\n${failing.stderr}',
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );

  test(
    'test reports when a project has no suites',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_test_none_',
      );
      addTearDown(() => workspace.delete(recursive: true));
      final project = await _createProject(workspace);

      final result = await _cli(['test'], workingDirectory: project.path);

      expect(result.exitCode, 0, reason: '${result.stdout}\n${result.stderr}');
      expect('${result.stdout}', contains('No test suites found'));
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
