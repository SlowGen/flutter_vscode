/// The pure parts of the pub registry client: the package-response
/// model and the lookup URL. The network path itself lives in the
/// host package, where the generated `hostFetch` runtime is available.
library;

import 'dart:convert';

import 'package:pub_semver/pub_semver.dart';

/// The registry's answer for one package.
final class PackageInfo {
  /// Creates a package answer.
  const PackageInfo({required this.latest, this.description});

  /// The latest published version.
  final Version latest;

  /// The latest release's pubspec description, when present.
  final String? description;
}

/// Parses one `GET <registry>/api/packages/<name>` response [body].
///
/// The pub API answers with
/// `{"name": ..., "latest": {"version": "1.2.3", "pubspec": {...}}}`;
/// the latest version and its pubspec description are all this
/// extension needs. Throws an actionable [FormatException] when the
/// body is not that shape.
PackageInfo parsePackageInfo(String body) {
  Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException catch (error) {
    throw FormatException(
      'The registry package response is not JSON (${error.message}). '
      'Check pubspecLens.registryUrl points at a pub-compatible registry.',
    );
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException(
      'The registry package response must be a JSON object with a '
      '"latest" release.',
    );
  }
  final latest = decoded['latest'];
  if (latest is! Map<String, Object?> || latest['version'] is! String) {
    throw const FormatException(
      'The registry package response has no latest.version string; '
      'a pub-compatible registry answers with '
      '{"latest": {"version": "1.2.3", ...}}.',
    );
  }
  final versionText = latest['version']! as String;
  Version version;
  try {
    version = Version.parse(versionText);
  } on FormatException {
    throw FormatException(
      'The registry reported latest.version "$versionText", which is '
      'not a semantic version.',
    );
  }
  final pubspec = latest['pubspec'];
  final description =
      pubspec is Map<String, Object?> && pubspec['description'] is String
      ? pubspec['description']! as String
      : null;
  return PackageInfo(latest: version, description: description);
}

/// The pub API lookup URL for [packageName] against [baseUrl].
///
/// [baseUrl] comes from the `pubspecLens.registryUrl` setting, so a
/// trailing slash is tolerated; gates point it at a local fake
/// registry serving the same `GET /api/packages/<name>` path.
String packageInfoUrl(String baseUrl, String packageName) {
  final base = baseUrl.endsWith('/')
      ? baseUrl.substring(0, baseUrl.length - 1)
      : baseUrl;
  return '$base/api/packages/${Uri.encodeComponent(packageName)}';
}

/// A pure in-memory cache of registry answers by package name.
///
/// Only successful answers are stored; a failed lookup stays uncached
/// so the next refresh retries it. The refresh command clears the
/// cache wholesale.
final class RegistryCache {
  final Map<String, PackageInfo> _byName = {};

  /// The cached answer for [packageName], or null on a miss.
  PackageInfo? operator [](String packageName) => _byName[packageName];

  /// Whether [packageName] has a cached answer.
  bool contains(String packageName) => _byName.containsKey(packageName);

  /// Stores the successful [info] answer for [packageName].
  void store(String packageName, PackageInfo info) =>
      _byName[packageName] = info;

  /// Forgets every stored answer.
  void clear() => _byName.clear();
}
