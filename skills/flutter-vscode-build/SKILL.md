---
name: flutter-vscode-build
description: >-
  Build or package a Dart-owned flutter_vscode Extension Project. Use before
  F5, after metadata/Host Dart/view changes, or when managed artifacts are
  stale.
---

# Build a flutter_vscode Extension

Preflight first, from the Extension Project root:

```sh
flutter_vscode doctor
```

`doctor` prints `[ok]`/`[!!]` lines for the Dart and Flutter SDKs, the
project layout, and the pinned `apiTarget`, and exits nonzero when anything
needs fixing — cheaper than discovering the same problem mid-build.

Then build:

```sh
flutter_vscode build
```

The command validates `extension.dart` and the explicit `apiTarget`, enforces
host/shared dependency boundaries, regenerates native host bindings and the VS
Code manifest, compiles Host Dart, builds configured Flutter views, and writes
the launch configuration.

During iterative work, keep a watcher running instead of re-invoking `build`:

```sh
flutter_vscode build --watch
```

It builds once, then rebuilds after every change to `extension.dart`,
`extension.json`, `host/lib`, `shared/lib`, or a `views/<name>/lib`. Build
failures print their error code without stopping the watcher; interrupt with
Ctrl+C.

Do not run npm or edit generated JavaScript, TypeScript, `package.json`,
`host/lib/generated/**`, `host/bootstrap.cjs`, or `out/**`.

To produce an installable artifact:

```sh
flutter_vscode package
```

Packaging must reject missing, stale, or unexpected managed artifacts and
validate the exact VSIX layout. If it fails, repair author-owned Dart and rerun
`build`; do not patch the archive. The `flutter-vscode-troubleshoot` skill maps
the error codes.

For reproducibility investigations, run `build` twice without source changes
and byte-compare framework-managed outputs.
