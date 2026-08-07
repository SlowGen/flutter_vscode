import 'dart:io';

import 'package:dart_vscode/contributions.dart';
import 'package:flutter_vscode/src/cli/build_command.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/create_command.dart';
import 'package:flutter_vscode/src/cli/doctor_command.dart';
import 'package:flutter_vscode/src/cli/packaging.dart';
import 'package:flutter_vscode/src/cli/test_command.dart';
import 'package:flutter_vscode/src/cli/watch_command.dart';
import 'package:path/path.dart' as p;

Future<void> main(List<String> arguments) async {
  try {
    switch (arguments) {
      case ['create', final name]:
        await createProject(Directory.current, name);
      case ['build']:
        await buildProject(Directory.current);
      case ['build', '--watch']:
        await buildWatch(Directory.current);
      case ['package']:
        await packageProject(Directory.current);
      case ['doctor']:
        if (await doctorProject(Directory.current) != 0) {
          exitCode = 1;
        }
      case ['test']:
        if (await testProject(Directory.current) != 0) {
          exitCode = 1;
        }
      default:
        throw const CliException(
          'Usage: flutter_vscode '
          '<create <project_name>|build [--watch]|package|doctor|test>',
          code: 'INVALID_USAGE',
          exitCode: 64,
        );
    }
  } on CliException catch (error) {
    stderr.writeln('${error.code}: ${error.message}');
    exitCode = error.exitCode;
  } on ContributionException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on HostDartSyntaxException catch (error) {
    final source = p
        .relative(error.path, from: Directory.current.path)
        .split(p.separator)
        .join('/');
    stderr.writeln(
      'INVALID_HOST_DART: $source:${error.line}:${error.column}: '
      '${error.message} Fix the Dart syntax and rerun flutter_vscode build.',
    );
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('INVALID_PROJECT_DATA: Invalid project data: $error');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln(
      'FILE_SYSTEM_ERROR: File system error: ${error.message} (${error.path})',
    );
    exitCode = 1;
  } on ProcessException catch (error) {
    stderr.writeln(
      'TOOL_COMMAND_START_FAILED: Could not start ${error.executable}: '
      '${error.message}',
    );
    exitCode = 1;
  }
}
