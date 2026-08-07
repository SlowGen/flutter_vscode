# dart_vscode

The complete typed Dart mapping of the VS Code extension API, with a Dart-first ergonomic surface — and the runtime pieces a VS Code extension written in Dart needs at its host boundary.

This package is pure Dart. It depends on `dart:js_interop` and nothing else, so a Host Dart module compiled with `dart compile js` never pulls the Flutter SDK into its dependency graph.

```dart
import 'package:dart_vscode/dart_vscode.dart';

final api = VscodeApi(rawVscode).dart;
await api.window.showInformationMessage('Hello from Dart.');
```

## What's here

| library | what it gives you |
|---|---|
| `dart_vscode.dart` | every public declaration of the pinned VS Code API, typed |
| `host_commands.dart` | `ExtensionCommands.register` and `context.own` — ordinary Dart command handlers, and registration ownership through the activation context |
| `host_runtime.dart` | promise and callback bridging, host `fetch`, Dart stack frames |
| `view_protocol.dart` | the versioned protocol shared by Host Dart and a Flutter View |
| `flutter_view_host.dart` | hosting a Flutter View from Host Dart |
| `contributions.dart` | `ManifestProjection` — the pinned platform's manifest admission semantics — and `vscodeApiVersion`, the one place the baseline is named |

The API layer is generated mechanically from one pinned VS Code release by this package's own maintainer pipeline — an Extension Author never runs it. The package version *is* the baseline: to target a different VS Code API, depend on the release that ships it.

Most authors do not depend on this package directly: `flutter_vscode create` scaffolds a project that already does. See the [flutter_vscode](https://github.com/SlowGen/flutter_vscode) repository for the CLI, the guides, and two complete example extensions.
