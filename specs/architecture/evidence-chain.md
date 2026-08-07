# Evidence Chain

Five hardening rounds taught one structural lesson: claims recorded as
prose rot; claims enforced by machines survive. Everything here exists to
keep "verified" meaning something.

## Receipts and the durable Host Contract

`packages/dart_vscode/tool/bindings/contracts/checkpoint4-extension-host.json` attests the
real-host evidence run: API and runtime targets, one source receipt
per load-bearing file (exact SHA-256 — generator, writer, CLI, the
generated API layer, fixtures, lockfiles, the verifier, its test,
and the contract writer itself; the artifact's `sources` block is the
authoritative list, not any count in prose), and the attributed
binding IDs. It is written only by the
mechanical regenerator (`packages/dart_vscode/tool/binding_generator/contract.dart`, invoked
as `generate.dart --contract .`); hand-editing evidence is not a
supported workflow. Overrides pins are per-baseline: every checked-in
baseline cites the same checkpoint-4 contract, and the contract writer
surgically repins the `artifactSha256` in each
`packages/dart_vscode/tool/bindings/overrides/vscode-*.json` on every write.
`packages/dart_vscode/test/binding_evidence_test.dart` proves the checked-in artifact
byte-equals regeneration and that the overrides pin matches its bytes;
the real-host launcher verifies all receipts before VS Code starts and
again before accepting evidence (`packages/flutter_vscode/tool/extension_host_test/run.cjs`,
`host_contract.cjs`). Attribution is mechanical and says so: binding
IDs cite the one receipted contract whose gate passed its surrounding
native behavior — there is no per-member observation mechanism, and
neither the ledger nor the contract claims independent behavioral
contracts (the `evidence.meaning` field states this in the artifact
itself).

The machine-checked totality artifacts are ledgers, not prose: the
substrate's `packages/dart_vscode/tool/bindings/parity-ledger.json` and the ergonomic
surface's `packages/dart_vscode/tool/bindings/dart-layer-ledger.json` — both written by
one `--dart-layer` run for the one generated API artifact — must each
byte-equal regeneration and cover exactly the IR
(`test/parity_layer_test.dart`, `test/dart_layer_test.dart`).

## Gate hierarchy

1. Focused suites (`flutter test`, importer `npm test`, Node harness
   tests) — including `packages/flutter_vscode/test/plan_truth_test.dart` (prose-truth ratchet),
   `packages/flutter_vscode/test/repository_gate_test.dart` (CI-definition pins, generated
   convergence, lockfile-in-HEAD, cache freshness), and
   `test/v0_removal_test.dart` (the deleted v0 pipeline stays deleted).
2. `./scripts/test_host_extension.sh` — the pinned real Extension Host in
   Docker, receipt-verified, with adversarial webview probes.
3. `./scripts/test_packaged_extension.sh` — installed-VSIX proof for both
   fixtures, staged from `dart pub`'s own archive listing
   (`packages/flutter_vscode/tool/pub_archive_list.dart`), hover-first lazy activation asserted.
4. `./scripts/test_coverage_extension.sh` — the shipped
   `extensions/coverage_treemap` example, built and packaged by the
   CLI, installed into the pinned Extension Host in Docker against a
   workspace with a known tracefile; asserts the parsed coverage
   snapshot and that the Flutter View boots and serves it over the
   view protocol in a real webview.
5. `./scripts/test_breakpoints.sh` — proof that breakpoints bind to
   Dart source lines through the emitted source maps in the pinned
   host: the driver decodes the fixture's source map, arms every
   mapped generated position over `--inspect-extensions`, and the
   Extension Host pauses on a location that maps back to the same
   Dart line (`packages/flutter_vscode/tool/extension_host_test/run_breakpoint.cjs`).
6. The CI workflow (`.github/workflows/test.yml`) — the one aggregate:
   every package's suite as a standard-runner step, and every real-host
   gate script as its own step, breakpoints included.
   `scripts/ci_gates.sh` runs the same workflow locally, each job on
   the platform it declares. Nothing in this chain runs only when
   someone remembers it.


## Methodology (inherited, binding on future rounds)

- **Frozen exit bars.** A hardening round freezes its machine-checkable
  exit bar before work starts; discoveries go to
  `specs/plans/futures.md`, never into the running bar. Only the round's
  script may declare it done. Owners may amend a bar; amendments are
  recorded visibly with what was lost.
- **Reds are commits.** Failing tests are committed before their fixes so
  chronology is `git log`, not narrative. Where a red is inexpressible
  in-repo, the ledger says exactly that.
- **Prose truth.** Documents may not carry present-tense claims a machine
  cannot vouch for. `packages/flutter_vscode/test/plan_truth_test.dart` enforces digest truth and
  self-consistency for the archived plan and pins its bytes: the archive
  is frozen history, so any edit fails the ratchet deliberately.
- **Status validity.** A completion claim holds only while its named
  check script exits 0 at HEAD.
