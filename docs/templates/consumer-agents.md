# Extension Agent Guidelines

This is a `flutter_vscode` Extension Project: activation and VS Code
callbacks run in pure Host Dart, and Flutter views are optional, separate
runtimes. This file is the working agreement for any agent editing the
project — which files are author-owned, which rules are non-negotiable,
and how to validate a change. Focused workflows live in the project-local
skills under [`agent-skills/`](agent-skills/).

## Source of truth

- Edit `extension.dart` for metadata and contributions (commands, views,
  view containers, configuration).
- Edit `host/lib/**` for commands, providers, events, and VS Code object use.
- Edit `shared/lib/**` only for runtime-neutral Dart.
- Edit `views/**` for optional Flutter UI.
- Never edit `package.json`, `host/lib/generated/**`,
  `host/bootstrap.cjs`, `.vscode/launch.json`, `out/**`, or a VSIX.

## Mandatory rules

1. Run host behavior without assuming a Flutter view exists.
2. Use only the one generated API layer,
   `package:dart_vscode/dart_vscode.dart`; it maps every public
   declaration of the pinned VS Code API. Never handwrite a replacement
   binding; report a missing or wrong mapping as a framework defect.
3. The VS Code baseline comes from the `flutter_vscode` release you depend
   on; move it only by upgrading that dependency deliberately.
4. Put Flutter/browser imports only in `views/`; keep `host/` and `shared/`
   within their enforced dependency boundaries.
5. Send only validated value snapshots across the versioned view protocol.
   Keep native VS Code objects in Host Dart.
6. Expose view operations through a specific allowlist; do not add a generic
   dispatcher.
7. Register disposables with the extension context or clean up Dart-owned
   resources idempotently.
8. Preflight with `flutter_vscode doctor`; regenerate with
   `flutter_vscode build` (or a running `flutter_vscode build --watch`);
   run author suites with `flutter_vscode test`; package with
   `flutter_vscode package`.

## Decision guide

```text
VS Code activation, command, provider, event, or native object -> host/lib/
Extension contribution                                      -> extension.dart
Runtime-neutral model                                       -> shared/lib/
Rich optional UI                                            -> views/<name>/
Host value needed by a view                        -> allowlisted operation
Missing generated VS Code symbol                            -> report API gap
```

## Validation

```sh
flutter_vscode doctor
flutter_vscode build
flutter_vscode test
flutter_vscode package
```

`doctor` verifies the Dart and Flutter SDKs, the project layout, and that
the installed framework carries its pinned VS Code baseline before deeper
work. `test` runs every author suite the
project has: `shared/test` and `host/test` with `dart test`, and each
`views/<name>/test` with `flutter test`.

After a view change, also verify that host commands and providers work both
without opening it and after closing it, and that protocol pending-request and
subscription counts return to zero.

Use the project-local skills under `agent-skills/` for focused workflows —
[`flutter-vscode-view`](agent-skills/flutter-vscode-view/SKILL.md) for
Flutter View authoring and
[`flutter-vscode-troubleshoot`](agent-skills/flutter-vscode-troubleshoot/SKILL.md)
when a command fails.
