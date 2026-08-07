part of '../generator.dart';

// Concerns reviewed removals, Host Contracts, and unexpected keys in override entries.

void _rejectUnexpectedKeys(
  Map<String, Object?> value,
  Set<String> allowedKeys, {
  required String subject,
}) {
  final unexpected =
      value.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
  if (unexpected.isEmpty) {
    return;
  }
  final expected = allowedKeys.toList()..sort();
  throw VSCodeBindingGenerationException(
    'INVALID_OVERRIDE',
    '$subject must contain exactly ${expected.join(', ')}; unexpected '
        '${unexpected.join(', ')}.',
  );
}

void _validateReviewedRemovals(Object? value, Set<String> currentPublicIds) {
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw const VSCodeBindingGenerationException(
      'INVALID_OVERRIDE',
      'Semantic Override removals must be an object when present.',
    );
  }
  final removals = value.cast<String, Object?>();
  for (final id in removals.keys.toList()..sort()) {
    if (currentPublicIds.contains(id)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Semantic Override removal $id is stale because the declaration is '
            'still public in the pinned inventory.',
      );
    }
    final value = removals[id];
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Semantic Override removal $id must be an object.',
      );
    }
    final removal = value.cast<String, Object?>();
    _rejectUnexpectedKeys(
      removal,
      const {'strategy', 'declarationSha256', 'reason'},
      subject: 'Semantic Override removal $id',
    );
    if (removal['strategy'] != 'reviewedRemoval') {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Semantic Override removal $id strategy must be reviewedRemoval.',
      );
    }
    final declarationSha256 = removal['declarationSha256'];
    if (declarationSha256 is! String ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(declarationSha256)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Semantic Override removal $id declarationSha256 must be a '
            'lowercase SHA-256.',
      );
    }
    final reason = removal['reason'];
    if (reason is! String || isEcmaScriptFalsyOrWhitespace(reason)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Semantic Override removal $id requires a non-empty reason.',
      );
    }
  }
}

Map<String, Map<String, Object?>> _validateHostContracts(Object? value) {
  final rawContracts = objectMap(value, 'overrides.hostContracts');
  if (rawContracts.isEmpty) {
    throw const VSCodeBindingGenerationException(
      'INVALID_OVERRIDE',
      'Semantic Overrides must declare at least one executable Host Contract.',
    );
  }
  final result = <String, Map<String, Object?>>{};
  final ids = rawContracts.keys.toList()..sort();
  for (final id in ids) {
    if (!RegExp(r'^[a-z][A-Za-z0-9]*$').hasMatch(id)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Host Contract ID $id must be lower camel case.',
      );
    }
    final contract = objectMap(
      rawContracts[id],
      'overrides.hostContracts.$id',
    );
    const expectedKeys = {'artifact', 'artifactSha256', 'boundary'};
    if (contract.length != expectedKeys.length ||
        !contract.keys.toSet().containsAll(expectedKeys)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Host Contract $id must contain exactly artifact, artifactSha256, '
            'and boundary.',
      );
    }
    final boundary = string(
      contract['boundary'],
      'overrides.hostContracts.$id.boundary',
    );
    if (boundary != 'vscodeExtensionHost') {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Host Contract $id has unsupported boundary $boundary.',
      );
    }
    final artifact = string(
      contract['artifact'],
      'overrides.hostContracts.$id.artifact',
    );
    if (!RegExp(
      r'^tool/bindings/contracts/[a-z0-9](?:[a-z0-9._-]*[a-z0-9])?\.json$',
    ).hasMatch(artifact)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Host Contract $id artifact must be a canonical JSON file directly '
            'under tool/bindings/contracts/.',
      );
    }
    final artifactSha256 = string(
      contract['artifactSha256'],
      'overrides.hostContracts.$id.artifactSha256',
    );
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(artifactSha256)) {
      throw VSCodeBindingGenerationException(
        'INVALID_OVERRIDE',
        'Host Contract $id artifactSha256 must be a lowercase SHA-256.',
      );
    }
    final normalized = <String, Object?>{
      'boundary': boundary,
      'artifact': artifact,
      'artifactSha256': artifactSha256,
    };
    result[id] = normalized;
  }
  return result;
}
