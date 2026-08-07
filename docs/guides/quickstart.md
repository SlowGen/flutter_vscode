# Quickstart

The end-to-end path for an Extension Author's first Dart-owned VS Code
extension: install the `flutter_vscode` CLI, scaffold an Extension
Project, then build, test, and package it — with no author-maintained
TypeScript anywhere. Each numbered step names the command that owns
it; the [README](../../README.md) walks the same path with full code,
and the [Generated Host API](../reference/generated-host-api.md)
covers the API surface in depth.

## 1. Install the CLI

The Dart-host workflow is currently unreleased. Activate the CLI from its
repository checkout:

```sh
dart pub global activate --source path /path/to/flutter_vscode
```

Once this release is available on pub.dev, use
`dart pub global activate flutter_vscode` instead.

Verify the toolchain any time with:

```sh
flutter_vscode doctor
```

Inside an Extension Project it also validates the layout, the project
descriptor, and the pinned API target, with actionable errors.

## 2. Create an Extension Project

```sh
flutter_vscode create my_extension
cd my_extension
```

The project separates pure host Dart, optional Flutter views, and a pure shared
Dart package. It contains no author-maintained JavaScript, TypeScript, or
`package.json`.

`extension.dart` is the source of truth for metadata and contributions. The
VS Code API it builds against is the one baseline this `flutter_vscode`
release pins (1.129.1), which also fixes the generated `engines.vscode`
value. There is no per-project selector: to move to a different VS Code
API, depend on the `flutter_vscode` release that ships it — an explicit
compatibility decision recorded in your `pubspec.yaml`.

## 3. Implement host behavior

Edit `host/lib/extension.dart`. Host code runs when the extension activates,
even if no Flutter view exists. Keep Flutter, browser-only libraries, `dart:io`,
and other unsupported platform APIs out of `host/` and `shared/`; `build` checks
these boundaries. The generated API layer is present immediately after
`create`, so `dart pub get && dart analyze` succeeds in `host/` before the
first build.
Use the [Generated Host API](../reference/generated-host-api.md) for supported
Dart patterns and the parity report for exact verification coverage.

## 4. Build and debug

```sh
flutter_vscode build
```

This deterministically regenerates the manifest, bindings, bootstrap, host
JavaScript, source map, and `.vscode/launch.json`. Open the project in VS Code
and press F5 to launch the generated debug configuration. While iterating,
`flutter_vscode build --watch` reruns the same build whenever author-owned
sources change; press Ctrl+C to stop.

## 5. Test

```sh
flutter_vscode test
```

Runs every author suite the project has — `shared/test` and
`host/test` with `dart test`, and each `views/<name>/test` with
`flutter test` — and fails if any suite fails.

## 6. Package

```sh
flutter_vscode package
```

The command validates framework-managed artifacts and writes the VSIX beneath
`build/`. Install that file with VS Code's **Extensions: Install from VSIX…**
command.

The behavioral proof runs against the pinned VS Code baseline shipped
in-tree. Do not infer or handwrite bindings:
the generated API layer already maps every public declaration of the
pinned API.

## Reaching the full VS Code API

The build emits one generated API layer into
`package:dart_vscode/dart_vscode.dart` — the complete typed
mapping of the pinned VS Code API with a Dart-first ergonomic surface in
the same artifact. See the
[Generated Host API reference](../reference/generated-host-api.md) for
how to wrap the activation module with `VscodeApi`, construct values
with `new$` and `lit$`, and enter the ergonomic surface with `.dart`.
