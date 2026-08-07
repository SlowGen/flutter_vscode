import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Repository-relative location of the deterministic build receipt.
const buildReceiptPath = '.dart_tool/flutter_vscode/build.json';

/// Digests every file beneath [relativePaths] in stable path order.
///
/// Directory inputs are recursive so newly added transitive tool sources
/// automatically change the identity instead of requiring a handwritten list
/// update.
Future<String> digestPackagePaths({
  required Directory packageRoot,
  required Iterable<String> relativePaths,
}) async {
  final files = <String, File>{};
  for (final relativePath in relativePaths.toSet().toList()..sort()) {
    final entityPath = p.joinAll([
      packageRoot.path,
      ...p.posix.split(relativePath),
    ]);
    final type = FileSystemEntity.typeSync(entityPath, followLinks: false);
    if (type == FileSystemEntityType.file) {
      files[_relativePackagePath(packageRoot, entityPath)] = File(entityPath);
      continue;
    }
    if (type == FileSystemEntityType.directory) {
      final entities = Directory(entityPath).listSync(
        recursive: true,
        followLinks: false,
      );
      for (final entity in entities) {
        if (entity is File) {
          files[_relativePackagePath(packageRoot, entity.path)] = entity;
        }
      }
      continue;
    }
    throw FileSystemException(
      'Build-tool identity input is missing or unsupported',
      entityPath,
    );
  }
  final components = <String>[];
  for (final relativePath in files.keys.toList()..sort()) {
    components.add(
      '$relativePath:${sha256.convert(await files[relativePath]!.readAsBytes())}',
    );
  }
  return sha256.convert(utf8.encode(components.join('\n'))).toString();
}

/// Records the exact inputs and Framework-Managed Artifacts from a build.
Future<void> writeBuildReceipt({
  required Directory projectRoot,
  required String apiTarget,
  required String frameworkSha256,
  required List<String> inputPaths,
  required List<String> artifactPaths,
}) async {
  final receipt = <String, Object?>{
    'schemaVersion': 3,
    'apiTarget': apiTarget,
    'frameworkSha256': frameworkSha256,
    'inputs': await _digests(projectRoot, inputPaths),
    'artifacts': await _digests(projectRoot, artifactPaths),
  };
  const encoder = JsonEncoder.withIndent('  ');
  final output = projectFile(projectRoot, buildReceiptPath);
  await output.parent.create(recursive: true);
  await output.writeAsString('${encoder.convert(receipt)}\n', flush: true);
}

/// Returns every reason the current project differs from its last build.
Future<List<String>> validateBuildReceipt({
  required Directory projectRoot,
  required String apiTarget,
  required String frameworkSha256,
  required List<String> inputPaths,
  required List<String> artifactPaths,
}) async {
  final receiptFile = projectFile(projectRoot, buildReceiptPath);
  if (!receiptFile.existsSync()) {
    return const ['$buildReceiptPath is missing'];
  }

  Object? decoded;
  try {
    decoded = jsonDecode(await receiptFile.readAsString());
  } on FormatException {
    return const ['$buildReceiptPath is not valid JSON'];
  }
  if (decoded is! Map<String, Object?> ||
      !_hasExactKeys(decoded, {
        'apiTarget',
        'artifacts',
        'frameworkSha256',
        'inputs',
        'schemaVersion',
      }) ||
      decoded['schemaVersion'] != 3 ||
      decoded['apiTarget'] != apiTarget ||
      !_isSha256(decoded['frameworkSha256']) ||
      decoded['inputs'] is! Map<String, Object?> ||
      decoded['artifacts'] is! Map<String, Object?>) {
    return const ['$buildReceiptPath has an unsupported structure'];
  }

  final problems = <String>[];
  if (decoded['frameworkSha256'] != frameworkSha256) {
    problems.add('flutter_vscode framework changed since build');
  }
  await _validateGroup(
    projectRoot: projectRoot,
    label: 'build input',
    recorded: decoded['inputs']! as Map<String, Object?>,
    currentPaths: inputPaths,
    problems: problems,
  );
  await _validateGroup(
    projectRoot: projectRoot,
    label: 'Framework-Managed Artifact',
    recorded: decoded['artifacts']! as Map<String, Object?>,
    currentPaths: artifactPaths,
    problems: problems,
  );
  return problems;
}

Future<Map<String, Object?>> _digests(
  Directory projectRoot,
  List<String> paths,
) async {
  final result = <String, Object?>{};
  for (final path in paths.toSet().toList()..sort()) {
    final file = projectFile(projectRoot, path);
    if (!file.existsSync()) {
      throw FileSystemException('Build receipt input is missing', file.path);
    }
    result[path] = await _digest(file);
  }
  return result;
}

Future<void> _validateGroup({
  required Directory projectRoot,
  required String label,
  required Map<String, Object?> recorded,
  required List<String> currentPaths,
  required List<String> problems,
}) async {
  final current = currentPaths.toSet();
  final previous = recorded.keys.toSet();
  for (final path in previous.difference(current).toList()..sort()) {
    problems.add('$label $path is missing');
  }
  for (final path in current.difference(previous).toList()..sort()) {
    problems.add('$label $path was added after build');
  }
  for (final path in current.intersection(previous).toList()..sort()) {
    final expected = recorded[path];
    if (expected is! String || !RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      problems.add('$label $path has an invalid recorded digest');
      continue;
    }
    final actual = await _digest(projectFile(projectRoot, path));
    if (actual != expected) {
      problems.add('$label $path changed after build');
    }
  }
}

Future<String> _digest(File file) async =>
    sha256.convert(await file.readAsBytes()).toString();

/// Resolves the project-relative POSIX path [relativePath] beneath [root].
File projectFile(Directory root, String relativePath) => File(
  p.joinAll([root.path, ...p.posix.split(relativePath)]),
);

String _relativePackagePath(Directory root, String path) =>
    p.relative(path, from: root.path).split(p.separator).join('/');

bool _hasExactKeys(Map<String, Object?> value, Set<String> expected) =>
    value.length == expected.length && value.keys.toSet().containsAll(expected);

bool _isSha256(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
