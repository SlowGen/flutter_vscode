/// Leaf scalar validators shared by contribution projection and the
/// maintainer-side binding generator: each coerces one JSON value or
/// raises an actionable failure.
library;

import 'package:dart_vscode/src/contributions/ecmascript_whitespace.dart';
import 'package:dart_vscode/src/contributions/exception.dart';

/// Requires a value to be a JSON array.
List<Object?> objectList(Object? value, String path) {
  if (value is! List<Object?>) {
    throw ContributionException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a JSON array.',
    );
  }
  return value;
}

/// Requires a value to be a string-keyed JSON object.
Map<String, Object?> objectMap(Object? value, String path) {
  if (value is! Map<Object?, Object?>) {
    throw ContributionException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a JSON object.',
    );
  }
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) {
      throw ContributionException(
        'INVALID_GENERATOR_INPUT',
        '$path contains a non-string key.',
      );
    }
    result[entry.key! as String] = entry.value;
  }
  return result;
}

/// Requires a value to be a string.
String string(Object? value, String path) {
  if (value is! String) {
    throw ContributionException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a string.',
    );
  }
  return value;
}

/// Requires a value to be a non-empty string.
String nonEmptyString(Object? value, String path) {
  final result = string(value, path);
  if (result.isEmpty) {
    throw ContributionException(
      'INVALID_PROJECT_MANIFEST',
      '$path must not be empty.',
    );
  }
  return result;
}

/// Requires a value to be a lower-kebab extension identifier component.
String extensionIdentifierComponent(Object? value, String path) {
  final result = nonEmptyString(value, path);
  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(result)) {
    throw ContributionException(
      'INVALID_PROJECT_MANIFEST',
      '$path "$result" is unsafe for a packaged extension identifier. '
          'flutter_vscode requires lower-kebab components: start with a '
          'lowercase ASCII letter or digit, then use only lowercase ASCII '
          'letters, digits, or hyphens.',
    );
  }
  return result;
}

/// Requires a value to contain a non-whitespace character.
String nonWhitespaceString(Object? value, String path) {
  final result = string(value, path);
  if (isEcmaScriptFalsyOrWhitespace(result)) {
    throw ContributionException(
      'INVALID_PROJECT_MANIFEST',
      '$path must contain a non-whitespace character.',
    );
  }
  return result;
}
