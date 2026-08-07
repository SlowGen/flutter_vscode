import 'dart:io';

import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:path/path.dart' as p;

/// A discovered Flutter View beneath an Extension Project's `views/` root.
final class FlutterView {
  /// Creates a view named [name] rooted at [root].
  const FlutterView(this.name, this.root);

  /// The view's directory name (lowercase_with_underscores).
  final String name;

  /// The view package's root directory.
  final Directory root;
}

/// The paths every Extension Project must contain.
///
/// This is the single required-paths source of truth: `doctor` reports
/// missing entries from this list and layout validation guards the same
/// tree, so the two can never drift apart.
const List<String> requiredProjectPaths = [
  'host',
  'host/lib',
  'host/lib/extension.dart',
  'shared',
  'shared/lib',
  'views',
];

/// Returns the [requiredProjectPaths] entries missing beneath [root].
List<String> missingRequiredProjectPaths(Directory root) => [
  for (final relative in requiredProjectPaths)
    if (FileSystemEntity.typeSync(p.join(root.path, relative)) ==
        FileSystemEntityType.notFound)
      relative,
];

/// Validates that every managed path beneath [root] is a real, in-tree
/// file-system entry before the toolchain reads or replaces it.
void validateProjectLayout(Directory root) {
  validateRealProjectPaths(
    root,
    const [
      'host',
      'host/lib',
      'host/lib/generated',
      'host/.dart_tool',
      'shared',
      'shared/lib',
      'shared/lib/generated',
      'shared/.dart_tool',
      'views',
      'out',
      'build',
      '.dart_tool',
      '.dart_tool/flutter_vscode',
      '.vscode',
    ],
    allowFinalFile: false,
  );
  validateRealProjectPaths(
    root,
    const [
      '.dart_tool/flutter_vscode/build.json',
      '.vscode/launch.json',
      'coverage.json',
      'host/.dart_tool/flutter_vscode_package_config.json',
      'host/.dart_tool/package_config.json',
      'host/bootstrap.cjs',
      'package.json',
    ],
    allowFinalFile: true,
  );
}

/// Validates the managed directories of every discovered Flutter [views].
void validateFlutterViewLayout(Directory root, List<FlutterView> views) {
  validateRealProjectPaths(
    root,
    [
      for (final view in views) ...[
        'views/${view.name}',
        'views/${view.name}/lib',
        'views/${view.name}/.dart_tool',
        'views/${view.name}/build',
        'out/views/${view.name}',
      ],
    ],
    allowFinalFile: false,
  );
}

/// Validates that each of [relativePaths] beneath [root] uses only real
/// directories (and, when [allowFinalFile] is set, a regular target file)
/// resolving inside the Extension Project.
void validateRealProjectPaths(
  Directory root,
  Iterable<String> relativePaths, {
  required bool allowFinalFile,
}) {
  final rootPath = p.normalize(p.absolute(root.path));
  if (FileSystemEntity.typeSync(rootPath, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw CliException(
      'Extension Project root must be a real directory: $rootPath.',
      code: 'UNSAFE_PROJECT_LAYOUT',
    );
  }
  final realRoot = Directory(rootPath).resolveSymbolicLinksSync();
  for (final relativePath in relativePaths) {
    final segments = p.posix.split(relativePath);
    var current = rootPath;
    for (var index = 0; index < segments.length; index += 1) {
      final segment = segments[index];
      current = p.join(current, segment);
      final type = FileSystemEntity.typeSync(current, followLinks: false);
      if (type == FileSystemEntityType.notFound) {
        break;
      }
      if (type == FileSystemEntityType.link) {
        throw CliException(
          '$relativePath must not use a symbolic-link ancestor: '
          '${p.relative(current, from: rootPath)}. Remove the link and use '
          'a real directory inside the Extension Project.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
      final isLast = index == segments.length - 1;
      final validType = allowFinalFile && isLast
          ? type == FileSystemEntityType.file
          : type == FileSystemEntityType.directory;
      if (!validType) {
        throw CliException(
          '$relativePath has an unsafe existing entry at '
          '${p.relative(current, from: rootPath)}. Use real directories and '
          '${allowFinalFile ? 'a regular target file' : 'a real directory'}.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
      final realCurrent = type == FileSystemEntityType.directory
          ? Directory(current).resolveSymbolicLinksSync()
          : File(current).resolveSymbolicLinksSync();
      if (realCurrent != realRoot && !p.isWithin(realRoot, realCurrent)) {
        throw CliException(
          '$relativePath resolves outside the Extension Project at '
          '${p.relative(current, from: rootPath)}. Move it inside '
          '$rootPath.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
    }
  }
}

/// Discovers the Flutter Views beneath [root]'s `views/` directory.
List<FlutterView> discoverViews(Directory root) {
  final viewsRoot = Directory(p.join(root.path, 'views'));
  final rootType = FileSystemEntity.typeSync(
    viewsRoot.path,
    followLinks: false,
  );
  if (rootType == FileSystemEntityType.notFound) {
    return const [];
  }
  if (rootType != FileSystemEntityType.directory) {
    throw const CliException(
      'views must be a real directory, not a file or symbolic link.',
      code: 'INVALID_FLUTTER_VIEW',
    );
  }
  final entities = viewsRoot.listSync(followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  final views = <FlutterView>[];
  for (final entity in entities) {
    final name = p.basename(entity.path);
    final type = FileSystemEntity.typeSync(entity.path, followLinks: false);
    if (type != FileSystemEntityType.directory ||
        !RegExp(r'^[a-z][a-z0-9_]*$').hasMatch(name)) {
      throw CliException(
        'Malformed Flutter View views/$name. View names must use '
        'lowercase_with_underscores and each direct child of views must be a '
        'real directory.',
        code: 'INVALID_FLUTTER_VIEW',
      );
    }
    final view = FlutterView(name, Directory(entity.path));
    for (final requiredPath in ['pubspec.yaml', 'lib/main.dart']) {
      final file = File(p.join(view.root.path, requiredPath));
      if (FileSystemEntity.typeSync(file.path, followLinks: false) !=
          FileSystemEntityType.file) {
        throw CliException(
          'Malformed Flutter View views/$name: $requiredPath must be a real '
          'file.',
          code: 'INVALID_FLUTTER_VIEW',
        );
      }
    }
    safeFiles(
      view.root,
      description: 'Flutter View $name source tree',
      excludedTopLevelNames: const {'.dart_tool', 'build'},
    );
    views.add(view);
  }
  return views;
}

/// Walks [root] and returns every regular file in stable path order,
/// rejecting symbolic links, path escapes, and unsupported entries.
///
/// Top-level entries named in [excludedTopLevelNames] are skipped.
List<File> safeFiles(
  Directory root, {
  required String description,
  Set<String> excludedTopLevelNames = const {},
}) {
  final rootPath = p.normalize(p.absolute(root.path));
  if (FileSystemEntity.typeSync(rootPath, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw CliException(
      '$description must be a real directory.',
      code: 'UNSAFE_PROJECT_LAYOUT',
    );
  }
  final files = <File>[];

  void visit(Directory directory) {
    final entities = directory.listSync(followLinks: false)
      ..sort((left, right) => left.path.compareTo(right.path));
    for (final entity in entities) {
      final normalized = p.normalize(p.absolute(entity.path));
      if (!p.isWithin(rootPath, normalized)) {
        throw CliException(
          '$description contains a path escape.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
      final relative = p.relative(normalized, from: rootPath);
      final segments = p.split(relative);
      if (segments.length == 1 &&
          excludedTopLevelNames.contains(segments.single)) {
        continue;
      }
      if (segments.any(
        (segment) =>
            segment.isEmpty ||
            segment == '.' ||
            segment == '..' ||
            segment.contains(r'\'),
      )) {
        throw CliException(
          '$description contains an unsafe path: $relative.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
      final type = FileSystemEntity.typeSync(normalized, followLinks: false);
      if (type == FileSystemEntityType.link) {
        throw CliException(
          '$description contains a symbolic link: $relative.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
      if (type == FileSystemEntityType.directory) {
        visit(Directory(normalized));
      } else if (type == FileSystemEntityType.file) {
        files.add(File(normalized));
      } else {
        throw CliException(
          '$description contains an unsupported file-system entry: $relative.',
          code: 'UNSAFE_PROJECT_LAYOUT',
        );
      }
    }
  }

  visit(Directory(rootPath));
  return files;
}

/// Returns the validated build-output files for every discovered view.
///
/// Host-Only Extensions must have no `out/views` tree at all; view-bearing
/// projects must have exactly one real output directory per view.
List<File> viewOutputFiles(Directory root, List<FlutterView> views) {
  final outputRoot = Directory(p.join(root.path, 'out', 'views'));
  if (views.isEmpty) {
    if (FileSystemEntity.typeSync(outputRoot.path, followLinks: false) !=
        FileSystemEntityType.notFound) {
      throw const CliException(
        'Host-Only Extension output unexpectedly contains out/views.',
        code: 'INVALID_VIEW_OUTPUT',
      );
    }
    return const [];
  }
  if (FileSystemEntity.typeSync(outputRoot.path, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw const CliException(
      'Flutter View build output out/views is missing or malformed.',
      code: 'INVALID_VIEW_OUTPUT',
    );
  }
  final expectedNames = views.map((view) => view.name).toSet();
  final entities = outputRoot.listSync(followLinks: false)
    ..sort((left, right) => left.path.compareTo(right.path));
  final actualNames = <String>{};
  final files = <File>[];
  for (final entity in entities) {
    final name = p.basename(entity.path);
    if (FileSystemEntity.typeSync(entity.path, followLinks: false) !=
            FileSystemEntityType.directory ||
        !expectedNames.contains(name) ||
        !actualNames.add(name)) {
      throw CliException(
        'Flutter View output contains an unexpected or malformed entry: '
        'out/views/$name.',
        code: 'INVALID_VIEW_OUTPUT',
      );
    }
    files.addAll(
      safeFiles(
        Directory(entity.path),
        description: 'Flutter View $name output tree',
      ),
    );
  }
  // The loop above admits only expected names, so subset is guaranteed
  // and equality reduces to cardinality.
  if (actualNames.length != expectedNames.length) {
    final missing = expectedNames.difference(actualNames).toList()..sort();
    throw CliException(
      'Flutter View output is missing: ${missing.join(', ')}.',
      code: 'INVALID_VIEW_OUTPUT',
    );
  }
  files.sort((left, right) => left.path.compareTo(right.path));
  return files;
}

/// Returns [file]'s path relative to [root] with POSIX separators.
String relativeProjectPath(Directory root, File file) =>
    p.relative(file.path, from: root.path).split(p.separator).join('/');
