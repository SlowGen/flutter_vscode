/// Safe file writer for deterministic Project-Derived Artifacts.
library;

import 'dart:io';

import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:path/path.dart' as p;

/// Writes [files] (project-relative POSIX path to contents) beneath
/// [outputRoot] in stable path order.
Future<void> writeProjectArtifacts(
  Map<String, String> files,
  Directory outputRoot,
) async {
  final rootPath = p.normalize(p.absolute(outputRoot.path));
  final rootType = FileSystemEntity.typeSync(rootPath, followLinks: false);
  if (rootType == FileSystemEntityType.notFound) {
    await _createRealOutputRoot(outputRoot, rootPath);
  } else if (rootType != FileSystemEntityType.directory) {
    throw CliException(
      'Generated output root must be a real directory: $rootPath.',
      code: 'UNSAFE_OUTPUT_PATH',
    );
  }
  final realRoot = outputRoot.resolveSymbolicLinksSync();
  final paths = files.keys.toList()..sort();
  for (final relativePath in paths) {
    if (p.isAbsolute(relativePath)) {
      throw CliException(
        'Generated output path must be relative: $relativePath.',
        code: 'INVALID_OUTPUT_PATH',
      );
    }
    final outputPath = p.normalize(p.join(rootPath, relativePath));
    if (!p.isWithin(rootPath, outputPath)) {
      throw CliException(
        'Generated output path escapes the output root: $relativePath.',
        code: 'INVALID_OUTPUT_PATH',
      );
    }
    _validateExistingOutputAncestors(
      rootPath: rootPath,
      realRoot: realRoot,
      relativePath: relativePath,
    );
  }
  for (final relativePath in paths) {
    final outputPath = p.normalize(p.join(rootPath, relativePath));
    final output = File(outputPath);
    await output.parent.create(recursive: true);
    await output.writeAsString(files[relativePath]!, flush: true);
  }
}

Future<void> _createRealOutputRoot(
  Directory outputRoot,
  String rootPath,
) async {
  var existingAncestor = p.dirname(rootPath);
  var ancestorType = FileSystemEntity.typeSync(
    existingAncestor,
    followLinks: false,
  );
  while (ancestorType == FileSystemEntityType.notFound) {
    final parent = p.dirname(existingAncestor);
    if (parent == existingAncestor) {
      break;
    }
    existingAncestor = parent;
    ancestorType = FileSystemEntity.typeSync(
      existingAncestor,
      followLinks: false,
    );
  }
  if (ancestorType != FileSystemEntityType.directory) {
    throw CliException(
      'Generated output root $rootPath has no real existing directory '
      'ancestor.',
      code: 'UNSAFE_OUTPUT_PATH',
    );
  }
  final realAncestor = Directory(existingAncestor).resolveSymbolicLinksSync();
  await outputRoot.create(recursive: true);
  if (FileSystemEntity.typeSync(rootPath, followLinks: false) !=
      FileSystemEntityType.directory) {
    throw CliException(
      'Generated output root was not created as a real directory: $rootPath.',
      code: 'UNSAFE_OUTPUT_PATH',
    );
  }
  final realRoot = outputRoot.resolveSymbolicLinksSync();
  if (realRoot != realAncestor && !p.isWithin(realAncestor, realRoot)) {
    throw CliException(
      'Generated output root resolves outside its existing directory '
      'ancestor: $rootPath.',
      code: 'UNSAFE_OUTPUT_PATH',
    );
  }
}

void _validateExistingOutputAncestors({
  required String rootPath,
  required String realRoot,
  required String relativePath,
}) {
  final segments = p.posix.split(relativePath);
  var current = rootPath;
  for (var index = 0; index < segments.length; index += 1) {
    current = p.join(current, segments[index]);
    final type = FileSystemEntity.typeSync(current, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      return;
    }
    if (type == FileSystemEntityType.link) {
      throw CliException(
        'Generated output $relativePath uses symbolic-link ancestor '
        '${p.relative(current, from: rootPath)}. Replace it with a real '
        'path inside the output root.',
        code: 'UNSAFE_OUTPUT_PATH',
      );
    }
    final isLast = index == segments.length - 1;
    if ((!isLast && type != FileSystemEntityType.directory) ||
        (isLast &&
            type != FileSystemEntityType.directory &&
            type != FileSystemEntityType.file)) {
      throw CliException(
        'Generated output $relativePath has an unsupported existing ancestor '
        '${p.relative(current, from: rootPath)}.',
        code: 'UNSAFE_OUTPUT_PATH',
      );
    }
    final resolved = type == FileSystemEntityType.directory
        ? Directory(current).resolveSymbolicLinksSync()
        : File(current).resolveSymbolicLinksSync();
    if (resolved != realRoot && !p.isWithin(realRoot, resolved)) {
      throw CliException(
        'Generated output $relativePath resolves outside $realRoot at '
        '${p.relative(current, from: rootPath)}.',
        code: 'UNSAFE_OUTPUT_PATH',
      );
    }
  }
}
