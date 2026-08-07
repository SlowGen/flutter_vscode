import 'dart:async';
import 'dart:io';

import 'package:flutter_vscode/src/cli/build_command.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/project_layout.dart';
import 'package:path/path.dart' as p;

/// Rebuilds the Extension Project at [root] whenever its sources change.
///
/// Runs until the process is interrupted; the returned future never
/// completes.
Future<void> buildWatch(Directory root) async {
  Future<void> buildOnce() async {
    try {
      await buildProject(root);
    } on CliException catch (error) {
      stderr.writeln('${error.code}: ${error.message}');
    } on HostDartSyntaxException catch (error) {
      final source = p
          .relative(error.path, from: root.path)
          .split(p.separator)
          .join('/');
      stderr.writeln(
        'INVALID_HOST_DART: $source:${error.line}:${error.column}: '
        '${error.message}',
      );
    } on Object catch (error) {
      stderr.writeln('WATCH_BUILD_FAILED: $error');
    }
  }

  await buildOnce();
  stdout.writeln('Watching for changes; press Ctrl+C to stop.');

  bool relevant(FileSystemEvent event) {
    final path = event.path;
    final separator = p.separator;
    if (path.contains('$separator.dart_tool') ||
        path.contains('${separator}generated$separator') ||
        path.endsWith('${separator}generated') ||
        path.contains('${separator}out$separator') ||
        path.contains('${separator}build$separator')) {
      return false;
    }
    return true;
  }

  final events = StreamController<FileSystemEvent>();
  void watchTree(String path) {
    final directory = Directory(path);
    if (directory.existsSync()) {
      directory.watch(recursive: true).listen(events.add);
    }
  }

  watchTree(p.join(root.path, 'host', 'lib'));
  watchTree(p.join(root.path, 'shared', 'lib'));
  for (final view in discoverViews(root)) {
    watchTree(p.join(view.root.path, 'lib'));
  }
  root
      .watch()
      .where((event) {
        final name = p.basename(event.path);
        return name == 'extension.dart' || name == 'extension.json';
      })
      .listen(events.add);

  var pending = false;
  var running = false;
  Future<void> schedule() async {
    pending = true;
    if (running) {
      return;
    }
    running = true;
    while (pending) {
      pending = false;
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await buildOnce();
    }
    running = false;
  }

  events.stream.where(relevant).listen((_) => unawaited(schedule()));
  await Completer<void>().future;
}
