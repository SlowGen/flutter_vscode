import 'dart:io';

import 'package:flutter_vscode/src/cli/build_receipt.dart';
import 'package:flutter_vscode/src/cli/project_layout.dart';

/// Enumerates the author-owned inputs a build reads, in stable order.
///
/// [views] is the already-discovered Flutter View list; callers hold it
/// from their own layout validation, so the tree is walked once.
List<String> buildInputPaths(Directory root, List<FlutterView> views) {
  final paths = <String>[];
  for (final descriptor in ['extension.dart', 'extension.json']) {
    if (projectFile(root, descriptor).existsSync()) {
      paths.add(descriptor);
    }
  }
  for (final path in [
    'host/pubspec.yaml',
    'host/pubspec.lock',
    'shared/pubspec.yaml',
  ]) {
    if (projectFile(root, path).existsSync()) {
      paths.add(path);
    }
  }
  for (final sourceRoot in ['host/lib', 'shared/lib']) {
    final directory = Directory(projectFile(root, sourceRoot).path);
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in safeFiles(
      directory,
      description: '$sourceRoot source tree',
    )) {
      final relative = relativeProjectPath(root, entity);
      if (!relative.startsWith('host/lib/generated/') &&
          !relative.startsWith('shared/lib/generated/')) {
        paths.add(relative);
      }
    }
  }
  for (final view in views) {
    for (final file in safeFiles(
      view.root,
      description: 'Flutter View ${view.name} source tree',
      excludedTopLevelNames: const {'.dart_tool', 'build'},
    )) {
      paths.add(relativeProjectPath(root, file));
    }
  }
  return paths.toSet().toList()..sort();
}

/// Enumerates the Framework-Managed Artifacts a build owns, in stable order.
List<String> managedArtifactPaths(Directory root) {
  final paths = <String>[];
  for (final path in [
    '.vscode/launch.json',
    'coverage.json',
    'host/bootstrap.cjs',
    'package.json',
  ]) {
    if (projectFile(root, path).existsSync()) {
      paths.add(path);
    }
  }
  for (final artifactRoot in [
    'host/lib/generated',
    'out',
    'shared/lib/generated',
  ]) {
    final directory = Directory(projectFile(root, artifactRoot).path);
    if (!directory.existsSync()) {
      continue;
    }
    for (final entity in safeFiles(
      directory,
      description: '$artifactRoot Framework-Managed Artifact tree',
    )) {
      paths.add(relativeProjectPath(root, entity));
    }
  }
  return paths.toSet().toList()..sort();
}

/// Digests the framework sources that produce and package a build.
///
/// The VS Code API surface is not part of this identity: it ships inside
/// `package:dart_vscode`, whose resolved version the project's pubspec
/// already pins the ordinary way.
Future<String> frameworkSha256(Directory packageRoot) => digestPackagePaths(
  packageRoot: packageRoot,
  relativePaths: const ['bin/flutter_vscode.dart', 'lib', 'pubspec.yaml'],
);
