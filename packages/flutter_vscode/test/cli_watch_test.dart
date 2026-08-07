import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'build --watch rebuilds when a host source changes',
    () async {
      final workspace = await Directory.systemTemp.createTemp(
        'flutter_vscode_watch_',
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

      final watcher = await Process.start(
        'dart',
        [executable, 'build', '--watch'],
        workingDirectory: project.path,
      );
      addTearDown(watcher.kill);
      final stderrLines = <String>[];
      watcher.stderr
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(stderrLines.add);

      final builds = StreamController<String>.broadcast();
      watcher.stdout
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen((line) {
            if (line.startsWith('Built ')) {
              builds.add(line);
            }
          });

      await builds.stream.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () => fail(
          'The first watch build never completed.\n${stderrLines.join('\n')}',
        ),
      );

      final rebuild = builds.stream.first;
      File(
        p.join(project.path, 'shared', 'lib', 'shared.dart'),
      ).writeAsStringSync(
        "const helloMessage = 'Hello from the watcher';\n",
      );
      await rebuild.timeout(
        const Duration(minutes: 5),
        onTimeout: () => fail(
          'The watcher never rebuilt after a source change.\n'
          '${stderrLines.join('\n')}',
        ),
      );

      watcher.kill();
    },
    // The inner waits already fail with diagnostics at five minutes each;
    // the outer ceiling exists only as a backstop and must never be what
    // fires first. At twelve minutes it was exactly that: two five-minute
    // budgets plus a scaffold and two pub resolves under full-suite load
    // left no headroom, which is the recorded "contention flake" -- green
    // standalone, red under load, same mechanism as the error-code test's
    // thirty-second default.
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
