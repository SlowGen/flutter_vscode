---
status: accepted
---

# Block Releases on Unclassified API Symbols

An API Parity Baseline update will fail when the Binding Pipeline encounters an
unclassified or ambiguous symbol. A maintainer must add an explicit Semantic
Override or extend a general translation rule before the new baseline can ship;
the generator will never silently drop the symbol, infer a likely meaning, or
replace it with `dynamic` unless `dynamic` is the faithful upstream type.

The previous baseline remains supported while the update is resolved. This
trades automatic release speed for compile-time accuracy and prevents
plausible-but-wrong bindings from becoming failures for Extension Users.

Checked-in baselines form an immutable, numerically ordered series beginning
with the explicit `1.129.1` seed. Maintainers add a new
`tool/bindings/ir/vscode-MAJOR.MINOR.PATCH.json` and its same-version Semantic
Override; they do not replace or delete earlier files. Run the enforced
repository gate:

```sh
./scripts/test_binding_importer.sh
```

That command, and therefore the full CI gate, discovers every checked-in
`vscode-*.json` baseline, validates the seed, and checks each adjacent
old-to-candidate pair. It rejects new public IDs and changed public shapes
unless the candidate has an explicit reviewed classification with the
candidate declaration's current fingerprint. Removed public declarations
require a `removals` entry with strategy `reviewedRemoval`, the previous
declaration fingerprint, and a non-empty review reason. Removal metadata cannot
claim executable Host evidence.

Targets, entries, removals, baseline files, and same-version override files are
exact sets: stale or orphaned metadata fails the gate. Non-public inventory is
mechanically excluded, and the existing baseline's visible pending entries are
not retroactively presented as supported.
