---
name: flutter-vscode-troubleshoot
description: >-
  Diagnose flutter_vscode build, packaging, Host Dart, generated-binding, or
  Flutter View protocol failures.
---

# Troubleshoot a flutter_vscode Extension

Start every diagnosis with:

```sh
flutter_vscode doctor
```

It checks the Dart and Flutter SDKs, the Extension Project layout, the
project descriptor, and whether the pinned `apiTarget` ships with the
installed `flutter_vscode`, printing `[ok]`/`[!!]` per check and exiting
nonzero while issues remain.

## Build/configuration

- `BUILD_NOT_EXTENSION_PROJECT`: run from the project root containing
  `extension.dart` and `host/lib/extension.dart`.
- `INVALID_PROJECT_API_TARGET` / `UNAVAILABLE_PROJECT_API_TARGET`: keep the
  explicit `apiTarget` an exact stable VS Code version that this
  `flutter_vscode` pins; do not silently substitute another version.
- `HOST_IMPORT_BOUNDARY_VIOLATION`: fix the author-owned file named by the
  diagnostic; Flutter and browser imports belong only in `views/`.
- `INVALID_HOST_DART`: fix the Dart syntax error at the reported
  file:line:column, then rerun `flutter_vscode build`.
- Keep the restricted constant descriptor shape emitted by `create` in
  `extension.dart`.

## Missing API

The generated layer, `package:dart_vscode/dart_vscode.dart`, maps
every public declaration of the pinned VS Code API. A symbol that appears
missing is either absent from the pinned `apiTarget` version or a framework
defect. Do not add raw interop or edit generated files; report the pinned
declaration ID so the framework pipeline can fix the mapping.

## Stale artifacts or VSIX

```sh
flutter_vscode build
flutter_vscode package
```

`MISSING_BUILD_ARTIFACTS` and `STALE_BUILD_ARTIFACTS` share one remedy: run
`flutter_vscode build` before packaging. If packaging still fails
(`UNSAFE_PACKAGE_OUTPUT`, `INVALID_VSIX`), use its exact diagnostic. Never
patch `package.json`, `out/**`, or the archive manually.

## Flutter View

- `INVALID_FLUTTER_VIEW` / `INVALID_VIEW_OUTPUT`: each view must be a real
  `lowercase_with_underscores` directory under `views/`, and built assets
  must exist beneath `out/views/<name>/`.
- Check CSP, webview-safe URIs, and private `acquireVsCodeApi` initialization.
- Match protocol/version/session/nonce and use only allowlisted operations.
- On close or reload, confirm pending request and subscription counts return
  to zero and late messages are ignored.

Host commands and providers should remain functional without the view and
after it closes; if not, move their lifecycle out of the view session. The
`flutter-vscode-view` skill covers the authoring side of the view runtime.
