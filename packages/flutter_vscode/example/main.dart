// The typed project descriptor `flutter_vscode create` scaffolds as
// `extension.dart` and `flutter_vscode build` consumes: Dart-owned
// extension metadata, projected into `package.json` with the pinned
// platform's exact admission semantics. Everything else in an Extension
// Project is ordinary Dart under `host/`, `shared/`, and `views/`.

import 'package:flutter_vscode/manifest.dart';

/// Dart-owned extension metadata consumed by `flutter_vscode build`.
const extension = ExtensionManifest(
  name: 'my-extension',
  displayName: 'My Extension',
  description: 'A VS Code extension written in Dart.',
  version: '0.0.1',
  publisher: 'local',
  activationEvents: ['onLanguage:json'],
  commands: [
    ExtensionCommand(
      command: 'my-extension.hello',
      title: 'Say Hello from Dart',
    ),
  ],
);
