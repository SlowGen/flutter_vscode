/// The pinned-projection checks of the binding pipeline: byte-compares
/// the imported manifest schema, manifest validator, and contribution
/// schema extractions against their independently reviewed Dart
/// projections in `package:dart_vscode`.
library;

import 'dart:convert';

import 'package:dart_vscode/src/contributions/json_values.dart';

import 'generator.dart';
import 'validators.dart';

/// Validates the pinned manifest schema projection and returns its input hash.
String validateManifestSchema(Map<String, Object?> inventory) {
  final schema = objectMap(
    inventory['manifestSchema'],
    'inventory.manifestSchema',
  );
  final inputSha256 = sha256Digest(
    schema['inputSha256'],
    'inventory.manifestSchema.inputSha256',
  );
  const expectedProjection = <String, Object?>{
    'schemaUri': 'vscode://schemas/vscode-extensions',
    'standalone': false,
    'properties': <String, Object?>{
      'activationEvents': <String, Object?>{
        'type': 'array',
        'items': <String, Object?>{'type': 'string'},
      },
      'contributes': <String, Object?>{'type': 'object'},
      'displayName': <String, Object?>{'type': 'string'},
      'engines': <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'vscode': <String, Object?>{'type': 'string'},
        },
      },
      'publisher': <String, Object?>{'type': 'string'},
    },
  };
  _expectReviewedProjection(
    schema,
    expectedProjection,
    'inventory.manifestSchema',
    subject: 'Pinned manifest schema',
  );
  return inputSha256;
}

/// Validates the pinned manifest validator projection and returns its input hash.
String validateManifestValidator(Map<String, Object?> inventory) {
  final validator = objectMap(
    inventory['manifestValidator'],
    'inventory.manifestValidator',
  );
  final inputSha256 = sha256Digest(
    validator['inputSha256'],
    'inventory.manifestValidator.inputSha256',
  );
  const expectedProjection = <String, Object?>{
    'generatedManifestRules': <Object?>[
      <String, Object?>{
        'path': 'publisher',
        'presence': 'optional',
        'type': 'string',
      },
      <String, Object?>{
        'path': 'name',
        'presence': 'required',
        'type': 'string',
      },
      <String, Object?>{
        'path': 'version',
        'presence': 'required',
        'type': 'string',
      },
      <String, Object?>{
        'path': 'engines',
        'presence': 'required',
        'type': 'object',
      },
      <String, Object?>{
        'path': 'engines.vscode',
        'presence': 'required',
        'type': 'string',
      },
      <String, Object?>{
        'path': 'activationEvents',
        'presence': 'optional',
        'type': 'string[]',
        'requiresAny': <Object?>['main', 'browser'],
      },
      <String, Object?>{
        'path': 'main',
        'presence': 'optional',
        'type': 'string',
      },
    ],
    'versionPredicate': 'semver.valid',
    'engineVersionSyntax': <String, Object?>{
      'source': r'^(\^|>=)?((\d+)|x)\.((\d+)|x)\.((\d+)|x)(\-.*)?$',
      'flags': '',
    },
    'validatorBodySha256':
        'a7df6554afff3fa5c5e021f793fc8a4662fc641ade451565a8ff59929cf5a171',
    'projectionLimits': <String, Object?>{
      'remainingValidatorBranches': 'integrityPinnedByValidatorBodySha256',
      'semverValidImplementation': 'unprojectedExternal',
    },
  };
  _expectReviewedProjection(
    validator,
    expectedProjection,
    'inventory.manifestValidator',
    subject: 'Pinned manifest validator',
  );
  return inputSha256;
}

/// Validates the pinned commands contribution schema and returns its input hash.
String validateCommandsContributionSchema(
  Map<String, Object?> inventory,
) {
  final schemas = objectMap(
    inventory['contributionSchemas'],
    'inventory.contributionSchemas',
  );
  const expectedSchemas = [
    'commands',
    'configuration',
    'views',
    'viewsContainers',
  ];
  final schemaNames = schemas.keys.toList()..sort();
  if (schemaNames.join(',') != expectedSchemas.join(',')) {
    throw const VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      'Inventory must contain exactly the commands, configuration, views, '
          'and viewsContainers contribution schemas.',
    );
  }
  final commands = objectMap(
    schemas['commands'],
    'inventory.contributionSchemas.commands',
  );
  final inputSha256 = sha256Digest(
    commands['inputSha256'],
    'inventory.contributionSchemas.commands.inputSha256',
  );
  const expectedProjection = <String, Object?>{
    'extensionPoint': 'commands',
    'accepts': <Object?>['object', 'array'],
    'itemSchema': <String, Object?>{
      'type': 'object',
      'required': <Object?>['command', 'title'],
      'properties': <String, Object?>{
        'category': <String, Object?>{'type': 'string'},
        'command': <String, Object?>{'type': 'string'},
        'enablement': <String, Object?>{'type': 'string'},
        'icon': <String, Object?>{
          'anyOf': <Object?>[
            <String, Object?>{'type': 'string'},
            <String, Object?>{
              'type': 'object',
              'properties': <String, Object?>{
                'dark': <String, Object?>{'type': 'string'},
                'light': <String, Object?>{'type': 'string'},
              },
            },
          ],
        },
        'shortTitle': <String, Object?>{'type': 'string'},
        'title': <String, Object?>{'type': 'string'},
      },
    },
    'validation': <String, Object?>{
      'whitespacePredicate': 'ecmascript-trim-empty',
      'nonWhitespaceStringProperties': <Object?>['command', 'title'],
      'icon': <String, Object?>{
        'objectRequiredStringProperties': <Object?>['dark', 'light'],
      },
    },
  };
  _expectReviewedProjection(
    commands,
    expectedProjection,
    'inventory.contributionSchemas.commands',
    subject: 'Commands contribution schema',
  );
  return inputSha256;
}

String _firstJsonDifferencePath(
  Object? expected,
  Object? actual,
  String path,
) {
  if (expected is Map<Object?, Object?> && actual is Map<Object?, Object?>) {
    final expectedKeys = expected.keys.whereType<String>().toSet();
    final actualKeys = actual.keys.whereType<String>().toSet();
    if (expectedKeys.length != expected.length ||
        actualKeys.length != actual.length) {
      return path;
    }
    final keys = {...expectedKeys, ...actualKeys}.toList()..sort();
    for (final key in keys) {
      final childPath = '$path.$key';
      if (!expected.containsKey(key) || !actual.containsKey(key)) {
        return childPath;
      }
      if (jsonEncode(expected[key]) != jsonEncode(actual[key])) {
        return _firstJsonDifferencePath(
          expected[key],
          actual[key],
          childPath,
        );
      }
    }
    return path;
  }
  if (expected is List<Object?> && actual is List<Object?>) {
    final sharedLength = expected.length < actual.length
        ? expected.length
        : actual.length;
    for (var index = 0; index < sharedLength; index++) {
      if (jsonEncode(expected[index]) != jsonEncode(actual[index])) {
        return _firstJsonDifferencePath(
          expected[index],
          actual[index],
          '$path[$index]',
        );
      }
    }
    return '$path[$sharedLength]';
  }
  return path;
}

/// The shared view item schema, reviewed against the pinned extraction.
const _viewItemSchema = <String, Object?>{
  'type': 'object',
  'required': <Object?>['id', 'name', 'icon'],
  'properties': <String, Object?>{
    'accessibilityHelpContent': <String, Object?>{'type': 'string'},
    'contextualTitle': <String, Object?>{'type': 'string'},
    'icon': <String, Object?>{'type': 'string'},
    'id': <String, Object?>{'type': 'string'},
    'initialSize': <String, Object?>{'type': 'number'},
    'name': <String, Object?>{'type': 'string'},
    'type': <String, Object?>{
      'type': 'string',
      'enum': <Object?>['tree', 'webview'],
    },
    'visibility': <String, Object?>{
      'type': 'string',
      'enum': <Object?>['visible', 'hidden', 'collapsed'],
    },
    'when': <String, Object?>{'type': 'string'},
  },
};

/// Validates the pinned views and viewsContainers schemas; returns their
/// shared input hash. Both live in one pinned source file, so one hash
/// covers both -- the generator refuses an inventory where they diverge.
String validateViewsContributionSchemas(Map<String, Object?> inventory) {
  final schemas = objectMap(
    inventory['contributionSchemas'],
    'inventory.contributionSchemas',
  );
  final containers = objectMap(
    schemas['viewsContainers'],
    'inventory.contributionSchemas.viewsContainers',
  );
  final views = objectMap(
    schemas['views'],
    'inventory.contributionSchemas.views',
  );
  final containersSha256 = sha256Digest(
    containers['inputSha256'],
    'inventory.contributionSchemas.viewsContainers.inputSha256',
  );
  final viewsSha256 = sha256Digest(
    views['inputSha256'],
    'inventory.contributionSchemas.views.inputSha256',
  );
  if (containersSha256 != viewsSha256) {
    throw const VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      'views and viewsContainers must share one pinned source file.',
    );
  }
  const expectedContainers = <String, Object?>{
    'extensionPoint': 'viewsContainers',
    'accepts': <Object?>['object'],
    'locations': <Object?>['activitybar', 'panel', 'secondarySidebar'],
    'itemSchema': <String, Object?>{
      'type': 'object',
      'required': <Object?>['id', 'title', 'icon'],
      'properties': <String, Object?>{
        'icon': <String, Object?>{'type': 'string'},
        'id': <String, Object?>{
          'type': 'string',
          'pattern': r'^[a-zA-Z0-9_-]+$',
        },
        'title': <String, Object?>{'type': 'string'},
      },
    },
    'validation': <String, Object?>{
      'whitespacePredicate': 'ecmascript-trim-empty',
      'idPattern': r'^[a-zA-Z0-9_-]+$',
      'requiredStringProperties': <Object?>['id', 'title', 'icon'],
      'nonWhitespaceStringProperties': <Object?>['id'],
      'whitespaceWarningProperties': <Object?>['title'],
    },
  };
  const expectedViews = <String, Object?>{
    'extensionPoint': 'views',
    'accepts': <Object?>['object'],
    'locations': <Object?>['debug', 'explorer', 'scm', 'test'],
    'remoteLocations': <Object?>['remote'],
    'additionalLocations': true,
    'itemSchema': _viewItemSchema,
    'remoteItemSchema': <String, Object?>{
      'type': 'object',
      'required': <Object?>['id', 'name'],
      'properties': <String, Object?>{
        'group': <String, Object?>{'type': 'string'},
        'id': <String, Object?>{'type': 'string'},
        'name': <String, Object?>{'type': 'string'},
        'remoteName': <String, Object?>{
          'type': <Object?>['string', 'array'],
          'items': <String, Object?>{'type': 'string'},
        },
        'when': <String, Object?>{'type': 'string'},
      },
    },
    'validation': <String, Object?>{
      'requiredStringProperties': <Object?>['id', 'name'],
      'optionalStringProperties': <Object?>['when', 'icon', 'contextualTitle'],
      'visibilityEnum': <Object?>['visible', 'hidden', 'collapsed'],
    },
  };
  _expectReviewedProjection(
    containers,
    expectedContainers,
    'inventory.contributionSchemas.viewsContainers',
  );
  _expectReviewedProjection(
    views,
    expectedViews,
    'inventory.contributionSchemas.views',
  );
  return viewsSha256;
}

/// Validates the pinned configuration schema; returns its input hash.
String validateConfigurationContributionSchema(
  Map<String, Object?> inventory,
) {
  final schemas = objectMap(
    inventory['contributionSchemas'],
    'inventory.contributionSchemas',
  );
  final configuration = objectMap(
    schemas['configuration'],
    'inventory.contributionSchemas.configuration',
  );
  final inputSha256 = sha256Digest(
    configuration['inputSha256'],
    'inventory.contributionSchemas.configuration.inputSha256',
  );
  const expected = <String, Object?>{
    'extensionPoint': 'configuration',
    'accepts': <Object?>['object', 'array'],
    'entrySchema': <String, Object?>{
      'type': 'object',
      'properties': <String, Object?>{
        'order': <String, Object?>{'type': 'integer'},
        'properties': <String, Object?>{
          'type': 'object',
          'propertyNames': <String, Object?>{'pattern': r'\S+'},
          'additionalProperties': <String, Object?>{},
        },
        'title': <String, Object?>{'type': 'string'},
      },
    },
    'validation': <String, Object?>{
      'propertyNamePattern': r'\S+',
      'titleType': 'string',
    },
  };
  _expectReviewedProjection(
    configuration,
    expected,
    'inventory.contributionSchemas.configuration',
  );
  return inputSha256;
}

void _expectReviewedProjection(
  Map<String, Object?> actual,
  Map<String, Object?> expected,
  String path, {
  String? subject,
}) {
  final projection = Map<String, Object?>.of(actual)..remove('inputSha256');
  if (jsonEncode(projection) != jsonEncode(expected)) {
    final differingPath = _firstJsonDifferencePath(expected, projection, path);
    throw VSCodeBindingGenerationException(
      'INVALID_GENERATOR_INPUT',
      '${subject ?? 'Contribution schema at $path'} contains an unprojected '
          'change. First differing path: $differingPath. Regenerate the IR '
          'from the pinned inputs; if upstream changed, review and update '
          'the generator projection before retrying.',
    );
  }
}
