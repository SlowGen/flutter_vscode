import 'dart:io';

import 'package:dart_vscode/contributions.dart';
import 'package:flutter_vscode/src/cli/baselines.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/json_object.dart';
import 'package:flutter_vscode/src/cli/project_descriptor.dart';
import 'package:flutter_vscode/src/cli/project_layout.dart';
import 'package:path/path.dart' as p;

/// Probes one toolchain [executable], returning health and a detail line.
typedef DoctorToolProbe = Future<(bool, String?)> Function(String executable);

/// Diagnoses the toolchain and the Extension Project at [root].
///
/// Writes `[ok]`/`[!!]` report lines to [out] (standard output by default)
/// and returns the number of failed checks. The project-layout check reuses
/// [requiredProjectPaths] and [validateProjectLayout] so `doctor` and the
/// build-time validator can never disagree about what a project needs.
/// [packageRoot] overrides the installed `dart_vscode` resolution for
/// callers (such as in-process tests) whose runtime cannot resolve
/// package URIs.
Future<int> doctorProject(
  Directory root, {
  StringSink? out,
  DoctorToolProbe? probeTool,
  Directory? packageRoot,
}) async {
  final sink = out ?? stdout;
  final probe = probeTool ?? _probeToolVersion;
  final checks = <(String, bool, String?)>[];

  Future<void> checkTool(String label, String executable) async {
    final (ok, detail) = await probe(executable);
    checks.add((label, ok, detail));
  }

  await checkTool('Dart SDK', 'dart');
  await checkTool('Flutter SDK', 'flutter');

  final dartDescriptor = File(p.join(root.path, 'extension.dart'));
  final jsonDescriptor = File(p.join(root.path, 'extension.json'));
  final insideProject =
      dartDescriptor.existsSync() || jsonDescriptor.existsSync();
  if (insideProject) {
    final missing = missingRequiredProjectPaths(root);
    if (missing.isNotEmpty) {
      checks.add(
        (
          'Project layout',
          false,
          'missing ${missing.join(', ')} — run flutter_vscode create for a '
              'reference layout',
        ),
      );
    } else {
      try {
        validateProjectLayout(root);
        checks.add(('Project layout', true, null));
      } on CliException catch (error) {
        checks.add(('Project layout', false, error.message));
      }
    }
    try {
      // Parsing is the check: a malformed descriptor reports below.
      if (dartDescriptor.existsSync()) {
        await readProjectDescriptor(dartDescriptor);
      } else {
        await readJsonObject(jsonDescriptor);
      }
      // The baseline ships inside package:dart_vscode: resolving that
      // package proves the generated API layer for the pinned VS Code is
      // on the build path. No binding inputs exist at author time.
      final frameworkRoot = packageRoot ?? await resolveDartVscodeRoot();
      checks.add(
        (
          'VS Code baseline $vscodeApiVersion',
          frameworkRoot.existsSync(),
          frameworkRoot.existsSync()
              ? null
              : 'the dart_vscode package did not resolve to a directory',
        ),
      );
    } on Object catch (error) {
      checks.add(('Project descriptor', false, '$error'));
    }
  }

  var failures = 0;
  for (final (label, ok, detail) in checks) {
    final suffix = detail == null || detail.isEmpty ? '' : ': $detail';
    sink.writeln('${ok ? '[ok]' : '[!!]'} $label$suffix');
    if (!ok) {
      failures += 1;
    }
  }
  if (!insideProject) {
    sink.writeln(
      'This directory is not an Extension Project (no extension.dart); '
      'toolchain checks only.',
    );
  }
  if (failures == 0) {
    sink.writeln('No issues found.');
  } else {
    sink.writeln('$failures issue(s) found.');
  }
  return failures;
}

Future<(bool, String?)> _probeToolVersion(String executable) async {
  try {
    final result = await Process.run(executable, const ['--version']);
    final banner = '${result.stdout}${result.stderr}'
        .trim()
        .split('\n')
        .first
        .trim();
    return (result.exitCode == 0, banner);
  } on ProcessException {
    return (false, 'not found on PATH');
  }
}
