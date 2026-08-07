# ADR 0015: Ship the runtime as a pure-Dart package

Status: Accepted

## Context

An Extension Project received about 2,850 lines of code its author never
wrote. The Host/Flutter View protocol was copied verbatim into the
project's shared package. The command-registration module and the Flutter
View host module were emitted from `const` raw strings held in the CLI —
Dart source stored as text, which is why neither could be analyzed or
tested where it lived, and why the tests covering them asserted properties
of their *source text* rather than their behaviour.

Separately, the generated VS Code API layer lived in `flutter_vscode`,
which depends on the Flutter SDK. Once projects imported the layer from
there instead of receiving a copy (ADR 0014), every Host Dart module — pure
Dart, compiled with `dart compile js` — pulled Flutter into its dependency
graph to reach an artifact that imports nothing but `dart:js_interop`.

## Decision

The pure-Dart runtime ships as its own published package, `dart_vscode`:
the generated API layer, the view protocol, `ExtensionCommands`, the
Flutter View host module, and the Host Dart runtime seam. It declares no
Flutter dependency. `flutter_vscode` keeps the CLI and the Flutter View
runtime and depends on it.

Framework code is not copied into projects. A project receives only what is
derived from that project: `host_exports.g.dart` and `vscode_runtime.g.dart`,
which carry its extension identifier and its collision-resistant global key.

Two JavaScript globals are genuinely per-extension — the source-map stack
mapper and the callback wrapper. The generated runtime binds those and
installs them through `installHostRuntime`; the code that uses them lives in
`dart_vscode` once.

## Consequences

Host packages depend on `dart_vscode` and keep a Flutter-free graph. The
2,850 lines come under the analyzer and the formatter for the first time,
and the tests that asserted source text are gone: the analyzer proves the
modules compile and the real-host gates prove they behave.

`flutter_vscode` and `dart_vscode` release together, and `flutter_vscode`
cannot be installed until `dart_vscode` is published. Until then, the
scaffold and two gates carry a `dependency_overrides` pointing at the local
copy; each says so where it does it, and they come out in one commit on the
day both packages ship.

This supersedes the emission half of ADR 0013 and amends ADR 0005: an
Extension Project no longer holds an inspectable copy of the framework's
code. The boundary stays visible in the project's `pubspec.yaml`, which
names `dart_vscode` explicitly.
