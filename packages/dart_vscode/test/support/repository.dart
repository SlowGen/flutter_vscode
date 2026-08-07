import 'dart:io';

import 'package:path/path.dart' as p;

/// The repository root of this checkout.
///
/// Tests run with `packages/dart_vscode` as the working directory, but
/// plenty of what they assert about lives above it: the gate scripts, the
/// docs and specs, the shipped example extensions, the CI workflow, and the
/// pub workspace's single `.dart_tool/package_config.json`. Resolving the
/// root by walking up to the workspace manifest keeps those references
/// correct no matter which directory a runner starts in.
final Directory repositoryRoot = _findRepositoryRoot();

/// Joins [relative] onto [repositoryRoot].
String repoPath(String relative) => p.join(repositoryRoot.path, relative);

Directory _findRepositoryRoot() {
  for (var directory = Directory.current; ; directory = directory.parent) {
    final manifest = File(p.join(directory.path, 'pubspec.yaml'));
    if (manifest.existsSync() &&
        manifest.readAsStringSync().contains('\nworkspace:')) {
      return directory;
    }
    if (p.equals(directory.path, directory.parent.path)) {
      throw StateError(
        'No pub workspace root above ${Directory.current.path}; tests locate '
        'repository-level files relative to it.',
      );
    }
  }
}
