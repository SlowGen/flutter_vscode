/// Maintainer-tool leaf scalars. The shared JSON coercion helpers live in
/// `package:dart_vscode`'s contributions library and are imported directly
/// by every module that needs them; only the digest and integer validators
/// are maintainer concerns.
library;

import 'package:dart_vscode/src/contributions/json_values.dart';

import 'generator.dart';

/// Requires a value to be a lowercase SHA-256 digest.
String sha256Digest(Object? value, String path) {
  final result = string(value, path);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(result)) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a lowercase SHA-256 digest.',
    );
  }
  return result;
}

/// Reads an optional integer, substituting a default when absent.
int integerOrDefault(
  Object? value, {
  required int defaultValue,
  required String path,
}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is! int) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must be an integer.',
    );
  }
  return value;
}
