part of '../ir_validator.dart';

// Validates the IR module envelope: its source block, declaration keys, and scalar fields.

/// Validates the inventory module descriptor.
void validateIrModule(Object? value) {
  final module = objectMap(value, 'inventory.module');
  validateIrExactKeys(
    module,
    const {'id', 'name'},
    path: 'inventory.module',
  );
  if (module['id'] != 'module:vscode' || module['name'] != 'vscode') {
    throw const VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      'inventory.module must identify module:vscode with name vscode.',
    );
  }
}

/// Validates and returns the normalized inventory source descriptor.
Map<String, Object?> validateIrSource(
  Object? value, {
  required Map<String, Object?> inventory,
}) {
  final source = objectMap(value, 'inventory.source');
  validateIrExactKeys(
    source,
    const {
      'product',
      'parser',
      'inputSha256',
      'manifestSchema',
      'inputs',
      'contributionSchemas',
    },
    path: 'inventory.source',
  );

  final product = objectMap(source['product'], 'inventory.source.product');
  validateIrExactKeys(
    product,
    const {'name', 'version', 'commit'},
    path: 'inventory.source.product',
  );
  nonEmptyString(product['name'], 'inventory.source.product.name');
  nonEmptyString(product['version'], 'inventory.source.product.version');
  _validateIrCommit(product['commit'], 'inventory.source.product.commit');

  final parser = objectMap(source['parser'], 'inventory.source.parser');
  validateIrExactKeys(
    parser,
    const {'name', 'version'},
    path: 'inventory.source.parser',
  );
  if (parser['name'] != 'typescript') {
    _invalidIrValue('inventory.source.parser.name', parser['name']);
  }
  nonEmptyString(parser['version'], 'inventory.source.parser.version');
  _validateIrSha256(
    source['inputSha256'],
    'inventory.source.inputSha256',
  );

  final manifestSchema = objectMap(
    source['manifestSchema'],
    'inventory.source.manifestSchema',
  );
  validateIrExactKeys(
    manifestSchema,
    const {'schemaUri', 'standalone', 'composition'},
    path: 'inventory.source.manifestSchema',
  );
  nonEmptyString(
    manifestSchema['schemaUri'],
    'inventory.source.manifestSchema.schemaUri',
  );
  _validateIrBoolean(
    manifestSchema['standalone'],
    'inventory.source.manifestSchema.standalone',
  );
  nonEmptyString(
    manifestSchema['composition'],
    'inventory.source.manifestSchema.composition',
  );

  final inputs = objectList(source['inputs'], 'inventory.source.inputs');
  if (inputs.isEmpty) {
    throw const VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      'inventory.source.inputs must contain pinned source receipts.',
    );
  }
  final inputsByKind = <String, List<Map<String, Object?>>>{};
  for (var index = 0; index < inputs.length; index += 1) {
    final path = 'inventory.source.inputs[$index]';
    final input = objectMap(inputs[index], path);
    validateIrExactKeys(
      input,
      const {
        'name',
        'kind',
        'path',
        'version',
        'commit',
        'source',
        'sha256',
        'license',
      },
      optionalKeys: const {'licensePath'},
      path: path,
    );
    for (final key in const [
      'name',
      'path',
      'version',
      'source',
      'license',
    ]) {
      nonEmptyString(input[key], '$path.$key');
    }
    final kind = string(input['kind'], '$path.kind');
    if (!const {
      'apiDeclarations',
      'extensionManifestSchemaSource',
      'extensionManifestValidatorSource',
      'contributionSchemaSource',
      'contributionValidationHelperSource',
      'viewsContributionSchemaSource',
      'configurationContributionSchemaSource',
      'license',
    }.contains(kind)) {
      _invalidIrValue('$path.kind', kind);
    }
    _validateIrCommit(input['commit'], '$path.commit');
    _validateIrSha256(input['sha256'], '$path.sha256');
    if (input.containsKey('licensePath')) {
      nonEmptyString(input['licensePath'], '$path.licensePath');
    }
    inputsByKind.putIfAbsent(kind, () => []).add(input);
  }

  final contributionSchemas = objectList(
    source['contributionSchemas'],
    'inventory.source.contributionSchemas',
  );
  final schemaNames = <String>[
    for (var index = 0; index < contributionSchemas.length; index += 1)
      nonEmptyString(
        contributionSchemas[index],
        'inventory.source.contributionSchemas[$index]',
      ),
  ];
  const expectedSchemaNames = [
    'commands',
    'configuration',
    'views',
    'viewsContainers',
  ];
  if (schemaNames.join(',') != expectedSchemaNames.join(',')) {
    throw const VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      'inventory.source.contributionSchemas must contain exactly commands, '
          'configuration, views, viewsContainers.',
    );
  }
  const officialSourcePathByKind = <String, String>{
    'apiDeclarations': 'src/vscode-dts/vscode.d.ts',
    'extensionManifestSchemaSource':
        'src/vs/workbench/services/extensions/common/extensionsRegistry.ts',
    'extensionManifestValidatorSource':
        'src/vs/platform/extensions/common/extensionValidator.ts',
    'contributionSchemaSource':
        'src/vs/workbench/services/actions/common/menusExtensionPoint.ts',
    'contributionValidationHelperSource': 'src/vs/base/common/strings.ts',
    'viewsContributionSchemaSource':
        'src/vs/workbench/api/browser/viewsExtensionPoint.ts',
    'configurationContributionSchemaSource':
        'src/vs/workbench/api/common/configurationExtensionPoint.ts',
    'license': 'LICENSE.txt',
  };
  for (final entry in officialSourcePathByKind.entries) {
    final matches = inputsByKind[entry.key] ?? const [];
    if (matches.length != 1) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        'inventory.source.inputs must contain exactly one ${entry.key} '
            'receipt; found ${matches.length}.',
      );
    }
    final input = matches.single;
    final productVersion = string(
      product['version'],
      'inventory.source.product.version',
    );
    final productCommit = string(
      product['commit'],
      'inventory.source.product.commit',
    );
    if (input['version'] != productVersion ||
        input['commit'] != productCommit) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        'inventory.source.inputs ${entry.key} receipt must match product '
            '$productVersion@$productCommit.',
      );
    }
    final expectedSource =
        'https://raw.githubusercontent.com/microsoft/vscode/'
        '$productCommit/${entry.value}';
    if (input['source'] != expectedSource) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        'inventory.source.inputs ${entry.key} source must be the canonical '
            'microsoft/vscode URL $expectedSource.',
      );
    }
  }

  String receiptSha(String kind) =>
      string(inputsByKind[kind]!.single['sha256'], 'inventory.source.inputs');
  void requireReceiptSha(String actual, String kind, String path) {
    _validateIrSha256(actual, path);
    final expected = receiptSha(kind);
    if (actual != expected) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path must match the inventory.source.inputs $kind receipt SHA-256 '
            '$expected.',
      );
    }
  }

  requireReceiptSha(
    string(source['inputSha256'], 'inventory.source.inputSha256'),
    'apiDeclarations',
    'inventory.source.inputSha256',
  );
  final projectedManifest = objectMap(
    inventory['manifestSchema'],
    'inventory.manifestSchema',
  );
  requireReceiptSha(
    string(
      projectedManifest['inputSha256'],
      'inventory.manifestSchema.inputSha256',
    ),
    'extensionManifestSchemaSource',
    'inventory.manifestSchema.inputSha256',
  );
  if (projectedManifest['schemaUri'] != manifestSchema['schemaUri'] ||
      projectedManifest['standalone'] != manifestSchema['standalone']) {
    throw const VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      'inventory.source.manifestSchema must match the projected '
          'inventory.manifestSchema identity.',
    );
  }
  final projectedValidator = objectMap(
    inventory['manifestValidator'],
    'inventory.manifestValidator',
  );
  requireReceiptSha(
    string(
      projectedValidator['inputSha256'],
      'inventory.manifestValidator.inputSha256',
    ),
    'extensionManifestValidatorSource',
    'inventory.manifestValidator.inputSha256',
  );
  final projectedContributions = objectMap(
    inventory['contributionSchemas'],
    'inventory.contributionSchemas',
  );
  final projectedCommands = objectMap(
    projectedContributions['commands'],
    'inventory.contributionSchemas.commands',
  );
  requireReceiptSha(
    string(
      projectedCommands['inputSha256'],
      'inventory.contributionSchemas.commands.inputSha256',
    ),
    'contributionSchemaSource',
    'inventory.contributionSchemas.commands.inputSha256',
  );
  return source;
}

/// Validates the exact key set of one inventory declaration.
void validateIrDeclarationKeys(
  Map<String, Object?> declaration,
  String path,
) {
  const common = {
    'id',
    'kind',
    'name',
    'qualifiedName',
    'parentId',
    'deprecated',
    'visibility',
    'coverage',
  };
  const callable = {
    ...common,
    'overloadOrdinal',
    'canonicalSignature',
    'typeParameters',
    'parameters',
    'returnType',
  };
  final kind = string(declaration['kind'], '$path.kind');
  final requiredKeys = switch (kind) {
    'namespace' => common,
    'interface' => {...common, 'typeParameters', 'extends'},
    'class' => {
      ...common,
      'abstract',
      'typeParameters',
      'extends',
      'implements',
    },
    'enum' => {...common, 'constant'},
    'enumMember' => {...common, 'initializer'},
    'typeAlias' => {...common, 'typeParameters', 'type'},
    'variable' => {...common, 'constant', 'declarationKind', 'type'},
    'property' => {
      ...common,
      'optional',
      'readonly',
      'static',
      'abstract',
      'type',
    },
    'function' || 'constructor' || 'callSignature' => callable,
    'method' => {...callable, 'static', 'optional', 'abstract'},
    'indexSignature' => {...callable, 'readonly'},
    'typeLiteral' => {...common, 'shapeHash', 'shape'},
    _ => throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '$path.kind has unsupported IR declaration kind $kind.',
    ),
  };
  validateIrExactKeys(
    declaration,
    requiredKeys,
    optionalKeys: const {'occurrenceCount'},
    path: path,
  );
  _validateIrDeclarationScalars(declaration, path);
  _validateIrCoverage(
    declaration['coverage'],
    '$path.coverage',
    visibility: string(declaration['visibility'], '$path.visibility'),
  );
}

void _validateIrDeclarationScalars(
  Map<String, Object?> declaration,
  String path,
) {
  nonEmptyString(declaration['id'], '$path.id');
  nonEmptyString(declaration['name'], '$path.name');
  nonEmptyString(declaration['qualifiedName'], '$path.qualifiedName');
  nonEmptyString(declaration['parentId'], '$path.parentId');
  _validateIrBoolean(declaration['deprecated'], '$path.deprecated');
  final visibility = string(declaration['visibility'], '$path.visibility');
  if (!const {'public', 'protected', 'private'}.contains(visibility)) {
    _invalidIrValue('$path.visibility', visibility);
  }
  if (declaration.containsKey('occurrenceCount')) {
    final occurrenceCount = _validateIrNonNegativeInteger(
      declaration['occurrenceCount'],
      '$path.occurrenceCount',
    );
    if (occurrenceCount < 2) {
      _invalidIrValue('$path.occurrenceCount', occurrenceCount);
    }
    final kind = declaration['kind'];
    final isNonMergeable =
        const {'class', 'typeAlias', 'enumMember'}.contains(kind) ||
        (kind == 'variable' && declaration['declarationKind'] != 'var');
    if (isNonMergeable) {
      throw VSCodeBindingGenerationException(
        'INVALID_GENERATOR_INPUT',
        '$path.occurrenceCount is impossible for nonmergeable $kind '
            'declarations.',
      );
    }
  }

  final kind = declaration['kind'];
  switch (kind) {
    case 'class':
      _validateIrBoolean(declaration['abstract'], '$path.abstract');
    case 'enum':
      _validateIrBoolean(declaration['constant'], '$path.constant');
    case 'variable':
      _validateIrBoolean(declaration['constant'], '$path.constant');
      final declarationKind = string(
        declaration['declarationKind'],
        '$path.declarationKind',
      );
      if (!const {'const', 'let', 'var'}.contains(declarationKind)) {
        _invalidIrValue('$path.declarationKind', declarationKind);
      }
    case 'property':
      for (final key in const ['optional', 'readonly', 'static', 'abstract']) {
        _validateIrBoolean(declaration[key], '$path.$key');
      }
    case 'function' || 'constructor' || 'callSignature':
      _validateIrNonNegativeInteger(
        declaration['overloadOrdinal'],
        '$path.overloadOrdinal',
      );
    case 'method':
      _validateIrNonNegativeInteger(
        declaration['overloadOrdinal'],
        '$path.overloadOrdinal',
      );
      for (final key in const ['optional', 'static', 'abstract']) {
        _validateIrBoolean(declaration[key], '$path.$key');
      }
    case 'indexSignature':
      _validateIrNonNegativeInteger(
        declaration['overloadOrdinal'],
        '$path.overloadOrdinal',
      );
      _validateIrBoolean(declaration['readonly'], '$path.readonly');
    case 'typeLiteral':
      _validateIrSha256(declaration['shapeHash'], '$path.shapeHash');
  }
}

/// Requires a JSON object to match the exact v1 IR key set.
void validateIrExactKeys(
  Map<String, Object?> value,
  Set<String> requiredKeys, {
  required String path,
  Set<String> optionalKeys = const {},
}) {
  final missing = requiredKeys.where((key) => !value.containsKey(key)).toList()
    ..sort();
  final allowedKeys = {...requiredKeys, ...optionalKeys};
  final unexpected =
      value.keys.where((key) => !allowedKeys.contains(key)).toList()..sort();
  if (missing.isEmpty && unexpected.isEmpty) {
    return;
  }
  throw VSCodeBindingGenerationException(
    'INVALID_GENERATOR_INPUT',
    '$path does not match the exact v1 IR schema; missing '
        '${missing.isEmpty ? 'none' : missing.join(', ')}; unexpected '
        '${unexpected.isEmpty ? 'none' : unexpected.join(', ')}.',
  );
}
