/// The validated manifest projection of one Extension Project descriptor.
library;

import 'package:dart_vscode/src/contributions/exception.dart';
import 'package:dart_vscode/src/contributions/json_values.dart';
import 'package:dart_vscode/src/contributions/projections.dart';
import 'package:dart_vscode/src/contributions/vscode_api_version.dart';

/// An Extension Project descriptor admitted against the pinned VS Code
/// baseline's exact manifest and contribution semantics.
///
/// Construction validates every field the way the pinned platform would at
/// extension load, so a descriptor that constructs successfully produces a
/// `package.json` the pinned VS Code accepts.
final class ManifestProjection {
  ManifestProjection._({
    required this.name,
    required this.displayName,
    required this.description,
    required this.version,
    required this.publisher,
    required this.activationEvents,
    required this.commands,
    required this.viewsContainers,
    required this.views,
    required this.configuration,
  });

  /// Validates [project] and projects it into manifest form.
  ///
  /// Throws a [ContributionException] with a stable diagnostic code when the
  /// descriptor would be rejected by the pinned platform.
  factory ManifestProjection.fromProjectDescriptor(
    Map<String, Object?> project,
  ) {
    validateProjectDescriptor(project);
    // Presence is admission: an absent identity field is an author
    // mistake and carries the author-facing code, not the maintainer
    // coercion diagnostic a null would produce downstream.
    for (final field in [
      'name',
      'displayName',
      'description',
      'version',
      'publisher',
      'activationEvents',
    ]) {
      if (project[field] == null) {
        throw ContributionException(
          'INVALID_PROJECT_MANIFEST',
          'project.$field is required.',
        );
      }
    }
    final name = extensionIdentifierComponent(
      project['name'],
      'project.name',
    );
    final displayName = nonEmptyString(
      project['displayName'],
      'project.displayName',
    );
    final description = nonEmptyString(
      project['description'],
      'project.description',
    );
    final version = string(project['version'], 'project.version');
    if (!isStrictSemanticVersion(version)) {
      throw const ContributionException(
        'INVALID_PROJECT_MANIFEST',
        'project.version must be a valid semantic version.',
      );
    }
    final publisher = extensionIdentifierComponent(
      project['publisher'],
      'project.publisher',
    );
    final activationEvents = <String>[
      for (final event in objectList(
        project['activationEvents'],
        'project.activationEvents',
      ))
        string(event, 'project.activationEvents entry'),
    ];
    final commands = projectCommands(project['commands']);
    final viewsContainers = projectViewsContainers(project['viewsContainers']);
    final contributedContainers = <String>{
      for (final entry in viewsContainers.values)
        for (final container in entry! as List<Map<String, Object?>>)
          container['id']! as String,
    };
    final views = projectViews(
      project['views'],
      contributedContainers: contributedContainers,
    );
    final configuration = projectConfiguration(project['configuration']);
    return ManifestProjection._(
      name: name,
      displayName: displayName,
      description: description,
      version: version,
      publisher: publisher,
      activationEvents: List.unmodifiable(activationEvents),
      commands: List.unmodifiable(commands),
      viewsContainers: Map.unmodifiable(viewsContainers),
      views: Map.unmodifiable(views),
      configuration: Map.unmodifiable(configuration),
    );
  }

  /// The lower-kebab extension name.
  final String name;

  /// The human-readable extension name.
  final String displayName;

  /// The marketplace description.
  final String description;

  /// The strict semantic version of the extension.
  final String version;

  /// The lower-kebab publisher identifier.
  final String publisher;

  /// The activation events the extension declares.
  final List<String> activationEvents;

  /// The projected command contributions.
  final List<Map<String, Object?>> commands;

  /// The projected views container contributions, keyed by location.
  final Map<String, Object?> viewsContainers;

  /// The projected view contributions, keyed by container.
  final Map<String, Object?> views;

  /// The projected configuration contribution.
  final Map<String, Object?> configuration;

  /// The `publisher.name` extension identifier.
  String get extensionId => '$publisher.$name';

  /// Builds the `package.json` object for this manifest.
  ///
  /// [main] is the extension entry module path the packaging layout
  /// provides; `engines.vscode` is always [vscodeApiVersion], the one
  /// baseline this `dart_vscode` release ships.
  Map<String, Object?> toManifestJson({required String main}) =>
      <String, Object?>{
        'name': name,
        'displayName': displayName,
        'description': description,
        'version': version,
        'publisher': publisher,
        'engines': <String, Object?>{'vscode': vscodeApiVersion},
        'main': main,
        'activationEvents': activationEvents,
        if (commands.isNotEmpty ||
            viewsContainers.isNotEmpty ||
            views.isNotEmpty ||
            configuration.isNotEmpty)
          'contributes': <String, Object?>{
            if (commands.isNotEmpty) 'commands': commands,
            if (viewsContainers.isNotEmpty) 'viewsContainers': viewsContainers,
            if (views.isNotEmpty) 'views': views,
            if (configuration.isNotEmpty) 'configuration': configuration,
          },
      };
}
