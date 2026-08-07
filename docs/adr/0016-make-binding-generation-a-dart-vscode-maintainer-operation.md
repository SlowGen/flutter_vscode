# ADR 0016: Make binding generation a dart_vscode maintainer operation

Status: Accepted

## Context

The binding pipeline — the pinned upstream inputs, the Node importer,
the committed IR, the Semantic Overrides, and the Dart generator — lived
in `packages/flutter_vscode/tool`, and `flutter_vscode build` read the
2.9 MB IR on every project build. That placement told a false story
about who generates what. An extension author never generates bindings:
the API layer is fixed at the moment a `dart_vscode` release is
published, and the only party who reruns the pipeline is the maintainer
moving the pinned VS Code baseline. Yet the IR and generator shipped in
the `flutter_vscode` archive, the build receipt digested them as if a
project build depended on them, and every project received a
`coverage.json` that contained no project data at all — the same ledger,
byte for byte, in every project.

Meanwhile the author-facing half of the pipeline — validating an
Extension Project's contributions with the pinned platform's exact
admission semantics and projecting them into `package.json` form — was
locked inside the generator, reachable only by handing it the full IR.

## Decision

The pipeline moves to `packages/dart_vscode/tool` and becomes
maintainer-internal: never published (the archive excludes `tool/`),
never read by `flutter_vscode build`, rerun only when the baseline
moves.

What each party owns:

- `package:dart_vscode` (published) owns everything pinned to the
  VS Code baseline: the generated API layer, the runtime libraries, and
  a `contributions` library holding the independently reviewed
  author-data admission mirrors (`ManifestProjection`), the ECMAScript
  whitespace lowering, and `vscodeApiVersion` — the one place the
  baseline is named.
- `packages/dart_vscode/tool` (repository-only) owns the importer, IR,
  overrides, generator, ledgers, and Host Contract writer. The
  generator's product is the maintainer coverage ledger
  (`tool/bindings/coverage-ledger.json`); it no longer emits project
  files.
- `flutter_vscode build` emits only Project-Derived Artifacts — the
  manifest, the bootstrap, and the two identity-wiring modules — from
  templates plus the contributions library. Its build receipt digests
  the framework alone.

The IR stays committed, as maintainer-internal state: parsing
`vscode.d.ts` faithfully requires the TypeScript compiler, so a
Node-to-Dart handoff artifact must exist, and persisting it keeps the
Dart-side pipeline tests Node-free, anchors the Semantic Override
fingerprints, and gives the ADR 0008 delta review a diffable object in
git history. It simply is not a package asset.

## Consequences

- The published `flutter_vscode` archive carries no generator, IR, or
  pinned inputs, and `dart_vscode` publishes without its `tool/` area;
  the packaged-extension gate asserts both.
- Descriptor admission is available as an ordinary library:
  `ManifestProjection.fromProjectDescriptor` validates and projects
  without any binding inputs, and its deep test suite needs only
  descriptors.
- `coverage.json` disappears from projects; behavioral-verification
  accounting lives in the maintainer ledger and the published parity
  report.
- The double-entry review is unchanged in substance but split across
  homes: the IR-side schema byte-compares stay in the maintainer tool,
  the author-side mirrors live in the published library, and the
  pipeline tests cross-check the two.
- Moving the baseline now touches one package's version and constant
  (`vscodeApiVersion`), regenerates one layer, and republishes both
  packages; nothing in an extension project changes except its resolved
  dependency.
