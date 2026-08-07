part of '../ir_validator.dart';

// Validates primitive value checks the other validators are built from.

void _validateIrExpression(Object? value, String path) {
  final expression = objectMap(value, path);
  final kind = string(expression['kind'], '$path.kind');
  switch (kind) {
    case 'literal':
      validateIrExactKeys(
        expression,
        const {'kind', 'value'},
        path: path,
      );
      final literal = expression['value'];
      if (literal is! String && literal is! bool && literal is! int) {
        _invalidIrValue('$path.value', literal);
      }
      if (literal is int) {
        _validateIrSafeInteger(literal, '$path.value');
      }
    case 'reference':
      validateIrExactKeys(
        expression,
        const {'kind', 'name'},
        path: path,
      );
      nonEmptyString(expression['name'], '$path.name');
    case 'unary':
      validateIrExactKeys(
        expression,
        const {'kind', 'operator', 'operand'},
        path: path,
      );
      final operator = string(expression['operator'], '$path.operator');
      if (!const {'++', '--', '+', '-', '~', '!'}.contains(operator)) {
        _invalidIrValue('$path.operator', operator);
      }
      _validateIrExpression(expression['operand'], '$path.operand');
    default:
      _invalidIrValue('$path.kind', kind);
  }
}

Never _invalidIrValue(String path, Object? value) {
  throw VSCodeBindingGenerationException(
    'INVALID_GENERATOR_INPUT',
    '$path contains unsupported v1 IR value ${jsonEncode(value)}.',
  );
}

bool _validateIrBoolean(Object? value, String path) {
  if (value is! bool) {
    _invalidIrValue(path, value);
  }
  return value;
}

int _validateIrNonNegativeInteger(Object? value, String path) {
  if (value is! int || value < 0) {
    _invalidIrValue(path, value);
  }
  return _validateIrSafeInteger(value, path);
}

int _validateIrSafeInteger(int value, String path) {
  const maxSafeInteger = 9007199254740991;
  if (value < -maxSafeInteger || value > maxSafeInteger) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a JavaScript safe integer.',
    );
  }
  return value;
}

String _validateIrCommit(Object? value, String path) {
  final commit = string(value, path);
  if (!RegExp(r'^[0-9a-f]{40}$').hasMatch(commit)) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a lowercase 40-character Git commit.',
    );
  }
  return commit;
}

void _validateIrSha256(Object? value, String path) {
  final digest = string(value, path);
  if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(digest)) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must be a lowercase SHA-256 digest.',
    );
  }
}

void _validateIrCoverage(
  Object? value,
  String path, {
  required String visibility,
}) {
  final coverage = objectMap(value, path);
  validateIrExactKeys(
    coverage,
    const {'discovery', 'semantics', 'binding', 'host'},
    path: path,
  );
  final discovery = string(coverage['discovery'], '$path.discovery');
  final semantics = string(coverage['semantics'], '$path.semantics');
  final binding = string(coverage['binding'], '$path.binding');
  final host = string(coverage['host'], '$path.host');
  final expectedSemantics = visibility == 'public' ? 'pending' : 'excluded';
  final expectedBinding = visibility == 'public' ? 'pending' : 'excluded';
  final expectedHost = visibility == 'public' ? 'pending' : 'notApplicable';
  if (discovery != 'discovered' ||
      semantics != expectedSemantics ||
      binding != expectedBinding ||
      host != expectedHost) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path must contain the producer coverage state for $visibility '
          'declarations: discovered/$expectedSemantics/$expectedBinding/'
          '$expectedHost.',
    );
  }
}

/// Rejects any input document whose schemaVersion is not 1.
void validateInputSchemaVersion(
  Map<String, Object?> document,
  String name,
) {
  if (document['schemaVersion'] != 1) {
    throw VSCodeBindingGenerationException(
      'UNSUPPORTED_INPUT_SCHEMA_VERSION',
      '$name.schemaVersion must be 1, found ${document['schemaVersion']}.',
    );
  }
}

/// Returns a stable semantic fingerprint for one normalized IR declaration.
String computeDeclarationFingerprint(Map<String, Object?> declaration) {
  final semanticDeclaration = Map<String, Object?>.from(declaration)
    ..remove('coverage');
  return sha256
      .convert(utf8.encode(_encodeCanonicalJson(semanticDeclaration)))
      .toString();
}
