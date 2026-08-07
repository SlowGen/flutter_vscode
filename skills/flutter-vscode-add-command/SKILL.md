---
name: flutter-vscode-add-command
description: >-
  Add a Dart-owned command to a flutter_vscode Extension Project, optionally
  exposing a typed result to a Flutter view.
---

# Add a Dart Command

1. Add the command contribution to `extension.dart` using
   `flutter-vscode-contributions`.
2. Register the identical ID during Host Dart activation with the generated
   commands API.
3. Keep native VS Code objects and provider callbacks in Host Dart.
4. Run `flutter_vscode build` and invoke the command in an Extension Host test.

If a Flutter view needs the result, add one narrowly named operation to that
view session’s allowlist and return a protocol-safe value snapshot. Call it
through the typed v1 view API. Do not expose `commands.executeCommand`, a dotted
path evaluator, or arbitrary get/set/call access across the view boundary.

If the command needs an API absent from generated bindings, stop and report its
IR/coverage state. Expanding the pinned API requires official input, a reviewed
Semantic Override, deterministic generation, and a real host test.
