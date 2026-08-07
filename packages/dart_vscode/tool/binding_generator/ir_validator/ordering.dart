part of '../ir_validator.dart';

// Validates declaration ordering, overload ordinals, and the identity derived from them.

/// Validates the canonical ordering of the declaration list.
void validateIrDeclarationOrder(List<Object?> declarations) {
  for (var index = 1; index < declarations.length; index += 1) {
    final previous = objectMap(
      declarations[index - 1],
      'inventory.declarations[${index - 1}]',
    );
    final current = objectMap(
      declarations[index],
      'inventory.declarations[$index]',
    );
    if (_compareIrDeclarations(previous, current) > 0) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        'inventory.declarations must remain in producer sort order; '
            'entry $index precedes entry ${index - 1}.',
      );
    }
  }
}

int _compareIrDeclarations(
  Map<String, Object?> left,
  Map<String, Object?> right,
) {
  final qualified =
      string(
        left['qualifiedName'],
        'inventory declaration.qualifiedName',
      ).compareTo(
        string(
          right['qualifiedName'],
          'inventory declaration.qualifiedName',
        ),
      );
  if (qualified != 0) {
    return qualified;
  }
  final leftOrdinal = left['overloadOrdinal'];
  final rightOrdinal = right['overloadOrdinal'];
  if (leftOrdinal is int && rightOrdinal is int) {
    final ordinal = leftOrdinal.compareTo(rightOrdinal);
    if (ordinal != 0) {
      return ordinal;
    }
  }
  return string(left['id'], 'inventory declaration.id').compareTo(
    string(right['id'], 'inventory declaration.id'),
  );
}

/// Validates the identity fields of one inventory declaration.
void validateIrDeclarationIdentity(
  Map<String, Object?> declaration,
  String path,
  Map<String, Map<String, Object?>> declarationsById,
) {
  final id = string(declaration['id'], '$path.id');
  final kind = string(declaration['kind'], '$path.kind');
  final name = string(declaration['name'], '$path.name');
  final qualifiedName = string(
    declaration['qualifiedName'],
    '$path.qualifiedName',
  );
  final parentId = string(declaration['parentId'], '$path.parentId');
  final parent = declarationsById[parentId];
  final rootParent = parentId == 'module:vscode' || parentId == 'global:global';
  if (!rootParent && parent == null) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.parentId $parentId does not resolve to a producer declaration.',
    );
  }
  final parentKind = parent?['kind'] as String?;
  final allowedParentKinds = switch (kind) {
    'namespace' ||
    'interface' ||
    'class' ||
    'enum' ||
    'typeAlias' ||
    'variable' ||
    'function' => const {'namespace'},
    'enumMember' => const {'enum'},
    'property' || 'method' => const {'class', 'interface', 'typeLiteral'},
    'constructor' => const {'class'},
    'callSignature' || 'indexSignature' => const {
      'class',
      'interface',
      'typeLiteral',
    },
    'typeLiteral' => const {
      'typeAlias',
      'variable',
      'property',
      'function',
      'constructor',
      'callSignature',
      'method',
      'indexSignature',
    },
    _ => const <String>{},
  };
  final acceptsRoot = const {
    'namespace',
    'interface',
    'class',
    'enum',
    'typeAlias',
    'variable',
    'function',
  }.contains(kind);
  if ((rootParent && !acceptsRoot) ||
      (!rootParent && !allowedParentKinds.contains(parentKind))) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.parentId $parentId is incompatible with $kind declarations.',
    );
  }

  final parentQualifiedName = switch (parentId) {
    'module:vscode' => 'vscode',
    'global:global' => 'global',
    _ => string(parent!['qualifiedName'], '$path.parentId.qualifiedName'),
  };
  final expectedQualifiedName = kind == 'typeLiteral'
      ? '$parentId.\$shape@${declaration['shapeHash']}'
      : '$parentQualifiedName.$name';
  if (qualifiedName != expectedQualifiedName) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.qualifiedName must be derived from name and parentId as '
          '$expectedQualifiedName.',
    );
  }

  if (kind == 'constructor' && name != 'constructor' ||
      kind == 'callSignature' && name != r'$call' ||
      kind == 'indexSignature' && name != r'$index' ||
      kind == 'typeLiteral' && name != r'$type') {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.name is not the producer name for $kind declarations.',
    );
  }

  final expectedId = switch (kind) {
    'namespace' ||
    'interface' ||
    'class' ||
    'enum' ||
    'typeAlias' ||
    'variable' => '$kind:$qualifiedName',
    'enumMember' => 'enumMember:$parentId/${_encodeIrIdPart(name)}',
    'property' =>
      'property:$parentId/${declaration['static'] == true ? r'$static' : r'$instance'}/${_encodeIrIdPart(name)}',
    'function' ||
    'constructor' ||
    'callSignature' ||
    'method' ||
    'indexSignature' =>
      '$kind:$qualifiedName@${sha256.convert(utf8.encode(string(declaration['canonicalSignature'], '$path.canonicalSignature')))}',
    'typeLiteral' =>
      'typeLiteral:$parentId/\$shape@${declaration['shapeHash']}',
    _ => id,
  };
  if (id != expectedId) {
    final basis =
        const {
          'function',
          'constructor',
          'callSignature',
          'method',
          'indexSignature',
        }.contains(kind)
        ? 'canonicalSignature, qualifiedName, and kind'
        : kind == 'typeLiteral'
        ? 'parentId and shapeHash'
        : 'name, qualifiedName, parentId, kind, and flags';
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.id must be derived from $basis as $expectedId.',
    );
  }

  final visibility = string(declaration['visibility'], '$path.visibility');
  if (rootParent && visibility != 'public') {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.visibility must be public for top-level producer declarations.',
    );
  }
  if (parent != null) {
    final parentVisibility = string(
      parent['visibility'],
      '$path.parentId.visibility',
    );
    final inheritsVisibility =
        kind == 'typeLiteral' ||
        kind == 'enumMember' ||
        ((kind == 'property' || kind == 'method') && parentKind != 'class') ||
        kind == 'callSignature' ||
        kind == 'indexSignature';
    if (inheritsVisibility && visibility != parentVisibility) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.visibility must inherit $parentVisibility from $parentId.',
      );
    }
    if ((kind == 'property' || kind == 'method') && parentKind != 'class') {
      for (final flag in const ['static', 'abstract']) {
        if (declaration[flag] != false) {
          throw VSCodeBindingGenerationException(
            'INVALID_GENERATOR_INPUT',
            '$path.$flag must be false outside class declarations.',
          );
        }
      }
    }
  }
  if (kind == 'variable') {
    final declarationKind = declaration['declarationKind'];
    final expectedConstant = declarationKind == 'const';
    if (declaration['constant'] != expectedConstant) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.constant must equal (declarationKind == const).',
      );
    }
  }
}

String _encodeIrIdPart(String value) {
  return Uri.encodeComponent(value)
      .replaceAll('%21', '!')
      .replaceAll('%27', "'")
      .replaceAll('%28', '(')
      .replaceAll('%29', ')')
      .replaceAll('%2A', '*');
}

/// Validates overload ordinal assignments across the inventory.
void validateIrOverloadOrdinals(
  Map<String, Map<String, Object?>> declarationsById,
  Map<String, String> declarationPathsById,
) {
  final groups = <String, List<Map<String, Object?>>>{};
  for (final declaration in declarationsById.values) {
    if (!const {
      'function',
      'constructor',
      'callSignature',
      'method',
      'indexSignature',
    }.contains(declaration['kind'])) {
      continue;
    }
    final key =
        '${declaration['kind']}:${declaration['qualifiedName']}:'
        '${declaration['static'] == true}';
    groups.putIfAbsent(key, () => []).add(declaration);
  }
  for (final declarations in groups.values) {
    declarations.sort(
      (left, right) => (left['overloadOrdinal']! as int).compareTo(
        right['overloadOrdinal']! as int,
      ),
    );
    var expected = 0;
    for (final declaration in declarations) {
      final actual = declaration['overloadOrdinal']! as int;
      if (actual != expected) {
        final path = declarationPathsById[declaration['id']]!;
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path.overloadOrdinal must be $expected for its producer overload '
              'group; found $actual.',
        );
      }
      expected += (declaration['occurrenceCount'] as int?) ?? 1;
    }
  }
}
