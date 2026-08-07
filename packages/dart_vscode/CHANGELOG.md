
## Unreleased

- Own the whole VS Code pin: the binding pipeline (pinned inputs,
  importer, IR, Semantic Overrides, generator, ledgers) moves into this
  package's maintainer `tool/` area, never published and never read at
  build time (ADR 0016). A new `contributions` library exposes the
  pinned platform's author-data admission semantics —
  `ManifestProjection` validates an Extension Project descriptor and
  projects its `package.json` form — plus `vscodeApiVersion`, the one
  place the shipped baseline is named.

## 0.1.0

- First release: the complete typed Dart mapping of the VS Code extension
  API, extracted from `flutter_vscode` so that Host Dart can reach it
  without pulling the Flutter SDK into its dependency graph. Carries the
  generated API layer, the Host/Flutter View protocol, `ExtensionCommands`,
  the Flutter View host module, and the Host Dart runtime seam.
