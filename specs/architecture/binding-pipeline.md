# Binding Pipeline

Public VS Code bindings are generated mechanically from pinned official
inputs plus reviewed Semantic Overrides. No LLM, probabilistic mapping,
silent omission, or guessed `dynamic` types participate; anything the
pipeline cannot express fails closed.

One pinned stable baseline ships per release (ADR 0014): the package
version is the baseline, and a project never selects one. The baseline
counts only when its pinned inputs, imported IR, and same-version
Semantic Override file all exist. Moving to a newer VS Code release is
a regenerate-and-republish operation, documented in
`docs/guides/new-baseline.md`.

## Stages

1. **Pins** — `packages/dart_vscode/tool/bindings/inputs/vscode/<version>/pins.json` pins six
   official inputs (`vscode.d.ts`, manifest schema/validator sources, the
   `commands` contribution schema source, transitive helper, license)
   with exact product version, commit, canonical source URL, checksum,
   and license. The manifest has one exact producer schema; input paths
   must resolve (realpath) inside the pin directory
   (`packages/dart_vscode/tool/binding_importer/src/pins.cjs`, `test/pins.test.cjs`).
2. **Importer** — `packages/dart_vscode/tool/binding_importer` (maintainer-only, pinned
   TypeScript parser) normalizes the pinned sources into canonical IR at
   `packages/dart_vscode/tool/bindings/ir/vscode-<version>.json`. The IR is lossless for every
   supported declaration shape — generic scopes alpha-normalized,
   visibility propagated, member order preserved via stored canonical
   type-literal shapes — and inexpressible syntax is rejected, never
   erased (`packages/dart_vscode/tool/binding_importer/test/inventory.test.cjs`).
3. **Overrides** — `packages/dart_vscode/tool/bindings/overrides/vscode-<version>.json` holds
   reviewed classifications (`entries` with strategies and declaration
   fingerprints, `targets`, Host Contract pins). Baseline updates fail
   closed: new, shape-changed, or removed public symbols require reviewed
   classification (`src/baseline*.cjs`, seed-validated by
   `npm run check:baseline-series`); ADR 0008 blocks releases on
   unclassified public symbols.
4. **Generator** — the orchestration in
   `packages/dart_vscode/tool/binding_generator/generator.dart` consumes IR + overrides and
   accepts only IR the producer could emit; the walking-slice strategy
   and relation validation still runs on every generate, so the
   reviewed override classifications keep their ADR-0008 gate without
   any generated-code backing of their own. The acceptance band itself
   lives in sibling modules: `ir_validator.dart` recomputes identities
   and hashes (including every registered type-literal shape hash,
   cross-validated member-by-member against child declarations),
   preserves graph relationships, correlates raw and canonical fields,
   and rejects impossible combinations, while
   `manifest_projection.dart` holds the manifest/contribution schema
   pins, `coverage_ledger.dart` the ledger emission, and
   `validators.dart` the maintainer leaf scalars. The author-data
   admission mirrors those schemas pin live in
   `package:dart_vscode/contributions.dart`, where the flutter_vscode
   CLI consumes them at build time. The validated slice is derived
   entirely from IR + override strategies — no shadow name/count
   profile in generator source
   (`packages/dart_vscode/test/binding_generator_test.dart`,
   `packages/dart_vscode/test/binding_generator_layout_test.dart`).
5. **Outputs** — the maintainer coverage ledger
   (`packages/dart_vscode/tool/bindings/coverage-ledger.json`),
   byte-identical on regeneration
   (`packages/dart_vscode/test/binding_generator_cli_test.dart`).
   Project artifacts (runtime module, host exports, bootstrap,
   manifest) are not generated here: `flutter_vscode build` emits them
   from the project descriptor alone, via
   `packages/flutter_vscode/lib/src/cli/project_artifacts.dart` and the
   contributions library — an extension author never runs this
   pipeline.
6. **Generated API Layer** — `packages/dart_vscode/tool/binding_generator/dart_layer.dart`
   (`generate.dart --dart-layer .`) emits the one self-contained API
   artifact, `packages/dart_vscode/lib/src/generated/vscode_dart_layer.g.dart`, exported
   as `package:dart_vscode/dart_vscode.dart`: the complete typed
   Parity Layer substrate (ADR 0012, emitted in-memory by
   `parity_layer.dart` and inlined into the artifact) with the
   mechanical, judgment-free Dart-first surface over it — scalar
   boundaries de-JS'd, `Future`s from `JSPromise` returns, broadcast
   `Stream` accessors beside `Event` members, `lit$` factories
   flattened across the declared interface hierarchy. Both emitters
   consume the shared `ir_type_mapper.dart` (IR indexes, type mapping
   with union/alias/LUB rules, substitution, name mangling, erasure as
   a per-call parameter). One `--dart-layer` run writes two totality
   ledgers — `packages/dart_vscode/tool/bindings/parity-ledger.json` covering every IR
   declaration in the substrate, and
   `packages/dart_vscode/tool/bindings/dart-layer-ledger.json`, in which every substrate
   declaration receives a disposition (emitted,
   passthrough-identical, or carried parity erasure) — and a
   construct without a total rule fails generation
   (`packages/dart_vscode/test/parity_layer_test.dart`,
   `test/dart_layer_test.dart`, `test/dart_layer_emitter_unit_test.dart`,
   both beside it). The artifact ships once, in
   `package:dart_vscode`, and every Extension Project imports it rather
   than receiving a copy (ADR 0015); the real-host gate executes it (the
   fixture parity smoke).

## Regeneration commands

Run from the repository root, in this order when in doubt. A release ships
one pinned baseline (ADR 0014), so there is no target to substitute:

```sh
# IR from pinned inputs (maintainer, after pin/importer changes):
(cd packages/dart_vscode/tool/binding_importer && node src/cli.cjs \
  --pins ../bindings/inputs/vscode/1.129.1/pins.json \
  --output ../bindings/ir/vscode-1.129.1.json)

# The Generated API Layer and both totality ledgers, into the
# dart_vscode package (after emitter or IR changes):
dart packages/dart_vscode/tool/binding_generator/generate.dart \
  --dart-layer .

# Runtime, host exports, bootstrap, and manifest into the fixture --
# only what is derived from that project:
bash scripts/build_host_fixture.sh

# Durable Host Contract artifact and the overrides pin (after any
# receipted source changes):
dart packages/dart_vscode/tool/binding_generator/generate.dart \
  --contract .

# Generated parity report (after coverage changes):
dart packages/dart_vscode/tool/binding_generator/generate.dart \
  --parity .
```

Order matters when a receipted source changes: format, regenerate the
contract, then `--dart-layer` (the coverage ledger carries the contract
digest, so repinning the overrides moves it), rebuild the fixture, and
regenerate the contract again to settle the receipted fixture bytes.

If gates complain about stale generated artifacts, the failing test names
which command to run; the checked-in files and their pins are always the
current authority, never prose.

## Coverage honesty

`packages/dart_vscode/tool/bindings/coverage-ledger.json` and
`docs/reference/parity.md` distinguish emitted,
reviewed-excluded, non-public, and pending symbols. Live coverage is
measured on two machine-derived axes, generated into the parity
report: the API Family axis is derived from the pinned IR (at least
one representative of every namespace family executes against live
VS Code), and the Construct Class axis from the emitter's canonical
constant (every Total Mapping Rule construct class carries a
`cc:`-tagged live probe unless it has a recorded live exemption with
its reason). Runtime evidence is one aggregate real-host contract with
mechanically attributed binding IDs — not independent behavioral
contracts — and the docs say so. A missing Dart path for a public
capability is a defect (vision rule, stated in the parity report).
