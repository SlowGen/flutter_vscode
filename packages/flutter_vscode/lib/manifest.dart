/// The typed Extension Manifest an Extension Project declares in its root
/// `extension.dart`.
///
/// An Extension Project's descriptor is one constant:
///
/// ```dart
/// import 'package:flutter_vscode/manifest.dart';
///
/// const extension = ExtensionManifest(
///   name: 'my-extension',
///   displayName: 'My Extension',
///   description: 'A VS Code extension written in Dart.',
///   version: '0.0.1',
///   publisher: 'local',
///   activationEvents: ['onLanguage:json'],
///   commands: [
///     ExtensionCommand(
///       command: 'my-extension.hello',
///       title: 'Say Hello from Dart',
///     ),
///   ],
/// );
/// ```
///
/// The declaration is ordinary, analyzable Dart — the editor completes and
/// type-checks it — but `flutter_vscode build` reads it as data: the CLI
/// parses the constant invocation and never loads or executes project code.
/// Every value must therefore be a constant literal.
library;

/// The Dart-owned metadata of one VS Code extension.
///
/// `flutter_vscode build` projects this manifest into the generated
/// `package.json` and builds against the one VS Code baseline this
/// `flutter_vscode` release pins. Only constant literal values are
/// supported; the CLI parses the declaration as data and never executes it.
final class ExtensionManifest {
  /// Creates the manifest an Extension Project declares as
  /// `const extension = ExtensionManifest(...)`.
  const ExtensionManifest({
    required this.name,
    required this.displayName,
    required this.description,
    required this.version,
    required this.publisher,
    required this.activationEvents,
    this.commands = const [],
    this.viewsContainers = const {},
    this.views = const {},
    this.configuration,
    this.schemaVersion = 1,
  });

  /// The extension identifier component, in lower-kebab-case, for example
  /// `'my-extension'`.
  ///
  /// Combined with [publisher] it forms the installed extension identifier
  /// `publisher.name`.
  final String name;

  /// The human-readable extension name VS Code shows in the UI, for example
  /// in the Extensions view.
  final String displayName;

  /// The short description VS Code shows beneath the display name.
  final String description;

  /// The extension's own semantic version, for example `'0.0.1'`.
  final String version;

  /// The publisher identifier component, in lower-kebab-case.
  ///
  /// Combined with [name] it forms the installed extension identifier
  /// `publisher.name`. Use `'local'` for extensions that are not published
  /// to a marketplace.
  final String publisher;

  /// The VS Code activation events that load the extension, for example
  /// `['onLanguage:json']` or `['onStartupFinished']`.
  ///
  /// Declare an empty list for an extension activated only by its own
  /// [commands].
  final List<String> activationEvents;

  /// The commands this extension contributes to the Command Palette.
  ///
  /// Defaults to none. Each contributed command's handler is registered by
  /// the Host Dart entrypoint under the same command identifier.
  final List<ExtensionCommand> commands;

  /// View containers this extension contributes, keyed by location.
  ///
  /// The pinned VS Code accepts `activitybar`, `panel`, and
  /// `secondarySidebar`. A container is where [views] render; contribute
  /// one and key views by its id.
  final Map<String, List<ExtensionViewContainer>> viewsContainers;

  /// Views this extension contributes, keyed by container.
  ///
  /// Keys are the built-in containers (`explorer`, `debug`, `scm`, `test`)
  /// or the id of a container from [viewsContainers]. A tree view rendered
  /// with `registerTreeDataProvider` must be contributed here first;
  /// without the contribution it renders nowhere.
  final Map<String, List<ExtensionView>> views;

  /// The settings this extension registers, shown in the Settings editor.
  ///
  /// The configuration API rejects reads of unregistered keys, so a
  /// setting must be declared here before `workspace.getConfiguration`
  /// can see it.
  final ExtensionConfiguration? configuration;

  /// The descriptor schema revision, currently always `1`.
  final int schemaVersion;
}

/// One command contribution: an identifier plus its Command Palette title.
final class ExtensionCommand {
  /// Creates a contributed command named [command] titled [title].
  const ExtensionCommand({required this.command, required this.title});

  /// The command identifier, conventionally `<extension-name>.<action>`,
  /// for example `'my-extension.hello'`.
  ///
  /// The Host Dart entrypoint registers the handler under this identifier.
  final String command;

  /// The human-readable title VS Code shows in the Command Palette.
  final String title;
}

/// One contributed view container: an icon in the Activity Bar, the Panel,
/// or the Secondary Side Bar that holds this extension's views.
final class ExtensionViewContainer {
  /// Creates a container [id] rendered with [title] and [icon].
  const ExtensionViewContainer({
    required this.id,
    required this.title,
    required this.icon,
  });

  /// The container identifier: alphanumeric, `_`, and `-` only.
  ///
  /// [ExtensionManifest.views] keys views into this container by this id.
  final String id;

  /// The human-readable name rendered on the container.
  final String title;

  /// Path to the container icon, or a theme icon like `r'$(list-tree)'`.
  final String icon;
}

/// One contributed view inside a container.
final class ExtensionView {
  /// Creates a view [id] rendered as [name] with [icon].
  const ExtensionView({
    required this.id,
    required this.name,
    required this.icon,
    this.type,
    this.when,
    this.visibility,
    this.contextualTitle,
    this.initialSize,
  });

  /// The view identifier a `TreeDataProvider` or webview view registers
  /// against, for example `'myExtension.dependencies'`.
  final String id;

  /// The human-readable view name.
  final String name;

  /// Path to the view icon, or a theme icon like `r'$(list-tree)'`.
  ///
  /// Required by the pinned manifest schema.
  final String icon;

  /// `'tree'` (the default) or `'webview'`.
  final String? type;

  /// A when-clause context expression controlling the view's visibility.
  final String? when;

  /// Initial state: `'visible'`, `'hidden'`, or `'collapsed'`.
  final String? visibility;

  /// Human-readable context for when the view moves out of its container.
  final String? contextualTitle;

  /// Initial size, behaving like the CSS `flex` property.
  final num? initialSize;
}

/// The settings category this extension registers.
final class ExtensionConfiguration {
  /// Creates a settings category holding [properties].
  const ExtensionConfiguration({
    required this.properties,
    this.title,
    this.order,
  });

  /// Setting descriptors keyed by full setting name, for example
  /// `'myExtension.registryUrl'`.
  ///
  /// Each value is a JSON-schema fragment: at minimum a `'type'`, and
  /// usually a `'default'` and a `'description'`.
  final Map<String, Map<String, Object?>> properties;

  /// The Settings editor subheading; defaults to the display name.
  final String? title;

  /// This category's order relative to other categories.
  final int? order;
}
