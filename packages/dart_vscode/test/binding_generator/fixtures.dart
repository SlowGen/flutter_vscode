part of '../binding_generator_test.dart';

// Builds a valid fixture: inventories, overrides, declarations, and the
// project descriptor a generation run starts from.

String _entryIdForStrategy(Map<String, Object?> entries, String strategy) {
  return entries.entries.singleWhere((entry) {
    final value = (entry.value! as Map<Object?, Object?>)
        .cast<String, Object?>();
    return value['strategy'] == strategy;
  }).key;
}

Map<String, Object?> _inventory(List<String> ids) {
  return {
    'schemaVersion': 1,
    'source': {
      'product': {
        'name': 'Visual Studio Code',
        'version': '1.129.1',
        'commit': '0' * 40,
      },
      'parser': {'name': 'typescript', 'version': 'test'},
      'inputSha256':
          'ee11e767c8ab76f6c0de8dc88222796147a6f0bc82f3a1ec644e41b39b52f2cd',
      'manifestSchema': {
        'schemaUri': 'vscode://schemas/vscode-extensions',
        'standalone': false,
        'composition': 'Contributions are composed at runtime.',
      },
      'inputs': [
        {
          'name': 'VS Code API declarations',
          'kind': 'apiDeclarations',
          'path': 'vscode.d.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vscode-dts/vscode.d.ts',
          'sha256':
              'ee11e767c8ab76f6c0de8dc88222796147a6f0bc82f3a1ec644e41b39b52f2cd',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code extension manifest schema source',
          'kind': 'extensionManifestSchemaSource',
          'path': 'extension-manifest-schema.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vs/workbench/services/extensions/common/'
              'extensionsRegistry.ts',
          'sha256':
              'feddc98984b755a95644674910aa8c671e3259f137698c581ec7e2837cb058aa',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code extension manifest validator source',
          'kind': 'extensionManifestValidatorSource',
          'path': 'extension-validator.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vs/platform/extensions/common/'
              'extensionValidator.ts',
          'sha256':
              'e8ae92aa491ab138b6f625acbbcbd7c53ff187098066ff13aebb64615202dde1',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code commands contribution schema source',
          'kind': 'contributionSchemaSource',
          'path': 'menusExtensionPoint.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vs/workbench/services/actions/common/'
              'menusExtensionPoint.ts',
          'sha256':
              'a85c943ae42b2cdef0403070f78cfb9dbe7bcdc1fce7c57bf9ca2234d1e36a33',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code string validation helper source',
          'kind': 'contributionValidationHelperSource',
          'path': 'strings.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vs/base/common/strings.ts',
          'sha256':
              'c65ae37d623cf8a1dd0a5083cbb3f09f3433342accdc220c6bb8076aa12a1eec',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code views extension point source',
          'kind': 'viewsContributionSchemaSource',
          'path': 'viewsExtensionPoint.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vs/workbench/api/browser/'
              'viewsExtensionPoint.ts',
          'sha256':
              '17006750e3af4359fa5a518bf8dcb14beb060e98bc401245302a46030172a102',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code configuration extension point source',
          'kind': 'configurationContributionSchemaSource',
          'path': 'configurationExtensionPoint.ts',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/src/vs/workbench/api/common/'
              'configurationExtensionPoint.ts',
          'sha256':
              'e9faa24f3835b807762aa069a8029c3b004b76a3e7f42ceddee598b71b26cb0a',
          'license': 'MIT',
          'licensePath': 'LICENSE.txt',
        },
        {
          'name': 'VS Code license',
          'kind': 'license',
          'path': 'LICENSE.txt',
          'version': '1.129.1',
          'commit': '0' * 40,
          'source':
              'https://raw.githubusercontent.com/microsoft/vscode/'
              '${'0' * 40}/LICENSE.txt',
          'sha256':
              '9480271317925265e806a9a196aaa33410a962fa9d4d1e248a4a5187bc8c9df9',
          'license': 'MIT',
        },
      ],
      'contributionSchemas': [
        'commands',
        'configuration',
        'views',
        'viewsContainers',
      ],
    },
    'manifestSchema': {
      'inputSha256':
          'feddc98984b755a95644674910aa8c671e3259f137698c581ec7e2837cb058aa',
      'schemaUri': 'vscode://schemas/vscode-extensions',
      'standalone': false,
      'properties': {
        'activationEvents': {
          'type': 'array',
          'items': {'type': 'string'},
        },
        'contributes': {'type': 'object'},
        'displayName': {'type': 'string'},
        'engines': {
          'type': 'object',
          'properties': {
            'vscode': {'type': 'string'},
          },
        },
        'publisher': {'type': 'string'},
      },
    },
    'manifestValidator': {
      'inputSha256':
          'e8ae92aa491ab138b6f625acbbcbd7c53ff187098066ff13aebb64615202dde1',
      'generatedManifestRules': [
        {'path': 'publisher', 'presence': 'optional', 'type': 'string'},
        {'path': 'name', 'presence': 'required', 'type': 'string'},
        {'path': 'version', 'presence': 'required', 'type': 'string'},
        {'path': 'engines', 'presence': 'required', 'type': 'object'},
        {
          'path': 'engines.vscode',
          'presence': 'required',
          'type': 'string',
        },
        {
          'path': 'activationEvents',
          'presence': 'optional',
          'type': 'string[]',
          'requiresAny': ['main', 'browser'],
        },
        {'path': 'main', 'presence': 'optional', 'type': 'string'},
      ],
      'versionPredicate': 'semver.valid',
      'engineVersionSyntax': {
        'source': r'^(\^|>=)?((\d+)|x)\.((\d+)|x)\.((\d+)|x)(\-.*)?$',
        'flags': '',
      },
      'validatorBodySha256':
          'a7df6554afff3fa5c5e021f793fc8a4662fc641ade451565a8ff59929cf5a171',
      'projectionLimits': {
        'remainingValidatorBranches': 'integrityPinnedByValidatorBodySha256',
        'semverValidImplementation': 'unprojectedExternal',
      },
    },
    'contributionSchemas': {
      'commands': {
        'inputSha256':
            'a85c943ae42b2cdef0403070f78cfb9dbe7bcdc1fce7c57bf9ca2234d1e36a33',
        'extensionPoint': 'commands',
        'accepts': ['object', 'array'],
        'itemSchema': {
          'type': 'object',
          'required': ['command', 'title'],
          'properties': {
            'category': {'type': 'string'},
            'command': {'type': 'string'},
            'enablement': {'type': 'string'},
            'icon': {
              'anyOf': [
                {'type': 'string'},
                {
                  'type': 'object',
                  'properties': {
                    'dark': {'type': 'string'},
                    'light': {'type': 'string'},
                  },
                },
              ],
            },
            'shortTitle': {'type': 'string'},
            'title': {'type': 'string'},
          },
        },
        'validation': {
          'whitespacePredicate': 'ecmascript-trim-empty',
          'nonWhitespaceStringProperties': ['command', 'title'],
          'icon': {
            'objectRequiredStringProperties': ['dark', 'light'],
          },
        },
      },
      'configuration': {
        'inputSha256':
            'e9faa24f3835b807762aa069a8029c3b004b76a3e7f42ceddee598b71b26cb0a',
        'extensionPoint': 'configuration',
        'accepts': ['object', 'array'],
        'entrySchema': {
          'type': 'object',
          'properties': {
            'order': {
              'type': 'integer',
            },
            'properties': {
              'type': 'object',
              'propertyNames': {
                'pattern': r'\S+',
              },
              'additionalProperties': <String, Object?>{},
            },
            'title': {
              'type': 'string',
            },
          },
        },
        'validation': {
          'propertyNamePattern': r'\S+',
          'titleType': 'string',
        },
      },
      'views': {
        'inputSha256':
            '17006750e3af4359fa5a518bf8dcb14beb060e98bc401245302a46030172a102',
        'extensionPoint': 'views',
        'accepts': ['object'],
        'locations': ['debug', 'explorer', 'scm', 'test'],
        'remoteLocations': ['remote'],
        'additionalLocations': true,
        'itemSchema': {
          'type': 'object',
          'required': ['id', 'name', 'icon'],
          'properties': {
            'accessibilityHelpContent': {
              'type': 'string',
            },
            'contextualTitle': {
              'type': 'string',
            },
            'icon': {
              'type': 'string',
            },
            'id': {
              'type': 'string',
            },
            'initialSize': {
              'type': 'number',
            },
            'name': {
              'type': 'string',
            },
            'type': {
              'type': 'string',
              'enum': ['tree', 'webview'],
            },
            'visibility': {
              'type': 'string',
              'enum': ['visible', 'hidden', 'collapsed'],
            },
            'when': {
              'type': 'string',
            },
          },
        },
        'remoteItemSchema': {
          'type': 'object',
          'required': ['id', 'name'],
          'properties': {
            'group': {
              'type': 'string',
            },
            'id': {
              'type': 'string',
            },
            'name': {
              'type': 'string',
            },
            'remoteName': {
              'type': ['string', 'array'],
              'items': {
                'type': 'string',
              },
            },
            'when': {
              'type': 'string',
            },
          },
        },
        'validation': {
          'requiredStringProperties': ['id', 'name'],
          'optionalStringProperties': ['when', 'icon', 'contextualTitle'],
          'visibilityEnum': ['visible', 'hidden', 'collapsed'],
        },
      },
      'viewsContainers': {
        'inputSha256':
            '17006750e3af4359fa5a518bf8dcb14beb060e98bc401245302a46030172a102',
        'extensionPoint': 'viewsContainers',
        'accepts': ['object'],
        'locations': ['activitybar', 'panel', 'secondarySidebar'],
        'itemSchema': {
          'type': 'object',
          'required': ['id', 'title', 'icon'],
          'properties': {
            'icon': {
              'type': 'string',
            },
            'id': {
              'type': 'string',
              'pattern': r'^[a-zA-Z0-9_-]+$',
            },
            'title': {
              'type': 'string',
            },
          },
        },
        'validation': {
          'whitespacePredicate': 'ecmascript-trim-empty',
          'idPattern': r'^[a-zA-Z0-9_-]+$',
          'requiredStringProperties': ['id', 'title', 'icon'],
          'nonWhitespaceStringProperties': ['id'],
          'whitespaceWarningProperties': ['title'],
        },
      },
    },
    'module': {'id': 'module:vscode', 'name': 'vscode'},
    'declarations': [for (final id in ids) _testDeclaration(id)],
  };
}

Map<String, Object?> _overrides(
  Map<String, String> strategies, {
  String vscodeVersion = '1.129.1',
  String manifestSchemaSha256 =
      'feddc98984b755a95644674910aa8c671e3259f137698c581ec7e2837cb058aa',
  String manifestValidatorSha256 =
      'e8ae92aa491ab138b6f625acbbcbd7c53ff187098066ff13aebb64615202dde1',
  String commandsContributionSchemaSha256 =
      'a85c943ae42b2cdef0403070f78cfb9dbe7bcdc1fce7c57bf9ca2234d1e36a33',
  String viewsContributionSchemaSha256 =
      '17006750e3af4359fa5a518bf8dcb14beb060e98bc401245302a46030172a102',
  String configurationContributionSchemaSha256 =
      'e9faa24f3835b807762aa069a8029c3b004b76a3e7f42ceddee598b71b26cb0a',
  List<String>? targets,
}) {
  return {
    'schemaVersion': 1,
    'vscodeVersion': vscodeVersion,
    'manifestSchemaSha256': manifestSchemaSha256,
    'manifestValidatorSha256': manifestValidatorSha256,
    'commandsContributionSchemaSha256': commandsContributionSchemaSha256,
    'viewsContributionSchemaSha256': viewsContributionSchemaSha256,
    'configurationContributionSchemaSha256':
        configurationContributionSchemaSha256,
    'hostContracts': {
      'testExtensionHost': {
        'boundary': 'vscodeExtensionHost',
        'artifact': 'tool/bindings/contracts/test-extension-host.json',
        'artifactSha256':
            '0000000000000000000000000000000000000000000000000000000000000000',
      },
    },
    'targets': targets ?? strategies.keys.toList(),
    'entries': {
      for (final entry in strategies.entries)
        entry.key: {
          'strategy': entry.value,
          'declarationSha256': computeDeclarationFingerprint(
            _testDeclaration(entry.key),
          ),
          if (entry.value != 'reviewedExcluded')
            'hostContract': 'testExtensionHost',
        },
    },
  };
}

Map<String, Object?> _testDeclaration(String id) {
  return {
    'id': id,
    'kind': 'interface',
    'name': id.substring(id.lastIndexOf('.') + 1),
    'qualifiedName': id.substring(id.indexOf(':') + 1),
    'parentId': 'module:vscode',
    'deprecated': false,
    'typeParameters': <Object?>[],
    'extends': <Object?>[],
    'visibility': 'public',
    'coverage': {
      'discovery': 'discovered',
      'semantics': 'pending',
      'binding': 'pending',
      'host': 'pending',
    },
  };
}

Map<String, Object?> _pendingCoverage() {
  return {
    'discovery': 'discovered',
    'semantics': 'pending',
    'binding': 'pending',
    'host': 'pending',
  };
}

String _sha256String(String value) {
  return crypto.sha256.convert(utf8.encode(value)).toString();
}

String _shapeHash(Map<String, Object?> shape) {
  return _sha256String(jsonEncode(shape));
}

Map<String, Object?> _schemaOverrideFor(
  Map<String, Object?> declaration,
) {
  final id = declaration['id']! as String;
  final overrides = _overrides({id: 'opaqueJsObject'});
  final entry =
      ((overrides['entries']! as Map<Object?, Object?>)[id]!
              as Map<Object?, Object?>)
          .cast<String, Object?>();
  entry['declarationSha256'] = computeDeclarationFingerprint(declaration);
  return overrides;
}

Map<String, Object?> _sourceInput(
  Map<String, Object?> inventory,
  String kind,
) {
  final source = (inventory['source']! as Map<Object?, Object?>)
      .cast<String, Object?>();
  final inputs = (source['inputs']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  return inputs
      .singleWhere((candidate) => candidate['kind'] == kind)
      .cast<String, Object?>();
}

Map<String, Object?> _unselectedCallable(Map<String, Object?> inventory) {
  final override = _readJson(
    'tool/bindings/overrides/vscode-1.129.1.json',
  );
  final targets = (override['targets']! as List<Object?>)
      .cast<String>()
      .toSet();
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  return declarations
      .firstWhere(
        (candidate) =>
            const {
              'function',
              'constructor',
              'callSignature',
              'method',
              'indexSignature',
            }.contains(candidate['kind']) &&
            !targets.contains(candidate['id']),
      )
      .cast<String, Object?>();
}

Map<String, Object?> _unselectedDeclarationOfKind(
  Map<String, Object?> inventory,
  String kind,
) {
  final override = _readJson(
    'tool/bindings/overrides/vscode-1.129.1.json',
  );
  final targets = (override['targets']! as List<Object?>)
      .cast<String>()
      .toSet();
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final matches = declarations.where(
    (candidate) =>
        candidate['kind'] == kind && !targets.contains(candidate['id']),
  );
  if (matches.isNotEmpty) {
    return matches.first.cast<String, Object?>();
  }
  if (kind != 'callSignature') {
    throw StateError('No unselected $kind declaration.');
  }
  final occupiedParents = declarations
      .where((candidate) => candidate['kind'] == 'callSignature')
      .map((candidate) => candidate['parentId'])
      .toSet();
  final parent = declarations.firstWhere(
    (candidate) =>
        candidate['kind'] == 'interface' &&
        !targets.contains(candidate['id']) &&
        !occupiedParents.contains(candidate['id']),
  );
  final template = declarations.firstWhere(
    (candidate) => candidate['kind'] == 'callSignature',
  );
  final clone = (jsonDecode(jsonEncode(template)) as Map<Object?, Object?>)
      .cast<String, Object?>();
  final parentId = parent['id']! as String;
  final qualifiedName = '${parent['qualifiedName']}.\$call';
  clone
    ..['parentId'] = parentId
    ..['qualifiedName'] = qualifiedName
    ..['visibility'] = parent['visibility']
    ..['coverage'] = _pendingCoverage()
    ..remove('occurrenceCount');
  clone['id'] =
      'callSignature:$qualifiedName@'
      '${_sha256String(clone['canonicalSignature']! as String)}';
  (inventory['declarations']! as List<Object?>).add(clone);
  _sortDeclarationsLikeProducer(inventory);
  return clone;
}

Map<String, Object?> _rawParameter(
  String name,
  Map<String, Object?> type,
) {
  return {
    'name': name,
    'optional': false,
    'rest': false,
    'type': type,
  };
}

Map<String, Object?> _canonicalParameter(Map<String, Object?> type) {
  return {'optional': false, 'rest': false, 'type': type};
}

Map<String, Object?> _syntheticMethod({
  List<Object?> rawTypeParameters = const [],
  List<Object?>? canonicalTypeParameters,
  List<Object?> rawParameters = const [],
  List<Object?>? canonicalParameters,
  Map<String, Object?> rawReturnType = const {
    'kind': 'primitive',
    'name': 'void',
  },
  Map<String, Object?>? canonicalReturnType,
  bool staticMember = false,
  bool optional = false,
  bool? canonicalStatic,
  bool? canonicalOptional,
}) {
  final canonicalSignature = jsonEncode({
    'typeParameters': canonicalTypeParameters ?? <Object?>[],
    'parameters': canonicalParameters ?? <Object?>[],
    'returnType': canonicalReturnType ?? rawReturnType,
    'static': canonicalStatic ?? staticMember,
    'optional': canonicalOptional ?? optional,
  });
  return {
    'id':
        'method:vscode.Known.synthetic@'
        '${_sha256String(canonicalSignature)}',
    'kind': 'method',
    'name': 'synthetic',
    'qualifiedName': 'vscode.Known.synthetic',
    'parentId': 'interface:vscode.Known',
    'deprecated': false,
    'visibility': 'public',
    'overloadOrdinal': 0,
    'canonicalSignature': canonicalSignature,
    'typeParameters': rawTypeParameters,
    'parameters': rawParameters,
    'returnType': rawReturnType,
    'static': staticMember,
    'optional': optional,
    'abstract': false,
    'coverage': _pendingCoverage(),
  };
}

List<List<String>> _fixtureInheritedScopes(
  Map<String, Object?> declaration,
  Map<String, Map<String, Object?>> declarationsById,
) {
  final ancestors = <Map<String, Object?>>[];
  var parentId = declaration['parentId']! as String;
  while (parentId != 'module:vscode' && parentId != 'global:global') {
    final parent = declarationsById[parentId]!;
    ancestors.add(parent);
    parentId = parent['parentId']! as String;
  }
  return [
    for (final ancestor in ancestors.reversed)
      if (const {
        'interface',
        'class',
        'typeAlias',
        'function',
        'constructor',
        'callSignature',
        'method',
        'indexSignature',
      }.contains(ancestor['kind']))
        [
          for (final parameter in ancestor['typeParameters']! as List<Object?>)
            (parameter! as Map<Object?, Object?>)['name']! as String,
        ],
  ];
}

String _fixtureCanonicalSignature(
  Map<String, Object?> callable,
  List<List<String>> inheritedScopes,
) {
  final rawTypeParameters = callable['typeParameters']! as List<Object?>;
  final ownScope = <String>[
    for (final value in rawTypeParameters)
      (value! as Map<Object?, Object?>)['name']! as String,
  ];
  final scopes = [...inheritedScopes, ownScope];
  return jsonEncode({
    'typeParameters': [
      for (final value in rawTypeParameters)
        _fixtureCanonicalTypeParameter(
          (value! as Map<Object?, Object?>).cast<String, Object?>(),
          scopes,
        ),
    ],
    'parameters': [
      for (final value in callable['parameters']! as List<Object?>)
        _fixtureCanonicalParameter(
          (value! as Map<Object?, Object?>).cast<String, Object?>(),
          scopes,
        ),
    ],
    'returnType': _fixtureCanonicalType(callable['returnType'], scopes),
    if (callable['kind'] == 'method') ...{
      'static': callable['static'],
      'optional': callable['optional'],
    },
    if (callable['kind'] == 'indexSignature') 'readonly': callable['readonly'],
  });
}

Map<String, Object?> _fixtureCanonicalTypeParameter(
  Map<String, Object?> parameter,
  List<List<String>> scopes,
) {
  return {
    if (parameter.containsKey('constraint'))
      'constraint': _fixtureCanonicalType(parameter['constraint'], scopes),
    if (parameter.containsKey('default'))
      'default': _fixtureCanonicalType(parameter['default'], scopes),
  };
}

Map<String, Object?> _fixtureCanonicalParameter(
  Map<String, Object?> parameter,
  List<List<String>> scopes,
) {
  return {
    'optional': parameter['optional'],
    'rest': parameter['rest'],
    'type': _fixtureCanonicalType(parameter['type'], scopes),
  };
}

Object? _fixtureCanonicalType(
  Object? value,
  List<List<String>> scopes,
) {
  final type = (value! as Map<Object?, Object?>).cast<String, Object?>();
  final kind = type['kind'];
  if (kind == 'reference') {
    final name = type['name']! as String;
    for (var scopeIndex = scopes.length - 1; scopeIndex >= 0; scopeIndex -= 1) {
      final index = scopes[scopeIndex].indexOf(name);
      if (index >= 0) {
        final depth = scopes.length - 1 - scopeIndex;
        return depth == 0
            ? <String, Object?>{'kind': 'typeParameter', 'index': index}
            : <String, Object?>{
                'kind': 'outerTypeParameter',
                'depth': depth,
                'index': index,
              };
      }
    }
  }
  return switch (kind) {
    'primitive' => <String, Object?>{
      'kind': kind,
      'name': type['name'],
    },
    'reference' => <String, Object?>{
      'kind': kind,
      'name': type['name'],
      'typeArguments': [
        for (final argument in type['typeArguments']! as List<Object?>)
          _fixtureCanonicalType(argument, scopes),
      ],
    },
    'array' => <String, Object?>{
      'kind': kind,
      'elementType': _fixtureCanonicalType(type['elementType'], scopes),
    },
    'union' || 'intersection' => <String, Object?>{
      'kind': kind,
      'types': [
        for (final item in type['types']! as List<Object?>)
          _fixtureCanonicalType(item, scopes),
      ],
    },
    'literal' => <String, Object?>{
      'kind': kind,
      'value': type['value'],
    },
    'tuple' => <String, Object?>{
      'kind': kind,
      'elements': [
        for (final value in type['elements']! as List<Object?>)
          _fixtureCanonicalTupleElement(
            (value! as Map<Object?, Object?>).cast<String, Object?>(),
            scopes,
          ),
      ],
    },
    'operator' => <String, Object?>{
      'kind': kind,
      'operator': type['operator'],
      'type': _fixtureCanonicalType(type['type'], scopes),
    },
    'function' => <String, Object?>{
      'kind': kind,
      'canonicalSignature': _synchronizeFixtureFunctionType(type, scopes),
    },
    'typeLiteral' => <String, Object?>{
      'kind': kind,
      'shapeHash': type['shapeHash'],
    },
    _ => throw StateError('Unsupported fixture type kind $kind.'),
  };
}

Map<String, Object?> _fixtureCanonicalTupleElement(
  Map<String, Object?> element,
  List<List<String>> scopes,
) {
  return {
    'optional': element['optional'],
    'rest': element['rest'],
    'type': _fixtureCanonicalType(element['type'], scopes),
  };
}

void _sortDeclarationsLikeProducer(Map<String, Object?> inventory) {
  (inventory['declarations']! as List<Object?>).sort((leftValue, rightValue) {
    final left = leftValue! as Map<Object?, Object?>;
    final right = rightValue! as Map<Object?, Object?>;
    final qualified = (left['qualifiedName']! as String).compareTo(
      right['qualifiedName']! as String,
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
    return (left['id']! as String).compareTo(right['id']! as String);
  });
}

Map<String, Object?> _soleUnselectedCallable(Map<String, Object?> inventory) {
  final override = _readJson(
    'tool/bindings/overrides/vscode-1.129.1.json',
  );
  final targets = (override['targets']! as List<Object?>)
      .cast<String>()
      .toSet();
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  final callables = declarations.where(
    (candidate) =>
        const {
          'function',
          'constructor',
          'callSignature',
          'method',
          'indexSignature',
        }.contains(candidate['kind']) &&
        !targets.contains(candidate['id']),
  );
  return callables.firstWhere((candidate) {
    final matches = callables.where(
      (other) =>
          other['kind'] == candidate['kind'] &&
          other['qualifiedName'] == candidate['qualifiedName'] &&
          other['static'] == candidate['static'],
    );
    return matches.length == 1;
  }).cast<String, Object?>();
}

({Map<String, Object?> first, Map<String, Object?> second})
_sameShapeTypeLiteralReferencePair(Map<String, Object?> inventory) {
  final references = <Map<String, Object?>>[];

  void visit(Object? value) {
    if (value is List<Object?>) {
      value.forEach(visit);
      return;
    }
    if (value is! Map<Object?, Object?>) {
      return;
    }
    final map = value.cast<String, Object?>();
    if (map['kind'] == 'typeLiteral' && map.containsKey('id')) {
      references.add(map);
    }
    map.values.forEach(visit);
  }

  final declarations = inventory['declarations']! as List<Object?>;
  for (final declarationValue in declarations) {
    final declaration = declarationValue! as Map<Object?, Object?>;
    declaration.values.forEach(visit);
  }
  for (final first in references) {
    final second = references.cast<Map<String, Object?>?>().firstWhere(
      (candidate) =>
          candidate != null &&
          candidate['id'] != first['id'] &&
          candidate['shapeHash'] == first['shapeHash'],
      orElse: () => null,
    );
    if (second != null) {
      return (first: first, second: second);
    }
  }
  throw StateError('No same-shape registered type-literal pair found.');
}

({Map<String, Object?> parent, Map<String, Object?> child})
_singlePropertyTypeLiteral(Map<String, Object?> inventory) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  for (final candidate in declarations) {
    if (candidate['kind'] != 'typeLiteral') {
      continue;
    }
    final children = declarations
        .where((child) => child['parentId'] == candidate['id'])
        .toList();
    if (children.length == 1 && children.single['kind'] == 'property') {
      return (
        parent: candidate.cast<String, Object?>(),
        child: children.single.cast<String, Object?>(),
      );
    }
  }
  throw StateError('No single-property type literal found.');
}

Map<String, Object?> _multiPropertyTypeLiteralChild(
  Map<String, Object?> inventory,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  for (final candidate in declarations) {
    if (candidate['kind'] != 'typeLiteral') {
      continue;
    }
    final children = declarations
        .where((child) => child['parentId'] == candidate['id'])
        .toList();
    if (children.length >= 2 &&
        children.every((child) => child['kind'] == 'property')) {
      return children.first.cast<String, Object?>();
    }
  }
  throw StateError('No multi-property type literal found.');
}

Map<String, Object?> _registeredLiteralTypedPropertyChild(
  Map<String, Object?> inventory,
) {
  final declarations = (inventory['declarations']! as List<Object?>)
      .cast<Map<Object?, Object?>>();
  for (final candidate in declarations) {
    if (candidate['kind'] != 'property') {
      continue;
    }
    final parentId = candidate['parentId'] as String?;
    if (parentId == null || !parentId.startsWith('typeLiteral:')) {
      continue;
    }
    if (_containsRegisteredLiteralReference(candidate['type'])) {
      return candidate.cast<String, Object?>();
    }
  }
  throw StateError('No registered-literal-typed property child found.');
}

bool _containsRegisteredLiteralReference(Object? value) {
  if (value is List<Object?>) {
    return value.any(_containsRegisteredLiteralReference);
  }
  if (value is! Map<Object?, Object?>) {
    return false;
  }
  if (value['kind'] == 'typeLiteral' && value.containsKey('id')) {
    return true;
  }
  return value.values.any(_containsRegisteredLiteralReference);
}

/// Matches a [VSCodeBindingGenerationException] with [code], and
/// optionally a [message] matcher.
Matcher _throwsGeneration(String code, [Object? message]) => throwsA(
  isA<VSCodeBindingGenerationException>()
      .having((error) => error.code, 'code', code)
      .having((error) => error.message, 'message', message ?? anything),
);

Map<String, Object?> _readJson(String path) {
  return (jsonDecode(File(path).readAsStringSync()) as Map<Object?, Object?>)
      .cast<String, Object?>();
}
