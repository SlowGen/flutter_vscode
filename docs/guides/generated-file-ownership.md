# Generated File Ownership

An Extension Project has two ownership classes. Keep this boundary intact so
`build` can regenerate and repair the project deterministically.

## Author-owned source

- `extension.dart`: metadata and contributions.
- `host/lib/**`: activation, commands, providers, and host lifecycle behavior.
- `shared/lib/**`: pure Dart code shared across runtimes.
- `views/**`: optional Flutter view source and assets.

Edit these files directly and commit them.

## Framework-managed artifacts

- `package.json`.
- `host/bootstrap.cjs` and `host/lib/generated/**` -- which is only what is
  derived from this project: its extension identifier, its collision-resistant
  global key, and the bindings tied to them. Framework code is not copied
  here; it ships in `package:dart_vscode` (ADR 0015).
- `.vscode/launch.json`.
- `out/**`, including the host bundle, source map, and built view assets.
- `build/*.vsix`.

Do not hand-edit these files. Regenerate them with:

```sh
flutter_vscode build
```

Repeated builds from unchanged source must produce byte-identical managed
content. `flutter_vscode package` validates the current managed artifacts and
the exact VSIX entry set before reporting success.

