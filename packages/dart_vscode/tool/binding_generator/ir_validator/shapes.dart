part of '../ir_validator.dart';

// Validates registered type literals and the shapes their children must match.

/// Validates the registered type-literal graph across the inventory.
void validateIrTypeLiteralGraph(
  Map<String, Map<String, Object?>> declarationsById,
  Map<String, String> declarationPathsById,
) {
  final inbound = <String, int>{};

  void visit(Object? value, String ownerId, String path) {
    if (value is List<Object?>) {
      for (var index = 0; index < value.length; index += 1) {
        visit(value[index], ownerId, '$path[$index]');
      }
      return;
    }
    if (value is! Map<Object?, Object?>) {
      return;
    }
    final map = value.cast<String, Object?>();
    if (map['kind'] == 'typeLiteral' && map.containsKey('id')) {
      final id = string(map['id'], '$path.id');
      final declaration = declarationsById[id];
      if (declaration == null || declaration['kind'] != 'typeLiteral') {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path.id $id must resolve to a registered typeLiteral declaration.',
        );
      }
      if (declaration['shapeHash'] != map['shapeHash']) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path.shapeHash must match registered typeLiteral declaration $id.',
        );
      }
      if (declaration['parentId'] != ownerId) {
        throw VSCodeBindingGenerationException(
          'INVALID_GENERATOR_INPUT',
          '$path typeLiteral $id must remain bound to owner $ownerId.',
        );
      }
      inbound[id] = (inbound[id] ?? 0) + 1;
    }
    for (final entry in map.entries) {
      visit(entry.value, ownerId, '$path.${entry.key}');
    }
  }

  for (final entry in declarationsById.entries) {
    final path = declarationPathsById[entry.key]!;
    for (final field in entry.value.entries) {
      visit(field.value, entry.key, '$path.${field.key}');
    }
  }
  for (final declaration in declarationsById.values) {
    if (declaration['kind'] != 'typeLiteral') {
      continue;
    }
    final id = declaration['id']! as String;
    if ((inbound[id] ?? 0) == 0) {
      final path = declarationPathsById[id]!;
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path typeLiteral $id must have an inbound registered reference.',
      );
    }
  }
  _validateIrRegisteredTypeLiteralShapes(
    declarationsById,
    declarationPathsById,
  );
}

void _validateIrRegisteredTypeLiteralShapes(
  Map<String, Map<String, Object?>> declarationsById,
  Map<String, String> declarationPathsById,
) {
  final childrenByParent = <String, List<Map<String, Object?>>>{};
  for (final declaration in declarationsById.values) {
    childrenByParent
        .putIfAbsent(declaration['parentId']! as String, () => [])
        .add(declaration);
  }
  for (final declaration in declarationsById.values) {
    if (declaration['kind'] != 'typeLiteral') {
      continue;
    }
    final id = declaration['id']! as String;
    final path = declarationPathsById[id]!;
    final shape = _registeredTypeLiteralShape(declaration, path);
    final expected = sha256.convert(utf8.encode(jsonEncode(shape))).toString();
    if (declaration['shapeHash'] != expected) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.shapeHash must commit to its canonical shape as $expected.',
      );
    }
    _validateRegisteredShapeChildren(
      shape: shape,
      children: childrenByParent[id] ?? const [],
      declarationsById: declarationsById,
      declarationPathsById: declarationPathsById,
      path: path,
    );
  }
}

Map<String, Object?> _registeredTypeLiteralShape(
  Map<String, Object?> declaration,
  String path,
) {
  final shape = declaration['shape'];
  if (shape is! Map<Object?, Object?> ||
      shape.keys.length != 1 ||
      shape['members'] is! List<Object?>) {
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.shape must be an object with exactly a members list.',
    );
  }
  const memberKeysByKind = <String, Set<String>>{
    'property': {'kind', 'name', 'optional', 'readonly', 'type'},
    'method': {'kind', 'signature', 'name', 'optional', 'static', 'abstract'},
    'callSignature': {'kind', 'signature'},
    'indexSignature': {'kind', 'signature', 'readonly'},
  };
  final members = shape['members']! as List<Object?>;
  for (var index = 0; index < members.length; index += 1) {
    final member = members[index];
    if (member is! Map<Object?, Object?>) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.shape.members[$index] must be an object.',
      );
    }
    final expectedKeys = memberKeysByKind[member['kind']];
    final actualKeys = member.keys.whereType<String>().toSet();
    if (expectedKeys == null ||
        actualKeys.length != member.keys.length ||
        actualKeys.length != expectedKeys.length ||
        !actualKeys.containsAll(expectedKeys)) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.shape.members[$index] has an unsupported member schema.',
      );
    }
    final kind = member['kind']! as String;
    final name = member['name'];
    final namedMember = kind == 'property' || kind == 'method';
    final validValues =
        (!namedMember || (name is String && name.isNotEmpty)) &&
        (!actualKeys.contains('optional') || member['optional'] is bool) &&
        (!actualKeys.contains('readonly') || member['readonly'] is bool) &&
        (!actualKeys.contains('static') || member['static'] is bool) &&
        (!actualKeys.contains('abstract') || member['abstract'] is bool) &&
        (!actualKeys.contains('signature') ||
            member['signature'] is Map<Object?, Object?>) &&
        (!actualKeys.contains('type') ||
            member['type'] is Map<Object?, Object?> ||
            member['type'] is List<Object?>);
    if (!validValues) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.shape.members[$index] has an unsupported member schema.',
      );
    }
  }
  return shape.cast<String, Object?>();
}

void _validateRegisteredShapeChildren({
  required Map<String, Object?> shape,
  required List<Map<String, Object?>> children,
  required Map<String, Map<String, Object?>> declarationsById,
  required Map<String, String> declarationPathsById,
  required String path,
}) {
  VSCodeBindingGenerationException mismatch(String detail) =>
      VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.shape members must match the canonical children committed '
            'by shapeHash: $detail.',
      );

  final members = [
    for (final member in shape['members']! as List<Object?>)
      (member! as Map<Object?, Object?>).cast<String, Object?>(),
  ];
  if (members.length != children.length) {
    throw mismatch(
      'expected ${members.length} children, found ${children.length}',
    );
  }
  final used = <Map<String, Object?>>{};
  final signatureOrdinals = <String, int>{};
  for (final member in members) {
    final kind = member['kind']! as String;
    if (kind == 'property') {
      final name = member['name'];
      final matches = children
          .where(
            (child) => child['kind'] == 'property' && child['name'] == name,
          )
          .toList();
      if (matches.length != 1 || !used.add(matches.single)) {
        throw mismatch('property $name has no unique child declaration');
      }
      final child = matches.single;
      if (member['optional'] != child['optional'] ||
          member['readonly'] != child['readonly']) {
        throw mismatch('property $name flags diverge');
      }
      final scopes = irInheritedTypeParameterScopes(
        child,
        declarationsById,
        declarationPathsById[child['id']!]!,
      );
      final childType = scopes.any((scope) => scope.isNotEmpty)
          ? _canonicalizeIrType(child['type'], scopes)
          : child['type'];
      if (!_shapeTypeMatchesChildType(
        member['type'],
        childType,
        declarationsById,
      )) {
        throw mismatch('property $name type diverges');
      }
    } else if (kind == 'method' ||
        kind == 'callSignature' ||
        kind == 'indexSignature') {
      final name = member['name'];
      final ordinal = signatureOrdinals.update(
        '$kind@${name ?? ''}',
        (value) => value + 1,
        ifAbsent: () => 0,
      );
      final matches = children
          .where(
            (child) =>
                child['kind'] == kind &&
                child['overloadOrdinal'] == ordinal &&
                (name == null || child['name'] == name),
          )
          .toList();
      if (matches.length != 1 || !used.add(matches.single)) {
        throw mismatch('$kind ${name ?? ordinal} has no unique child');
      }
      final child = matches.single;
      final canonical =
          (jsonDecode(child['canonicalSignature']! as String)
                  as Map<Object?, Object?>)
              .cast<String, Object?>();
      if (kind == 'method') {
        canonical
          ..remove('static')
          ..remove('optional');
        if (member['optional'] != child['optional'] ||
            member['static'] != child['static'] ||
            member['abstract'] != child['abstract']) {
          throw mismatch('method $name flags diverge');
        }
      }
      if (kind == 'indexSignature') {
        canonical.remove('readonly');
        if (member['readonly'] != child['readonly']) {
          throw mismatch('index signature flags diverge');
        }
      }
      if (_encodeCanonicalJson(member['signature']) !=
          _encodeCanonicalJson(canonical)) {
        throw mismatch('$kind ${name ?? ordinal} signature diverges');
      }
    } else {
      throw mismatch('unsupported member kind $kind');
    }
  }
}

bool _shapeTypeMatchesChildType(
  Object? shapeType,
  Object? childType,
  Map<String, Map<String, Object?>> declarationsById,
) {
  if (shapeType is List<Object?>) {
    if (childType is! List<Object?> || childType.length != shapeType.length) {
      return false;
    }
    for (var index = 0; index < shapeType.length; index += 1) {
      if (!_shapeTypeMatchesChildType(
        shapeType[index],
        childType[index],
        declarationsById,
      )) {
        return false;
      }
    }
    return true;
  }
  if (shapeType is! Map<Object?, Object?>) {
    return shapeType == childType;
  }
  if (childType is! Map<Object?, Object?>) {
    return false;
  }
  final shapeMap = shapeType.cast<String, Object?>();
  final childMap = childType.cast<String, Object?>();
  if (shapeMap['kind'] == 'typeLiteral' &&
      childMap['kind'] == 'typeLiteral' &&
      shapeMap.containsKey('shape') &&
      childMap.containsKey('id')) {
    if (shapeMap['shapeHash'] != childMap['shapeHash']) {
      return false;
    }
    final registered = declarationsById[childMap['id']];
    return registered != null &&
        _encodeCanonicalJson(shapeMap['shape']) ==
            _encodeCanonicalJson(registered['shape']);
  }
  final shapeKeys = shapeMap.keys.toSet();
  if (shapeKeys.length != childMap.keys.length ||
      !childMap.keys.every(shapeKeys.contains)) {
    return false;
  }
  for (final key in shapeKeys) {
    if (!_shapeTypeMatchesChildType(
      shapeMap[key],
      childMap[key],
      declarationsById,
    )) {
      return false;
    }
  }
  return true;
}

void _validateIrTypeLiteralShape(
  Object? value,
  String path, {
  required List<List<String?>> typeParameterScopes,
}) {
  final shape = objectMap(value, path);
  validateIrExactKeys(shape, const {'members'}, path: path);
  final members = objectList(shape['members'], '$path.members');
  for (var index = 0; index < members.length; index += 1) {
    final memberPath = '$path.members[$index]';
    final member = objectMap(members[index], memberPath);
    final kind = string(member['kind'], '$memberPath.kind');
    switch (kind) {
      case 'property':
        validateIrExactKeys(
          member,
          const {'kind', 'name', 'optional', 'readonly', 'type'},
          path: memberPath,
        );
        nonEmptyString(member['name'], '$memberPath.name');
        _validateIrBoolean(member['optional'], '$memberPath.optional');
        _validateIrBoolean(member['readonly'], '$memberPath.readonly');
        if (typeParameterScopes.any((scope) => scope.isNotEmpty)) {
          _validateIrCanonicalType(
            member['type'],
            '$memberPath.type',
            typeParameterScopes: typeParameterScopes,
          );
        } else {
          _validateIrType(
            member['type'],
            '$memberPath.type',
            typeParameterScopes: typeParameterScopes,
          );
        }
      case 'method':
        validateIrExactKeys(
          member,
          const {
            'kind',
            'name',
            'signature',
            'optional',
            'static',
            'abstract',
          },
          path: memberPath,
        );
        nonEmptyString(member['name'], '$memberPath.name');
        _validateIrBoolean(member['optional'], '$memberPath.optional');
        _validateIrBoolean(member['static'], '$memberPath.static');
        _validateIrBoolean(member['abstract'], '$memberPath.abstract');
        _validateIrCanonicalSignatureObject(
          member['signature'],
          '$memberPath.signature',
          inheritedScopes: typeParameterScopes,
        );
      case 'callSignature':
        validateIrExactKeys(
          member,
          const {'kind', 'signature'},
          path: memberPath,
        );
        _validateIrCanonicalSignatureObject(
          member['signature'],
          '$memberPath.signature',
          inheritedScopes: typeParameterScopes,
        );
      case 'indexSignature':
        validateIrExactKeys(
          member,
          const {'kind', 'signature', 'readonly'},
          path: memberPath,
        );
        _validateIrBoolean(member['readonly'], '$memberPath.readonly');
        _validateIrCanonicalSignatureObject(
          member['signature'],
          '$memberPath.signature',
          inheritedScopes: typeParameterScopes,
        );
      default:
        _invalidIrValue('$memberPath.kind', kind);
    }
  }
}
