import 'dart:convert';
import 'dart:io';

import 'package:dart_vscode/contributions.dart';
import 'package:flutter_vscode/src/cli/artifact_writer.dart';
import 'package:flutter_vscode/src/cli/baselines.dart';
import 'package:flutter_vscode/src/cli/build_inputs.dart';
import 'package:flutter_vscode/src/cli/build_receipt.dart';
import 'package:flutter_vscode/src/cli/check_host_imports.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/json_object.dart';
import 'package:flutter_vscode/src/cli/project_artifacts.dart';
import 'package:flutter_vscode/src/cli/project_descriptor.dart';
import 'package:flutter_vscode/src/cli/project_layout.dart';
import 'package:path/path.dart' as p;

/// Builds the Extension Project at [root] into runnable host artifacts.
Future<void> buildProject(Directory root) async {
  validateProjectLayout(root);
  final dartDescriptor = File(p.join(root.path, 'extension.dart'));
  final jsonDescriptor = File(p.join(root.path, 'extension.json'));
  final hostRoot = Directory(p.join(root.path, 'host'));
  final entrypoint = File(p.join(hostRoot.path, 'lib', 'extension.dart'));
  if ((!dartDescriptor.existsSync() && !jsonDescriptor.existsSync()) ||
      !entrypoint.existsSync()) {
    throw const CliException(
      'Run build from an Extension Project containing extension.dart and '
      'host/lib/extension.dart.',
      code: 'BUILD_NOT_EXTENSION_PROJECT',
      exitCode: 64,
    );
  }
  if (dartDescriptor.existsSync() && jsonDescriptor.existsSync()) {
    throw const CliException(
      'Extension Project contains both extension.dart and extension.json. '
      'Remove the obsolete descriptor.',
      code: 'AMBIGUOUS_PROJECT_DESCRIPTOR',
    );
  }

  final views = discoverViews(root);
  validateFlutterViewLayout(root, views);
  final packageRoot = await resolvePackageRoot();
  final project = dartDescriptor.existsSync()
      ? await readProjectDescriptor(dartDescriptor)
      : await readJsonObject(jsonDescriptor);
  final generated = emitProjectArtifacts(project);
  final generatedRoot = Directory(
    p.join(hostRoot.path, 'lib', 'generated'),
  );
  if (generatedRoot.existsSync()) {
    await generatedRoot.delete(recursive: true);
  }
  await writeProjectArtifacts(generated, root);
  // Framework code is not emitted into projects: the view protocol, the
  // command registration module, and the Flutter View host module are
  // libraries in package:dart_vscode. A project receives only what is
  // derived from the project itself.
  final sharedGeneratedRoot = Directory(
    p.join(root.path, 'shared', 'lib', 'generated'),
  );
  if (sharedGeneratedRoot.existsSync()) {
    await sharedGeneratedRoot.delete(recursive: true);
  }
  await _run(
    'dart',
    const ['pub', 'get'],
    workingDirectory: hostRoot.path,
    description: 'resolve Host Dart dependencies',
  );
  final packageConfig = _findPackageConfig(hostRoot);
  final guardPackageConfig = await _writeDirectoryAwarePackageConfig(
    packageConfig,
  );
  late final List<String> violations;
  try {
    violations = _checkHostAndSharedImports(
      hostRoot: hostRoot,
      sharedRoot: Directory(p.join(root.path, 'shared')),
      packageConfig: guardPackageConfig,
    );
  } finally {
    await guardPackageConfig.delete();
  }
  if (violations.isNotEmpty) {
    throw CliException(
      formatHostImportViolations(violations).trimRight(),
      code: 'HOST_IMPORT_BOUNDARY_VIOLATION',
    );
  }

  final out = Directory(p.join(root.path, 'out'));
  if (out.existsSync()) {
    await out.delete(recursive: true);
  }
  await out.create(recursive: true);
  await _run(
    'dart',
    [
      'compile',
      'js',
      '--server-mode',
      '--fatal-warnings',
      '-O2',
      entrypoint.path,
      '--output',
      p.join(out.path, 'extension.dart.js'),
    ],
    workingDirectory: hostRoot.path,
    description: 'compile Host Dart',
  );
  await File(p.join(hostRoot.path, 'bootstrap.cjs')).copy(
    p.join(out.path, 'bootstrap.cjs'),
  );
  for (final view in views) {
    await _run(
      'flutter',
      const ['pub', 'get'],
      workingDirectory: view.root.path,
      description: 'resolve Flutter View ${view.name} dependencies',
    );
    final output = p.join(out.path, 'views', view.name);
    await _run(
      'flutter',
      [
        'build',
        'web',
        '--release',
        '--output=$output',
        '--no-web-resources-cdn',
        '--csp',
        '--pwa-strategy',
        'none',
        '--no-tree-shake-icons',
      ],
      workingDirectory: view.root.path,
      description: 'build Flutter View ${view.name}',
    );
  }
  viewOutputFiles(root, views);
  await _writeLaunchConfiguration(root);
  final frameworkDigest = await frameworkSha256(packageRoot);
  await writeBuildReceipt(
    projectRoot: root,
    apiTarget: vscodeApiVersion,
    frameworkSha256: frameworkDigest,
    inputPaths: buildInputPaths(root, views),
    artifactPaths: managedArtifactPaths(root),
  );
  stdout.writeln('Built ${root.path}');
}

/// Locates the `package_config.json` that governs [start].
///
/// A standalone Extension Project resolves into its own `.dart_tool/`, but a
/// project that is a member of a pub workspace resolves into the workspace
/// root instead, so this walks upward the way the Dart toolchain does.
File _findPackageConfig(Directory start) {
  for (var directory = start; ; directory = directory.parent) {
    final candidate = File(
      p.join(directory.path, '.dart_tool', 'package_config.json'),
    );
    if (candidate.existsSync()) {
      return candidate;
    }
    if (p.equals(directory.path, directory.parent.path)) {
      throw CliException(
        'Host Dart dependencies did not resolve: no package config '
        'exists at or above ${start.path}.',
        code: 'MISSING_PACKAGE_CONFIG',
      );
    }
  }
}

Future<File> _writeDirectoryAwarePackageConfig(File packageConfig) async {
  final decoded = jsonDecode(await packageConfig.readAsString());
  if (decoded is! Map<String, Object?> ||
      decoded['packages'] is! List<Object?>) {
    throw const FormatException('Host package config is malformed.');
  }
  final packages = decoded['packages']! as List<Object?>;
  for (final package in packages) {
    if (package is! Map<String, Object?> || package['rootUri'] is! String) {
      continue;
    }
    final rootUri = Uri.parse(package['rootUri']! as String);
    if (!rootUri.path.endsWith('/')) {
      package['rootUri'] = rootUri.replace(path: '${rootUri.path}/').toString();
    }
  }
  final normalized = File(
    p.join(
      packageConfig.parent.path,
      'flutter_vscode_package_config.json',
    ),
  );
  await normalized.writeAsString(jsonEncode(decoded), flush: true);
  return normalized;
}

List<String> _checkHostAndSharedImports({
  required Directory hostRoot,
  required Directory sharedRoot,
  required File packageConfig,
}) {
  final sources = <File>[];
  for (final sourceRoot in [hostRoot, sharedRoot]) {
    if (!sourceRoot.existsSync()) {
      continue;
    }
    for (final entity in sourceRoot.listSync(recursive: true)) {
      if (entity is! File || p.extension(entity.path) != '.dart') {
        continue;
      }
      final relative = p.relative(entity.path, from: sourceRoot.path);
      final segments = p.split(relative);
      if (segments.contains('.dart_tool')) {
        continue;
      }
      // Package test directories never execute inside the Extension Host.
      if (segments.first == 'test') {
        continue;
      }
      sources.add(entity);
    }
  }
  sources.sort((left, right) => left.path.compareTo(right.path));
  final violations = <String>{};
  for (final source in sources) {
    violations.addAll(
      checkHostImports(
        entrypoint: source,
        packageConfig: packageConfig,
      ),
    );
  }
  return violations.toList()..sort();
}

Future<void> _run(
  String executable,
  List<String> arguments, {
  required String workingDirectory,
  required String description,
}) async {
  late final ProcessResult result;
  try {
    result = await Process.run(
      executable,
      arguments,
      workingDirectory: workingDirectory,
    );
  } on ProcessException catch (error) {
    throw CliException(
      'Could not start $description with $executable: ${error.message}',
      code: 'TOOL_COMMAND_START_FAILED',
    );
  }
  if (result.exitCode != 0) {
    throw CliException(
      'Failed to $description.\n${result.stdout}${result.stderr}',
      code: 'TOOL_COMMAND_FAILED',
    );
  }
}

Future<void> _writeLaunchConfiguration(Directory root) async {
  const encoder = JsonEncoder.withIndent('  ');
  final file = File(p.join(root.path, '.vscode', 'launch.json'));
  await file.parent.create(recursive: true);
  await file.writeAsString(
    '${encoder.convert(<String, Object?>{
      'version': '0.2.0',
      'configurations': <Object?>[
        <String, Object?>{
          'name': 'Run Extension',
          'type': 'extensionHost',
          'request': 'launch',
          'args': <String>[
            r'--extensionDevelopmentPath=${workspaceFolder}',
          ],
          'outFiles': <String>[r'${workspaceFolder}/out/**/*.js'],
        },
      ],
    })}\n',
  );
}
