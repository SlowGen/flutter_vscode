---
name: flutter-vscode-test
description: >-
  Test Host Dart, generated VS Code behavior, or a Flutter View protocol in a
  flutter_vscode Extension Project.
---

# Test a flutter_vscode Extension

Run every author suite with one command from the Extension Project root:

```sh
flutter_vscode test
```

It discovers `shared/test` and `host/test` (run with `dart test`) and each
`views/<name>/test` (run with `flutter test`), resolves dependencies per
suite, and fails if any suite fails. A project with no test directories
reports "No test suites found" and exits cleanly — add suites under those
three roots and they are picked up without configuration.

Write tests at the narrowest real seam that owns the behavior:

- Pure Dart tests in `shared/test` for shared logic and protocol validation.
- Dart tests in `host/test` for host-side logic that needs no live VS Code.
- Flutter tests in `views/<name>/test` for view rendering and typed protocol
  calls.
- A pinned VS Code Extension Host test for activation, commands, providers,
  native object identity, events, and disposal.
- An installed-VSIX test for packaging and auto-activation.

For protocol work, test the handshake and happy call first, then wrong version,
invalid schema, session/nonce mismatch, disallowed operation, duplicate request,
structured operation failure, close/reload, late replies, and zero pending or
subscription counts.

Use red-green-refactor: observe the new test fail for the intended reason, add
the smallest implementation, then run the focused test before broader gates.

Always finish with:

```sh
flutter_vscode build
flutter_vscode test
flutter_vscode package
```

Framework contributors additionally run `flutter analyze` and
`./scripts/ci_gates.sh`.
