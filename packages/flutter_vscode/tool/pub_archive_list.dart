// Prints the exact file list `dart pub publish` would archive, one
// repository-relative path per line, by parsing pub's own dry-run tree.
// The packaged E2E stages the framework from this list so installed
// coverage runs against pub's real file selection, not an approximation.
import 'dart:convert';
import 'dart:io';

Future<void> main() async {
  final result = await Process.run('dart', [
    'pub',
    'publish',
    '--dry-run',
    '--ignore-warnings',
  ]);
  if (result.exitCode != 0) {
    stderr
      ..writeln('dart pub publish --dry-run failed:')
      ..writeln(result.stderr);
    exitCode = 1;
    return;
  }
  final lines = const LineSplitter().convert(result.stdout as String);
  final entryPattern = RegExp(
    r'^((?:(?:│   )|(?:    ))*)[├└]── (.+?)( \([^()]+\))?$',
  );
  final directoryStack = <String>[];
  var sawTree = false;
  var emitted = 0;
  for (final line in lines) {
    final match = entryPattern.firstMatch(line);
    if (match == null) {
      if (sawTree) {
        break;
      }
      continue;
    }
    sawTree = true;
    final depth = match.group(1)!.length ~/ 4;
    final name = match.group(2)!;
    final isFile = match.group(3) != null;
    while (directoryStack.length > depth) {
      directoryStack.removeLast();
    }
    if (isFile) {
      stdout.writeln([...directoryStack, name].join('/'));
      emitted += 1;
    } else {
      directoryStack.add(name);
    }
  }
  if (!sawTree || emitted == 0) {
    stderr.writeln('No archive tree found in pub output.');
    exitCode = 1;
  }
}
