part of '../binding_generator_test.dart';

// Damages a valid fixture in one exact way, so a test can prove the
// generator rejects that damage and nothing else. Kept apart from the
// builders: making a thing and breaking it are different jobs.

void _reanchorDeclaration(
  Map<String, Object?> inventory,
  Map<String, Object?> declaration,
  String parentId,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final parent = declarations.singleWhere(
    (candidate) => candidate['id'] == parentId,
  );
  final name = declaration['name']! as String;
  final qualifiedName = '${parent['qualifiedName']}.$name';
  declaration
    ..['parentId'] = parentId
    ..['qualifiedName'] = qualifiedName;
  final kind = declaration['kind']! as String;
  declaration['id'] = switch (kind) {
    'constructor' || 'method' =>
      '$kind:$qualifiedName@${_sha256String(declaration['canonicalSignature']! as String)}',
    'enumMember' => 'enumMember:$parentId/${Uri.encodeComponent(name)}',
    'property' =>
      'property:$parentId/${declaration['static'] == true ? r'$static' : r'$instance'}/${Uri.encodeComponent(name)}',
    _ => throw StateError('unsupported fixture kind $kind'),
  };
}

String _renameProducerDeclaration(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String declarationId,
  String name,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  declarations.singleWhere(
    (candidate) => candidate['id'] == declarationId,
  )['name'] = name;
  final renamedId = _reindexProducerSubtree(
    inventory,
    overrides,
    declarationId,
  )[declarationId]!;
  return _resynchronizeAncestorTypeLiterals(
    inventory,
    overrides,
    renamedId,
  );
}

String _resynchronizeAncestorTypeLiterals(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String declarationId,
) {
  const callableKinds = {
    'function',
    'constructor',
    'callSignature',
    'method',
    'indexSignature',
  };
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final tracked = declarations.singleWhere(
    (candidate) => candidate['id'] == declarationId,
  );
  var changed = true;
  var guard = 0;
  while (changed) {
    if (guard++ > 64) {
      throw StateError('Ancestor type-literal resynchronization diverged.');
    }
    changed = false;
    final byId = <String, Map<Object?, Object?>>{
      for (final candidate in declarations)
        candidate['id']! as String: candidate,
    };
    final declarationsById = <String, Map<String, Object?>>{
      for (final candidate in declarations)
        candidate['id']! as String: candidate.cast<String, Object?>(),
    };
    final childrenByParent = <String, List<Map<Object?, Object?>>>{};
    for (final declaration in declarations) {
      childrenByParent
          .putIfAbsent(declaration['parentId']! as String, () => [])
          .add(declaration);
    }
    var node = byId[tracked['parentId']];
    while (node != null) {
      if (node['kind'] == 'typeLiteral') {
        final literal = node.cast<String, Object?>();
        final shape = _rebuildFixtureTypeLiteralShape(
          literal,
          childrenByParent[literal['id']] ?? const [],
          declarationsById,
        );
        final shapeHash = _shapeHash(shape);
        if (jsonEncode(literal['shape']) != jsonEncode(shape) ||
            literal['shapeHash'] != shapeHash) {
          final oldId = literal['id']! as String;
          literal['shape'] = shape;
          if (literal['shapeHash'] != shapeHash) {
            literal['shapeHash'] = shapeHash;
            _replaceRegisteredTypeLiteralShapeHash(
              inventory,
              oldId,
              shapeHash,
            );
            _reindexProducerSubtree(inventory, overrides, oldId);
          }
          changed = true;
          break;
        }
      } else if (callableKinds.contains(node['kind'])) {
        final callable = node.cast<String, Object?>();
        final expected = _fixtureCanonicalSignature(
          callable,
          _fixtureInheritedScopes(callable, declarationsById),
        );
        if (callable['canonicalSignature'] != expected) {
          callable['canonicalSignature'] = expected;
          _reindexProducerSubtree(
            inventory,
            overrides,
            callable['id']! as String,
          );
          changed = true;
          break;
        }
      }
      node = byId[node['parentId']];
    }
  }
  _refreshOverrideFingerprints(inventory, overrides);
  _sortDeclarationsLikeProducer(inventory);
  return tracked['id']! as String;
}

String _synchronizeCallableProducerEncoding(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String declarationId,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final declaration = declarations
      .singleWhere((candidate) => candidate['id'] == declarationId)
      .cast<String, Object?>();
  final declarationsById = <String, Map<String, Object?>>{
    for (final candidate in declarations)
      candidate['id']! as String: candidate.cast<String, Object?>(),
  };
  declaration['canonicalSignature'] = _fixtureCanonicalSignature(
    declaration,
    _fixtureInheritedScopes(declaration, declarationsById),
  );
  final refreshedId = _reindexProducerSubtree(
    inventory,
    overrides,
    declarationId,
  )[declarationId]!;
  return _resynchronizeAncestorTypeLiterals(
    inventory,
    overrides,
    refreshedId,
  );
}

String _synchronizeProducerMutation(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String declarationId,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final declaration = declarations.singleWhere(
    (candidate) => candidate['id'] == declarationId,
  );
  if (const {
    'function',
    'constructor',
    'callSignature',
    'method',
    'indexSignature',
  }.contains(declaration['kind'])) {
    return _synchronizeCallableProducerEncoding(
      inventory,
      overrides,
      declarationId,
    );
  }
  _synchronizeDescendantProducerEncodings(
    inventory,
    overrides,
    declarationId,
  );
  _refreshOverrideFingerprints(inventory, overrides);
  _sortDeclarationsLikeProducer(inventory);
  return declarationId;
}

void _synchronizeDescendantProducerEncodings(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String rootId,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final childrenByParent = <String, List<Map<Object?, Object?>>>{};
  for (final declaration in declarations) {
    childrenByParent
        .putIfAbsent(declaration['parentId']! as String, () => [])
        .add(declaration);
  }
  final descendants = <Map<Object?, Object?>>[];
  final pending = <Map<Object?, Object?>>[
    ...?childrenByParent[rootId],
  ];
  while (pending.isNotEmpty) {
    final declaration = pending.removeAt(0);
    descendants.add(declaration);
    pending.addAll(
      childrenByParent[declaration['id']] ?? const <Map<Object?, Object?>>[],
    );
  }

  final declarationsById = <String, Map<String, Object?>>{
    for (final declaration in declarations)
      declaration['id']! as String: declaration.cast<String, Object?>(),
  };
  final changedTypeLiterals = <Map<Object?, Object?>>[];
  for (final typeLiteral in descendants.reversed.where(
    (candidate) => candidate['kind'] == 'typeLiteral',
  )) {
    final literal = typeLiteral.cast<String, Object?>();
    final shape = _rebuildFixtureTypeLiteralShape(
      literal,
      childrenByParent[literal['id']] ?? const [],
      declarationsById,
    );
    literal['shape'] = shape;
    final shapeHash = _shapeHash(shape);
    if (shapeHash == typeLiteral['shapeHash']) {
      continue;
    }
    final oldId = typeLiteral['id']! as String;
    typeLiteral['shapeHash'] = shapeHash;
    _replaceRegisteredTypeLiteralShapeHash(inventory, oldId, shapeHash);
    changedTypeLiterals.add(typeLiteral);
  }

  const callableKinds = {
    'function',
    'constructor',
    'callSignature',
    'method',
    'indexSignature',
  };
  final callableDescendants = descendants
      .where((candidate) => callableKinds.contains(candidate['kind']))
      .toList();
  for (final typeLiteral in changedTypeLiterals) {
    var parentId = typeLiteral['parentId']! as String;
    var hasCallableAncestor = false;
    while (parentId != rootId && declarationsById[parentId] != null) {
      final parent = declarationsById[parentId]!;
      if (callableKinds.contains(parent['kind'])) {
        hasCallableAncestor = true;
        break;
      }
      parentId = parent['parentId']! as String;
    }
    if (!hasCallableAncestor) {
      _refreshProducerIdentity(
        inventory,
        overrides,
        typeLiteral['id']! as String,
      );
    }
  }
  for (final callable in callableDescendants) {
    _synchronizeCallableProducerEncoding(
      inventory,
      overrides,
      callable['id']! as String,
    );
  }
}

Map<String, Object?> _matchFixtureShapeChild(
  List<Map<Object?, Object?>> children,
  Set<Map<Object?, Object?>> used,
  String kind,
  Object? name,
  int? ordinal,
) {
  final sameKind = children
      .where(
        (candidate) => candidate['kind'] == kind && !used.contains(candidate),
      )
      .toList();
  var matches = sameKind
      .where(
        (candidate) =>
            (name == null || candidate['name'] == name) &&
            (ordinal == null || candidate['overloadOrdinal'] == ordinal),
      )
      .toList();
  if (matches.isEmpty && sameKind.length == 1) {
    matches = sameKind;
  }
  if (matches.length != 1) {
    throw StateError('No unique $kind child for fixture shape member $name.');
  }
  used.add(matches.single);
  return matches.single.cast<String, Object?>();
}

Map<String, Object?> _rebuildFixtureTypeLiteralShape(
  Map<String, Object?> literal,
  List<Map<Object?, Object?>> children,
  Map<String, Map<String, Object?>> declarationsById,
) {
  final oldMembers = [
    for (final member
        in (literal['shape']! as Map<Object?, Object?>)['members']!
            as List<Object?>)
      (member! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
  final ordinals = <String, int>{};
  final members = <Object?>[];
  final used = <Map<Object?, Object?>>{};
  for (final oldMember in oldMembers) {
    final kind = oldMember['kind']! as String;
    if (kind == 'property') {
      final child = _matchFixtureShapeChild(
        children,
        used,
        'property',
        oldMember['name'],
        null,
      );
      final scopes = _fixtureInheritedScopes(child, declarationsById);
      final rawType = child['type'];
      members.add(<String, Object?>{
        'kind': 'property',
        'name': child['name'],
        'optional': child['optional'],
        'readonly': child['readonly'],
        'type': scopes.any((scope) => scope.isNotEmpty)
            ? _fixtureCanonicalType(rawType, scopes)
            : rawType,
      });
    } else {
      final name = oldMember['name'];
      final ordinal = ordinals.update(
        '$kind@${name ?? ''}',
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final child = _matchFixtureShapeChild(
        children,
        used,
        kind,
        name,
        ordinal,
      );
      final canonical =
          (jsonDecode(
                    _fixtureCanonicalSignature(
                      child,
                      _fixtureInheritedScopes(child, declarationsById),
                    ),
                  )
                  as Map<Object?, Object?>)
              .cast<String, Object?>();
      final member = <String, Object?>{
        'kind': kind,
        'signature': canonical,
      };
      if (kind == 'method') {
        canonical
          ..remove('static')
          ..remove('optional');
        member['name'] = child['name'];
        member['optional'] = child['optional'];
        member['static'] = child['static'];
        member['abstract'] = child['abstract'];
      }
      if (kind == 'indexSignature') {
        canonical.remove('readonly');
        member['readonly'] = child['readonly'];
      }
      members.add(member);
    }
  }
  return <String, Object?>{'members': members};
}

void _replaceRegisteredTypeLiteralShapeHash(
  Object? value,
  String typeLiteralId,
  String shapeHash,
) {
  if (value is List<Object?>) {
    for (final item in value) {
      _replaceRegisteredTypeLiteralShapeHash(item, typeLiteralId, shapeHash);
    }
    return;
  }
  if (value is! Map<Object?, Object?>) {
    return;
  }
  if (value['kind'] == 'typeLiteral' &&
      value['id'] == typeLiteralId &&
      !value.containsKey('name')) {
    value['shapeHash'] = shapeHash;
  }
  for (final child in value.values) {
    _replaceRegisteredTypeLiteralShapeHash(child, typeLiteralId, shapeHash);
  }
}

String _refreshProducerIdentity(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String declarationId,
) {
  return _reindexProducerSubtree(
    inventory,
    overrides,
    declarationId,
  )[declarationId]!;
}

Map<String, String> _reindexProducerSubtree(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
  String rootId,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final byOldId = <String, Map<Object?, Object?>>{
    for (final declaration in declarations)
      declaration['id']! as String: declaration,
  };
  if (!byOldId.containsKey(rootId)) {
    throw StateError('No producer declaration $rootId.');
  }
  final childrenByOldParent = <String, List<String>>{};
  for (final declaration in declarations) {
    final parentId = declaration['parentId']! as String;
    childrenByOldParent
        .putIfAbsent(parentId, () => <String>[])
        .add(declaration['id']! as String);
  }

  final oldIds = <String>[];
  final pending = <String>[rootId];
  while (pending.isNotEmpty) {
    final oldId = pending.removeAt(0);
    oldIds.add(oldId);
    pending.addAll(childrenByOldParent[oldId] ?? const <String>[]);
  }

  final replacements = <String, String>{};
  for (final oldId in oldIds) {
    final declaration = byOldId[oldId]!;
    final oldParentId = declaration['parentId']! as String;
    final parentId = replacements[oldParentId] ?? oldParentId;
    declaration['parentId'] = parentId;
    final kind = declaration['kind']! as String;
    final name = declaration['name']! as String;
    final parentQualifiedName = switch (parentId) {
      'module:vscode' => 'vscode',
      'global:global' => 'global',
      _ =>
        declarations.singleWhere(
              (candidate) => candidate['id'] == parentId,
            )['qualifiedName']!
            as String,
    };
    final qualifiedName = kind == 'typeLiteral'
        ? '$parentId.\$shape@${declaration['shapeHash']}'
        : '$parentQualifiedName.$name';
    declaration['qualifiedName'] = qualifiedName;
    final newId = switch (kind) {
      'namespace' ||
      'interface' ||
      'class' ||
      'enum' ||
      'typeAlias' ||
      'variable' => '$kind:$qualifiedName',
      'enumMember' => 'enumMember:$parentId/${Uri.encodeComponent(name)}',
      'property' =>
        'property:$parentId/${declaration['static'] == true ? r'$static' : r'$instance'}/${Uri.encodeComponent(name)}',
      'function' ||
      'constructor' ||
      'callSignature' ||
      'method' ||
      'indexSignature' =>
        '$kind:$qualifiedName@${_sha256String(declaration['canonicalSignature']! as String)}',
      'typeLiteral' =>
        'typeLiteral:$parentId/\$shape@${declaration['shapeHash']}',
      _ => throw StateError('Unsupported producer declaration kind $kind.'),
    };
    declaration['id'] = newId;
    replacements[oldId] = newId;
  }

  _replaceRegisteredTypeLiteralIds(inventory, replacements);
  _rekeyOverrideIds(overrides, replacements);
  _refreshOverrideFingerprints(inventory, overrides);
  _sortDeclarationsLikeProducer(inventory);
  return replacements;
}

void _replaceRegisteredTypeLiteralIds(
  Object? value,
  Map<String, String> replacements,
) {
  if (value is List<Object?>) {
    for (final item in value) {
      _replaceRegisteredTypeLiteralIds(item, replacements);
    }
    return;
  }
  if (value is! Map<Object?, Object?>) {
    return;
  }
  if (value['kind'] == 'typeLiteral' &&
      value.containsKey('shapeHash') &&
      !value.containsKey('name')) {
    final id = value['id'];
    if (id is String && replacements[id] != null) {
      value['id'] = replacements[id];
    }
  }
  for (final child in value.values) {
    _replaceRegisteredTypeLiteralIds(child, replacements);
  }
}

void _rekeyOverrideIds(
  Map<String, Object?> overrides,
  Map<String, String> replacements,
) {
  final entries = overrides['entries']! as Map<Object?, Object?>;
  final removals = overrides['removals'] as Map<Object?, Object?>?;
  for (final replacement in replacements.entries) {
    if (replacement.key == replacement.value) {
      continue;
    }
    if (entries.containsKey(replacement.key)) {
      entries[replacement.value] = entries.remove(replacement.key);
    }
    if (removals?.containsKey(replacement.key) ?? false) {
      removals![replacement.value] = removals.remove(replacement.key);
    }
  }
  final targets = overrides['targets']! as List<Object?>;
  for (var index = 0; index < targets.length; index += 1) {
    final target = targets[index]! as String;
    targets[index] = replacements[target] ?? target;
  }
}

void _refreshOverrideFingerprints(
  Map<String, Object?> inventory,
  Map<String, Object?> overrides,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final entries = overrides['entries']! as Map<Object?, Object?>;
  for (final entry in entries.entries) {
    final declaration = declarations.singleWhere(
      (candidate) => candidate['id'] == entry.key,
    );
    (entry.value! as Map<Object?, Object?>)['declarationSha256'] =
        computeDeclarationFingerprint(declaration.cast<String, Object?>());
  }
}

String _synchronizeFixtureFunctionType(
  Map<String, Object?> type,
  List<List<String>> inheritedScopes,
) {
  final signature = _fixtureCanonicalSignature(type, inheritedScopes);
  type['canonicalSignature'] = signature;
  return signature;
}

void _tamperSignatureChildOfTypeLiteral(Map<String, Object?> inventory) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  for (final candidate in declarations) {
    if (candidate['kind'] != 'indexSignature') {
      continue;
    }
    final parentId = candidate['parentId']! as String;
    if (!parentId.startsWith('typeLiteral:')) {
      continue;
    }
    final child = candidate.cast<String, Object?>();
    final canonical =
        (jsonDecode(child['canonicalSignature']! as String)
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    canonical['returnType'] = {'kind': 'primitive', 'name': 'string'};
    final encodedCanonical = jsonEncode(canonical);
    final id = child['id']! as String;
    child['canonicalSignature'] = encodedCanonical;
    child['id'] =
        id.substring(0, id.length - 64) +
        crypto.sha256.convert(utf8.encode(encodedCanonical)).toString();
    child['returnType'] = {'kind': 'primitive', 'name': 'string'};
    return;
  }
  throw StateError('No signature-child type literal found.');
}
