import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/repository.dart';

/// An Extension Project receives generated code, never framework source.
///
/// Everything the framework authors -- the view protocol, the command
/// registration module, the Flutter View host module, the generic runtime
/// helpers -- is library code and ships in `package:vscode_dart`, where the
/// analyzer and the formatter see it and its tests can address it directly.
/// What a project receives is only what is derived from that project: its
/// extension identifier, its collision-resistant global key, and the exports
/// bound to them.
void main() {
  /// Generated files whose contents depend on the project being built.
  const projectDerivedArtifacts = <String>{
    'host_exports.g.dart',
    'vscode_runtime.g.dart',
  };

  final builtProjects = <String>[
    'test/fixtures/host_extension',
    repoPath('extensions/pubspec_lens'),
    repoPath('extensions/coverage_treemap'),
  ];

  test('a built project receives only artifacts derived from itself', () {
    for (final project in builtProjects) {
      final generated = Directory(p.join(project, 'host', 'lib', 'generated'));
      expect(generated.existsSync(), isTrue, reason: project);

      final names = generated
          .listSync()
          .whereType<File>()
          .map((file) => p.basename(file.path))
          .toSet();

      expect(
        names,
        projectDerivedArtifacts,
        reason:
            '$project must carry no framework source: the protocol, the '
            'command module, and the Flutter View host module are libraries '
            'in package:vscode_dart, not files copied into every project',
      );
    }
  });

  test('no framework source is copied into a shared package', () {
    for (final project in builtProjects) {
      final shared = Directory(p.join(project, 'shared', 'lib', 'generated'));
      expect(
        shared.existsSync(),
        isFalse,
        reason:
            '$project must not receive a copy of the view protocol; both '
            'runtimes type against the one published library',
      );
    }
  });
}
