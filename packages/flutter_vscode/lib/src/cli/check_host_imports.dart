import 'dart:convert';
import 'dart:io';

import 'package:analyzer/dart/analysis/features.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:path/path.dart' as p;

const _allowedDartLibraries = {
  'dart:async',
  'dart:collection',
  'dart:convert',
  'dart:core',
  'dart:developer',
  'dart:js_interop',
  'dart:js_interop_unsafe',
  'dart:math',
  'dart:typed_data',
};
const _prohibitedPackages = {
  'flutter',
  'flutter_test',
  'flutter_web_plugins',
  'web',
};

/// Returns dependency-boundary violations reachable from [entrypoint].
List<String> checkHostImports({
  required File entrypoint,
  required File packageConfig,
}) {
  return _HostImportGuard(
    entrypoint: entrypoint,
    packageConfig: packageConfig,
  ).check();
}

/// Formats [violations] as an actionable command-line diagnostic.
String formatHostImportViolations(List<String> violations) {
  final output = StringBuffer('Host Dart dependency boundary check failed:\n');
  for (final violation in violations) {
    output.writeln('- $violation');
  }
  output.writeln(
    'Host Dart runs in the VS Code Node Extension Host. '
    'Move this code to a Flutter View or replace the dependency with a '
    'host-compatible package.',
  );
  return output.toString();
}

final class _HostImportGuard {
  _HostImportGuard({
    required this.entrypoint,
    required this.packageConfig,
  });

  final File entrypoint;
  final File packageConfig;
  final _visited = <String>{};
  final _violations = <String>[];
  late final Map<String, Uri> _packageLibraries = _readPackageLibraries();
  late final String _packageRoot = p.dirname(p.dirname(packageConfig.path));

  List<String> check() {
    if (!entrypoint.existsSync()) {
      return ['Entrypoint does not exist: ${entrypoint.path}'];
    }
    if (!packageConfig.existsSync()) {
      return ['Package config does not exist: ${packageConfig.path}'];
    }

    _visit(
      entrypoint,
      [p.relative(entrypoint.path, from: _packageRoot)],
    );
    return List.unmodifiable(_violations);
  }

  Map<String, Uri> _readPackageLibraries() {
    final decoded = jsonDecode(packageConfig.readAsStringSync());
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('Package config must be a JSON object.');
    }
    final packages = decoded['packages'];
    if (packages is! List<Object?>) {
      throw const FormatException('Package config has no packages array.');
    }

    final libraries = <String, Uri>{};
    for (final value in packages) {
      if (value is! Map<String, Object?>) {
        continue;
      }
      final name = value['name'];
      final root = value['rootUri'];
      final library = value['packageUri'];
      if (name is! String || root is! String || library is! String) {
        continue;
      }
      final rootUri = packageConfig.uri.resolve(root);
      libraries[name] = rootUri.resolve(library);
    }
    return libraries;
  }

  void _visit(File source, List<String> chain) {
    final normalizedPath = p.normalize(p.absolute(source.path));
    if (!_visited.add(normalizedPath)) {
      return;
    }
    if (!source.existsSync()) {
      _violations.add('${chain.join(' -> ')} (file not found)');
      return;
    }

    final parsed = parseFile(
      path: normalizedPath,
      featureSet: FeatureSet.latestLanguageVersion(),
      throwIfDiagnostics: false,
    );
    if (parsed.errors.isNotEmpty) {
      final diagnostic = parsed.errors.first;
      final location = parsed.lineInfo.getLocation(diagnostic.offset);
      throw HostDartSyntaxException(
        path: normalizedPath,
        line: location.lineNumber,
        column: location.columnNumber,
        message: diagnostic.message,
      );
    }
    for (final directive in parsed.unit.directives) {
      if (directive is! UriBasedDirective) {
        continue;
      }
      _follow(
        source: source,
        uriLiteral: directive.uri,
        chain: chain,
        lineInfo: parsed.lineInfo,
      );
      if (directive is NamespaceDirective) {
        for (final configuration in directive.configurations) {
          _follow(
            source: source,
            uriLiteral: configuration.uri,
            chain: chain,
            lineInfo: parsed.lineInfo,
          );
        }
      }
    }
  }

  void _follow({
    required File source,
    required StringLiteral uriLiteral,
    required List<String> chain,
    required LineInfo lineInfo,
  }) {
    final importUri = uriLiteral.stringValue;
    if (importUri == null) {
      return;
    }
    final location = lineInfo.getLocation(uriLiteral.offset);
    final sourceLocation =
        '${p.relative(source.path, from: _packageRoot)}:'
        '${location.lineNumber}:${location.columnNumber}';

    if (importUri.startsWith('dart:')) {
      if (!_allowedDartLibraries.contains(importUri)) {
        _violations.add(
          '$sourceLocation imports $importUri, which is not supported by '
          'Host Dart (${[...chain, importUri].join(' -> ')})',
        );
      }
      return;
    }
    final parsedUri = Uri.tryParse(importUri);
    if (parsedUri?.scheme == 'package' &&
        parsedUri!.pathSegments.isNotEmpty &&
        _prohibitedPackages.contains(parsedUri.pathSegments.first)) {
      _violations.add(
        '$sourceLocation imports $importUri, which is not supported by '
        'Host Dart (${[...chain, importUri].join(' -> ')})',
      );
      return;
    }

    final target = _resolve(source, importUri);
    if (target == null) {
      _violations.add(
        '$sourceLocation cannot resolve $importUri '
        '(${[...chain, importUri].join(' -> ')})',
      );
      return;
    }
    _visit(target, [...chain, importUri]);
  }

  File? _resolve(File source, String importUri) {
    final uri = Uri.tryParse(importUri);
    if (uri == null) {
      return null;
    }
    if (uri.scheme.isEmpty) {
      return File.fromUri(source.parent.uri.resolveUri(uri));
    }
    if (uri.scheme != 'package') {
      return null;
    }

    final segments = uri.pathSegments;
    if (segments.length < 2) {
      return null;
    }
    final libraryRoot = _packageLibraries[segments.first];
    if (libraryRoot == null) {
      return null;
    }
    return File.fromUri(libraryRoot.resolve(segments.skip(1).join('/')));
  }
}
