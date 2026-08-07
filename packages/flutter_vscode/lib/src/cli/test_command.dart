import 'dart:io';

import 'package:flutter_vscode/src/cli/project_layout.dart';
import 'package:path/path.dart' as p;

/// Runs every discovered test suite in the Extension Project at [root].
///
/// Returns the number of failed suites; the process adapter maps a nonzero
/// count to exit code 1.
Future<int> testProject(Directory root) async {
  validateProjectLayout(root);
  final suites = <(String, Directory, String)>[];
  final shared = Directory(p.join(root.path, 'shared'));
  if (Directory(p.join(shared.path, 'test')).existsSync()) {
    suites.add(('shared', shared, 'dart'));
  }
  final host = Directory(p.join(root.path, 'host'));
  if (Directory(p.join(host.path, 'test')).existsSync()) {
    suites.add(('host', host, 'dart'));
  }
  for (final view in discoverViews(root)) {
    if (Directory(p.join(view.root.path, 'test')).existsSync()) {
      suites.add(('views/${view.name}', view.root, 'flutter'));
    }
  }
  if (suites.isEmpty) {
    stdout.writeln(
      'No test suites found. Add tests under shared/test, host/test, or '
      'views/<name>/test.',
    );
    return 0;
  }
  var failures = 0;
  for (final (label, directory, tool) in suites) {
    stdout.writeln('--- $label');
    final resolve = await Process.run(
      tool,
      const ['pub', 'get'],
      workingDirectory: directory.path,
    );
    if (resolve.exitCode != 0) {
      stdout
        ..write(resolve.stdout)
        ..write(resolve.stderr);
      failures += 1;
      continue;
    }
    final run = await Process.run(
      tool,
      const ['test'],
      workingDirectory: directory.path,
    );
    stdout
      ..write(run.stdout)
      ..write(run.stderr);
    if (run.exitCode != 0) {
      failures += 1;
    }
  }
  if (failures == 0) {
    stdout.writeln('All suites passed.');
  } else {
    stdout.writeln('$failures suite(s) failed.');
  }
  return failures;
}
