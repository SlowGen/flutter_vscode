---
name: flutter-vscode-contributions
description: >-
  Add or change VS Code contributions in a Dart-owned flutter_vscode Extension
  Project. Use for command-palette entries and other generated manifest data.
---

# Add a Contribution

Edit `extension.dart`, never generated `package.json`.

For a command, add an `ExtensionCommand` to the typed
`ExtensionManifest` constant (from `package:flutter_vscode/manifest.dart`):

```dart
  commands: [
    ExtensionCommand(
      command: 'my-extension.refresh',
      title: 'Refresh',
    ),
  ],
```

Then register the same identifier in `host/lib/extension.dart` through the
generated commands binding. Keep identifiers and titles nonblank; command IDs
must be unique. `ExtensionCommand` carries exactly the fields the toolchain
supports today — if a contribution needs a field it lacks (for example
`category` or an icon), report the gap instead of hand-editing
`package.json`.

Run `flutter_vscode build`. The generator validates contributions against the
mechanically projected schema for the project’s pinned API target. If a desired
contribution point is not generated, report the missing schema coverage instead
of inserting raw JSON or editing `package.json`.
