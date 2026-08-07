# Moving the Pinned VS Code Baseline

How a maintainer advances the one VS Code release `dart_vscode` pins.
The package version *is* the baseline (ADR 0014): a release ships
exactly one pinned API, projects do not select among several, and an
author who needs an older API depends on the `dart_vscode` release
that shipped it. The pipeline lives in `packages/dart_vscode/tool`;
extension authors never run any of this. Moving the baseline is
therefore a regenerate-and-republish operation, not an additive one.

`./scripts/test_binding_importer.sh` runs the importer suite and the
baseline validation in the pinned Node container.

> **Reviewing the delta.** ADR 0008 blocks a release on unclassified
> API symbols by comparing the incoming baseline against the previous
> one. Keep the outgoing baseline's pinned inputs in the tree for the
> duration of the upgrade round so that comparison has both sides, and
> remove them in the same commit that ships the new one.

## 1. Choose the release and resolve its commit

Pick an exact stable version newer than the newest checked-in baseline
and resolve its tag commit:

```sh
curl -s https://api.github.com/repos/microsoft/vscode/git/ref/tags/<version>
```

The `object.sha` of the tag is the pin commit for every input.

## 2. Fetch and pin the six official inputs

Create `packages/dart_vscode/tool/bindings/inputs/vscode/<version>/`
and fetch each input
from `https://raw.githubusercontent.com/microsoft/vscode/<commit>/...`
at the canonical repository paths (`tool/binding_importer/src/pins.cjs`
holds the kind-to-path map and rejects any other source URL):

- `vscode.d.ts` — `src/vscode-dts/vscode.d.ts`
- `extension-manifest-schema.ts` —
  `src/vs/workbench/services/extensions/common/extensionsRegistry.ts`
- `extension-validator.ts` —
  `src/vs/platform/extensions/common/extensionValidator.ts`
- `menusExtensionPoint.ts` —
  `src/vs/workbench/services/actions/common/menusExtensionPoint.ts`
- `strings.ts` — `src/vs/base/common/strings.ts`
- `LICENSE.txt` — `LICENSE.txt`

Copy the previous baseline's `pins.json` beside them and update the
product version, the commit, every source URL, and every `sha256`
(`shasum -a 256 <file>`). The `parser.version` must equal the
TypeScript version pinned in `tool/binding_importer/package.json`; the
importer refuses a mismatch.

## 3. Import the canonical IR

```sh
cd tool/binding_importer
npm ci
node src/cli.cjs \
  --pins ../bindings/inputs/vscode/<version>/pins.json \
  --output ../bindings/ir/vscode-<version>.json
```

The importer verifies every pinned checksum before parsing and fails
closed on inexpressible syntax. The output lands at
`packages/dart_vscode/tool/bindings/ir/vscode-<version>.json`.

## 4. Review the delta into Semantic Overrides

Author `packages/dart_vscode/tool/bindings/overrides/vscode-<version>.json`.
Start from the
previous baseline's file with `vscodeVersion` advanced; the root
evidence hashes only change when the manifest schema, validator, or
contribution schema inputs changed. Then classify the API delta —
the series validation rejects every new, shape-changed, or removed
public symbol that lacks a reviewed entry with the candidate
declaration's current fingerprint (removals need strategy
`reviewedRemoval` plus a reason).

A delta can be pure source metadata — when `vscode.d.ts` and the
schema/validator inputs are byte-identical and only, say, `strings.ts`
changes outside the extracted validation projection, the previous
reviewed classifications carry over unchanged.

A larger delta can also surface a construct the Complete Parity Layer
has no Total Mapping Rule for; generation then fails with a
`ParityGenerationException` naming the declaration. Add a total,
judgment-free rule with emitter unit cases (ADR 0012,
`specs/research/js-to-dart-mapping.md`) — never a special case for one
symbol.

## 5. Validate the series

```sh
cd tool/binding_importer
npm run check:baseline-series
```

This validates the seed and every adjacent baseline pair, and rejects
orphaned IR or override files. CI reaches the same validation through
`./scripts/test_binding_importer.sh` (Docker, pinned Node).

If the round touched any file receipted by the durable Host Contract
(the CLI, generator, or fixture sources), regenerate the contract —
it repins `artifactSha256` into every checked-in override file:

```sh
dart packages/dart_vscode/tool/binding_generator/generate.dart --contract .
```

## 6. Retarget the package and prove it end to end

Advance `vscodeApiVersion` in
`packages/dart_vscode/lib/src/contributions/vscode_api_version.dart`,
regenerate the layer and ledgers, rebuild the fixture and both shipped
extensions, then run every package's suite:

```sh
dart packages/dart_vscode/tool/binding_generator/generate.dart --dart-layer .
dart packages/dart_vscode/tool/binding_generator/generate.dart --contract .
./scripts/build_host_fixture.sh
(cd packages/dart_vscode && dart test)
(cd packages/flutter_vscode && flutter test --exclude-tags gate)
```

Record the new baseline in `CHANGELOG.md`: for consumers it is a
breaking change, because the generated `engines.vscode` minimum moves
with it.

## Related

- [Binding pipeline](../../specs/architecture/binding-pipeline.md)
- [ADR 0008: block releases on unclassified API symbols](../adr/0008-block-releases-on-unclassified-api-symbols.md)
- [ADR 0012: generate the complete parity layer with total mapping rules](../adr/0012-generate-the-complete-parity-layer-with-total-mapping-rules.md)
