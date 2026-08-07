# Code Generation Rules

## Generator Architecture

- Parse pinned official VS Code inputs into canonical IR before generating host
  bindings or contribution models.
- Pin transitive validation helpers as inputs too. The commands projection
  recognizes the exact upstream `isFalsyOrWhitespace` implementation and
  lowers JavaScript trim behavior as `ecmascript-trim-empty`; do not substitute
  Dart `String.trim()` or infer semantics from the helper name.
- Project the direct manifest type, entrypoint, and engine-version predicates
  used by generated packages from the pinned `extension-validator.ts`. The
  engine regex is projected exactly. The rest of `validateExtensionManifest`
  is integrity-pinned by `validatorBodySha256`; the imported `semver.valid`
  implementation remains an unprojected external dependency, and the project
  makes no equivalence claim for it.
- Combine IR only with reviewed, fingerprinted Semantic Overrides. New,
  changed, or removed public declarations fail closed with the exact path and
  remediation. A reviewed removal records the previous fingerprint and a
  reason; it never cites Host execution evidence.
- Add API baselines as immutable `vscode-MAJOR.MINOR.PATCH.json` files; never
  replace the explicit `1.129.1` seed or an earlier baseline. Run
  `./scripts/test_binding_importer.sh`. Its automatic series gate compares each
  adjacent candidate with its predecessor, validates the seed, and requires a
  current, fingerprinted classification for every new, changed, or removed
  public symbol. Stale targets, entries, removals, contracts, or orphaned
  baseline/override files fail closed.
- Require every pinned official VS Code source to carry the exact product
  version and commit in addition to its own checksum, source URL, and license.
- Generate identical bytes for identical inputs and tool versions; never use
  locale-dependent ordering, clocks, environment values, or inferred types.
- Use actionable, stable error codes at every generator boundary.

## Analyzer API Usage

- The only analyzer use is AST-parsing the project descriptor
  (`lib/src/cli/project_descriptor.dart`): parse as data, never
  execute project code.
- The binding pipeline consumes pinned IR JSON, not analyzer
  elements; generation stays deterministic from pinned inputs
  (ADR 0007).

## Output Conventions

- Keep generated output formatted and readable.
- Mark framework-managed output as generated and never mix author edits into it.
- Emit a coverage ledger that distinguishes discovery, semantic review, binding
  emission, exclusions, and mechanically attributed real-host execution. Do
  not describe one operation's erased type IDs as independent behavioral
  contracts.
- Back every verified Host Contract with a compact artifact retained in the
  published package. The artifact records exact binding IDs, the source
  repository, and SHA-256 hashes of excluded executable test sources; the real
  Extension Host launcher rejects missing, extra, or duplicate IDs.
- Attribute Host Contract binding IDs mechanically from the active Semantic
  Overrides to the receipted real-host contract; there is no per-member
  observation mechanism. Tests and author-owned Host Dart must never report
  binding IDs themselves, and neither the ledger nor the contract may claim
  independent behavioral contracts.
- Regenerate twice in CI and compare bytes.

## Related

- [Reference Index](../reference/index.md)
- [VS Code Integration Rules](vscode-integration.md)
