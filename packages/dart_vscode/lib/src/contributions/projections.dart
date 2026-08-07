/// Author-data contribution projection for the pinned VS Code baseline:
/// validates an Extension Project's contributions with the platform's
/// exact admission semantics and projects them into manifest form.
///
/// Each projection is the independently reviewed Dart mirror of the pinned
/// upstream contribution schema and validator branches; the maintainer-side
/// binding pipeline cross-checks these mirrors against the imported schema
/// extraction whenever the baseline moves.
library;

import 'package:dart_vscode/src/contributions/exception.dart';
import 'package:dart_vscode/src/contributions/json_values.dart';

/// Validates and projects the command contributions of an Extension Project.
List<Map<String, Object?>> projectCommands(Object? value) {
  if (value == null) {
    return const [];
  }
  final result = <Map<String, Object?>>[];
  final identifiers = <String>{};
  const supportedKeys = {
    'category',
    'command',
    'enablement',
    'icon',
    'shortTitle',
    'title',
  };
  for (final rawCommand in objectList(value, 'project.commands')) {
    final command = objectMap(rawCommand, 'project.commands entry');
    final unknown =
        command.keys.where((key) => !supportedKeys.contains(key)).toList()
          ..sort();
    if (unknown.isNotEmpty) {
      throw ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'Unknown command contribution fields: ${unknown.join(', ')}.',
      );
    }
    final identifier = nonWhitespaceString(
      command['command'],
      'project.commands entry.command',
    );
    if (!identifiers.add(identifier)) {
      throw ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'Duplicate command contribution $identifier.',
      );
    }
    final title = nonWhitespaceString(
      command['title'],
      'project.commands entry.title',
    );
    result.add(<String, Object?>{
      'command': identifier,
      'title': title,
      for (final key in ['shortTitle', 'category', 'enablement'])
        if (command[key] != null)
          key: string(command[key], 'project.commands entry.$key'),
      if (command['icon'] != null) 'icon': _projectCommandIcon(command['icon']),
    });
  }
  return result;
}

/// Projects author viewsContainers data against the pinned schema.
Map<String, Object?> projectViewsContainers(Object? value) {
  if (value == null) {
    return const {};
  }
  const locations = {'activitybar', 'panel', 'secondarySidebar'};
  final idPattern = RegExp(r'^[a-zA-Z0-9_-]+$');
  final result = <String, Object?>{};
  final byLocation = objectMap(value, 'project.viewsContainers');
  final identifiers = <String>{};
  for (final location in byLocation.keys.toList()..sort()) {
    if (!locations.contains(location)) {
      throw ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'Unknown views container location $location; the pinned VS Code '
            'accepts ${locations.join(', ')}.',
      );
    }
    final containers = <Map<String, Object?>>[];
    for (final rawContainer in objectList(
      byLocation[location],
      'project.viewsContainers.$location',
    )) {
      final container = objectMap(
        rawContainer,
        'project.viewsContainers.$location entry',
      );
      final unknown =
          container.keys
              .where((key) => !{'id', 'title', 'icon'}.contains(key))
              .toList()
            ..sort();
      if (unknown.isNotEmpty) {
        throw ContributionException(
          'INVALID_PROJECT_MANIFEST',
          'Unknown views container fields: ${unknown.join(', ')}.',
        );
      }
      final identifier = nonWhitespaceString(
        container['id'],
        'project.viewsContainers.$location entry.id',
      );
      if (!idPattern.hasMatch(identifier)) {
        throw ContributionException(
          'INVALID_PROJECT_MANIFEST',
          'Views container id $identifier must match '
              '${idPattern.pattern}.',
        );
      }
      if (!identifiers.add(identifier)) {
        throw ContributionException(
          'INVALID_PROJECT_MANIFEST',
          'Duplicate views container $identifier.',
        );
      }
      containers.add(<String, Object?>{
        'id': identifier,
        // A whitespace-only title is a warning in the pinned host, not an
        // error; the projection matches the platform instead of exceeding
        // it.
        'title': string(
          container['title'],
          'project.viewsContainers.$location entry.title',
        ),
        'icon': string(
          container['icon'],
          'project.viewsContainers.$location entry.icon',
        ),
      });
    }
    result[location] = containers;
  }
  return result;
}

/// Projects author views data against the pinned schema.
Map<String, Object?> projectViews(
  Object? value, {
  required Set<String> contributedContainers,
}) {
  if (value == null) {
    return const {};
  }
  const knownLocations = {'debug', 'explorer', 'scm', 'test'};
  const remoteLocations = {'remote'};
  const optionalStrings = {
    'when',
    'icon',
    'contextualTitle',
    'accessibilityHelpContent',
  };
  const visibilityEnum = {'visible', 'hidden', 'collapsed'};
  const typeEnum = {'tree', 'webview'};
  final result = <String, Object?>{};
  final byLocation = objectMap(value, 'project.views');
  final identifiers = <String>{};
  for (final location in byLocation.keys.toList()..sort()) {
    if (remoteLocations.contains(location)) {
      throw ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'The $location views container needs the contribViewsRemote API '
            'proposal, which stable extensions cannot enable.',
      );
    }
    if (!knownLocations.contains(location) &&
        !contributedContainers.contains(location)) {
      throw ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'Views location $location is neither a built-in container '
            '(${knownLocations.join(', ')}) nor one contributed by this '
            'extension.',
      );
    }
    final views = <Map<String, Object?>>[];
    for (final rawView in objectList(
      byLocation[location],
      'project.views.$location',
    )) {
      final view = objectMap(rawView, 'project.views.$location entry');
      final unknown =
          view.keys
              .where(
                (key) => !{
                  'id',
                  'name',
                  'icon',
                  'type',
                  'visibility',
                  'initialSize',
                  ...optionalStrings,
                }.contains(key),
              )
              .toList()
            ..sort();
      if (unknown.isNotEmpty) {
        throw ContributionException(
          'INVALID_PROJECT_MANIFEST',
          'Unknown view fields: ${unknown.join(', ')}.',
        );
      }
      final identifier = nonWhitespaceString(
        view['id'],
        'project.views.$location entry.id',
      );
      if (!identifiers.add(identifier)) {
        throw ContributionException(
          'INVALID_PROJECT_MANIFEST',
          'Duplicate view $identifier.',
        );
      }
      final projected = <String, Object?>{
        'id': identifier,
        'name': string(view['name'], 'project.views.$location entry.name'),
        // Required by the pinned manifest schema, though the runtime
        // tolerates its absence: the build follows the schema.
        'icon': string(view['icon'], 'project.views.$location entry.icon'),
      };
      final type = view['type'];
      if (type != null) {
        final typed = string(type, 'project.views.$location entry.type');
        if (!typeEnum.contains(typed)) {
          throw ContributionException(
            'INVALID_PROJECT_MANIFEST',
            'View type $typed must be one of ${typeEnum.join(', ')}.',
          );
        }
        projected['type'] = typed;
      }
      final visibility = view['visibility'];
      if (visibility != null) {
        final typed = string(
          visibility,
          'project.views.$location entry.visibility',
        );
        if (!visibilityEnum.contains(typed)) {
          throw ContributionException(
            'INVALID_PROJECT_MANIFEST',
            'View visibility $typed must be one of '
                '${visibilityEnum.join(', ')}.',
          );
        }
        projected['visibility'] = typed;
      }
      final initialSize = view['initialSize'];
      if (initialSize != null) {
        if (initialSize is! num) {
          throw const ContributionException(
            'INVALID_PROJECT_MANIFEST',
            'View initialSize must be a number.',
          );
        }
        projected['initialSize'] = initialSize;
      }
      for (final key in optionalStrings) {
        if (view[key] != null) {
          projected[key] = string(
            view[key],
            'project.views.$location entry.$key',
          );
        }
      }
      views.add(projected);
    }
    result[location] = views;
  }
  return result;
}

/// Projects author configuration data against the pinned schema.
Map<String, Object?> projectConfiguration(Object? value) {
  if (value == null) {
    return const {};
  }
  final entry = objectMap(value, 'project.configuration');
  final unknown =
      entry.keys
          .where((key) => !{'title', 'order', 'properties'}.contains(key))
          .toList()
        ..sort();
  if (unknown.isNotEmpty) {
    throw ContributionException(
      'INVALID_PROJECT_MANIFEST',
      'Unknown configuration fields: ${unknown.join(', ')}.',
    );
  }
  final result = <String, Object?>{};
  if (entry['title'] != null) {
    result['title'] = string(entry['title'], 'project.configuration.title');
  }
  final order = entry['order'];
  if (order != null) {
    if (order is! int) {
      throw const ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'configuration.order must be an integer.',
      );
    }
    result['order'] = order;
  }
  final properties = objectMap(
    entry['properties'],
    'project.configuration.properties',
  );
  final nonWhitespace = RegExp(r'\S');
  final projected = <String, Object?>{};
  for (final name in properties.keys.toList()..sort()) {
    if (!nonWhitespace.hasMatch(name)) {
      throw const ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'Configuration property names must contain a non-whitespace '
            'character.',
      );
    }
    // The pinned schema accepts any draft-07 schema as a property value;
    // the projection passes the author value through untouched.
    projected[name] = objectMap(
      properties[name],
      'project.configuration.properties.$name',
    );
  }
  result['properties'] = projected;
  return result;
}

Object _projectCommandIcon(Object? value) {
  if (value is String) {
    return value;
  }
  final icon = objectMap(value, 'project.commands entry.icon');
  final unknown =
      icon.keys.where((key) => key != 'dark' && key != 'light').toList()
        ..sort();
  if (unknown.isNotEmpty ||
      !icon.containsKey('dark') ||
      !icon.containsKey('light')) {
    throw const ContributionException(
      'INVALID_PROJECT_MANIFEST',
      'Command icon must be a string or an object containing both dark and '
          'light string paths and no other fields.',
    );
  }
  return <String, Object?>{
    'dark': string(icon['dark'], 'project.commands entry.icon.dark'),
    'light': string(
      icon['light'],
      'project.commands entry.icon.light',
    ),
  };
}

/// Validates the key set and schema version of an Extension Project descriptor.
void validateProjectDescriptor(Map<String, Object?> project) {
  const expectedKeys = {
    'activationEvents',
    'commands',
    'configuration',
    'views',
    'viewsContainers',
    'description',
    'displayName',
    'name',
    'publisher',
    'schemaVersion',
    'version',
  };
  final unexpected =
      project.keys.where((key) => !expectedKeys.contains(key)).toList()..sort();
  if (unexpected.isNotEmpty) {
    throw ContributionException(
      'INVALID_PROJECT_DESCRIPTOR',
      'Unknown project descriptor fields: ${unexpected.join(', ')}.',
    );
  }
  // The typed descriptor's constructor declares `schemaVersion = 1`; an
  // absent key admits as revision 1 on every descriptor path.
  final schemaVersion = project['schemaVersion'] ?? 1;
  if (schemaVersion != 1) {
    throw ContributionException(
      'INVALID_PROJECT_DESCRIPTOR',
      'project.schemaVersion must be 1, found $schemaVersion.',
    );
  }
}

/// Whether a version string is a strict semantic version.
bool isStrictSemanticVersion(String value) {
  final match = RegExp(
    r'^(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)'
    r'(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?'
    r'(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$',
  ).firstMatch(value);
  if (match == null) {
    return false;
  }
  final preRelease = match.group(4);
  if (preRelease == null) {
    return true;
  }
  return preRelease
      .split('.')
      .every(
        (part) =>
            !RegExp(r'^\d+$').hasMatch(part) ||
            part == '0' ||
            !part.startsWith('0'),
      );
}
