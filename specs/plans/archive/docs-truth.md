# Docs Truth Plan

Status: Implemented and verified — valid only while the docs gates
(plan_truth, repository_gate, the single-layer docs grep, link-check)
are green at HEAD
Date: 2026-07-25

Brings the documentation corpus to truth at HEAD. The original
default-battery audit (46 pages, 42 findings) predated the
single-layer round, whose SL-3 wave rewrote eight of the audited
pages; this re-scope keeps only what remains open at HEAD, per-item
verified. The `.improve-docs/` baseline predates SL-3 — DT-0 refreshes
it so deltas measure this round's work, not the single-layer round's.

Rules (inherited): the exit bar is frozen; edits land on a branch in
grouped commits; generated pages are regenerated, never hand-edited;
no history rewrites in ADRs — amendments only; discoveries go to
[`futures.md`](futures.md).

## Exit bar

- [x] DT-0 Fresh baseline: re-run the census and polish/drift scoring
  over the corpus at HEAD into `.improve-docs/baseline.json` before
  any edit, so per-dimension deltas attribute honestly. Check: the
  report's deltas reference the new baseline date.
- [x] DT-1 Front door: README and quickstart document the full CLI
  surface (`doctor`, `test`, `build --watch` — all absent from the
  README today), both pinned baselines with `apiTarget` selection
  (1.130.0 appears only in the new-baseline guide today), and name
  ViewShell in the view walkthrough. The one-layer presentation and
  example section are already true — do not re-litigate. Check:
  repository_gate_test green; fresh-eyes pass records no stale claim.
- [x] DT-2 Reference: wire-v2 protocol documentation exists — either
  Closed (2026-07-25): the README walkthrough gained `doctor` (with
  its real `[ok]`/`[!!]` output shape) before the build step,
  `build --watch` with the exact watched roots, and a Test it section
  matching `flutter_vscode test`'s suite discovery; both pages now
  name the two pinned baselines (1.129.1 default, 1.130.0) with
  `apiTarget` selection and link the new-baseline guide; the README
  view walkthrough names `ViewShell.connect` (session, theme stream,
  host-pushed events, one `dispose`). The quickstart gained a DT-7
  opener and `--watch` in its build step; it has no view walkthrough,
  so ViewShell naming lives in the README's. Per owner directive (no
  legacy framing — the docs describe only the current workflow), the
  README's "Legacy v0 webview workflow" section and the quickstart's
  "Legacy webview scaffold" section were deleted; the repository
  gate's labeled-or-gone rule is satisfied by gone, so no test
  expectation changed. Every command, flag, and output shape was
  verified against `bin/flutter_vscode.dart` and `lib/src/cli/` at
  HEAD; repository_gate_test green.
- [x] DT-3 Guides: troubleshooting.md names the v2 handshake, leads
  with `flutter_vscode doctor`, and replaces the pre-totality
  missing-API remedy (the generated layer is total; "pending" means
  unverified, not unsupported); agent-assisted-development.md's
  working model reflects the total generated layer and the full CLI
  (test/doctor in the run loop). Check: every named error code and
  remedy matches the CLI at HEAD.
- [x] DT-4 Agent surface: project-structure.md teaches the current
  Closed (2026-07-25): troubleshooting.md now opens with a `doctor`
  first step (its real `[ok]`/`[!!]` shape), describes the version-2
  `ready`/`readyAck` session/nonce handshake in the blank-view entry,
  and replaces the missing-API remedy with the totality rule — a
  `pending` `coverage.json` entry is unverified, not unsupported; a
  construct the generator cannot map fails as
  `ParityGenerationException` and is a framework defect to report.
  The two error codes the page now names
  (`HOST_IMPORT_BOUNDARY_VIOLATION`, `STALE_BUILD_ARTIFACTS`) both
  exist in `lib/src/cli/` at HEAD. agent-assisted-development.md's
  working model became
  edit -> doctor -> build [--watch] -> test -> package, its coverage
  paragraph teaches absent-from-coverage != unsupported, and its
  checklist adds doctor/test; surgical edits, length and voice kept.
  Both pages gained DT-7 openers. Per the same owner directive as
  DT-1, troubleshooting.md's "Legacy v0 projects" section and
  agent-assisted-development.md's closing legacy-mapping pointer were
  deleted; vscode-api-mapping.md stays linked from
  `docs/reference/index.md` and `AGENTS.md`, so no orphan results.
- [x] DT-5 ADR residue: ADR 0012's amendment gains the release-gate
  correction (per-symbol reviewed classification survives at baseline
  import per ADR 0008 as amended; the no-rule block applies at layer
  generation); ADR 0011 gains the missing-apiTarget fallback caveat.
  The 0006/0012 one-layer amendments already landed in SL-4. Check:
  originals untouched below amendment lines.
- [x] DT-6 Structure (amended by owner directive: no legacy content
  survives — we build on a branch): docs/architecture/index.md is a
  true pointer to specs/architecture/; docs/adr/index.md lists all
  thirteen ADRs and is linked from docs/index.md; the legacy pages
  (consumer-agents-v0.md, vscode-api-mapping.md, and — via DT-2's
  amended resolution — message-contract.md) are deleted outright with
  their referrers cleaned, not linked as variants. Structural moves
  landed in their own commits. Check: link-check clean, zero legacy
  orphans.
- [x] DT-7 Polish on touched pages: openers 40–80 words naming thing,
  audience, and place; motivation and cross-links; no reflow of
  untouched pages. Check: fresh-eyes review; per-dimension deltas vs
  the DT-0 baseline.

Verification gate: link-check clean; plan_truth_test,
repository_gate_test, the parity-report regeneration pin, and
`flutter analyze` green; the report records deltas against the DT-0
baseline and remaining distance to the bar.

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **DT-0** (2026-07-25): baseline re-snapshotted at HEAD b3081d8
   (38 docs pages) into `.improve-docs/baseline.json`, superseding the
   pre-single-layer snapshot so this round's deltas attribute honestly.
2. **DT-4** (cb7c8ac, a4e713f, 2026-07-25): a docs item has no
   executable red; every claim was instead ground-truthed against
   HEAD before writing — the CLI surface against
   bin/flutter_vscode.dart and lib/src/cli/, suite discovery against
   test_command.dart, watch semantics against watch_command.dart,
   every troubleshoot error code grepped to its CliException site,
   and the view skill's identifiers against view_shell.dart, the
   theme bridge, view_protocol.dart, and the shipped treemap_panel
   consumer. Two pages and four skills updated, one skill added and
   registered; the extension-host skill was verified current and left
   untouched. plan_truth (5) and repository_gate (14) green at
   recording time; flutter analyze clean (the nested fixture and
   example-extension packages needed only local dependency
   resolution, no source change).

3. **DT-5/DT-6** (2026-07-25): the 0012 release-gate-composition and
   0011 apiTarget-fallback amendments landed append-only; the
   architecture index reduced to a pointer, the thirteen-ADR index
   landed and is linked from the docs root — and mid-round the owner
   directed the legacy purge: no legacy framing anywhere, so
   vscode-api-mapping.md and consumer-agents-v0.md are deleted with
   referrers cleaned, and DT-2's resolution amends from
   keep-as-legacy-record to delete message-contract.md outright.
4. **DT-2** (2026-07-25): `docs/reference/view-protocol.md` lands as
   the one protocol reference; an owner directive during execution
   superseded the approval-time resolution, so message-contract.md is
   deleted rather than kept as a linked legacy record and
   reference/index.md drops its legacy-flagged entries while gaining
   the new page and startup.md; link-check reports zero broken links
   and neither page is an orphan.
5. **DT-1** (2026-07-25): the front door now teaches the full CLI —
   README gained doctor-before-build, `build --watch`, and a Test it
   section; README and quickstart both name the two pinned baselines
   with `apiTarget` selection and link the new-baseline guide; the
   README view walkthrough names ViewShell
   (connect/theme/events/dispose); per owner directive both pages'
   legacy-workflow sections were deleted outright. All claims
   ground-truthed against `bin/flutter_vscode.dart` and
   `lib/src/cli/` at HEAD; repository_gate_test green at recording
   time.
6. **DT-3** (2026-07-25): the guides shed their pre-totality residue —
   troubleshooting.md leads with `doctor`, names the version-2
   `ready`/`readyAck` handshake, and treats a `pending` coverage
   entry as unverified rather than unsupported (an unmappable
   construct is a `ParityGenerationException`, a framework defect);
   agent-assisted-development.md's loop is now
   doctor -> build [--watch] -> test -> package over the total
   generated layer; per the DT-1 owner directive, both pages' legacy
   sections were deleted outright. Error codes named on the pages
   verified against `lib/src/cli/`; repository_gate_test and
   plan_truth_test green at recording time.
7. **Round close** (2026-07-25): all seven DT items landed; the
   owner's mid-round no-legacy directive expanded the purge to every
   living page — the v0-era reference pages (message-contract,
   vscode-api-mapping, roadmap, prd-traceability, consumer-agents-v0)
   are deleted with referrers cleaned, and every legacy/v0 section on
   surviving pages is gone (zero mentions in living docs). Final
   state: 0 broken links, 0 orphans (the ADR index cured ten),
   repository_gate + plan_truth + analyze green. The v0 pipeline CODE
   deletion is recorded in futures as the next round.
7. **Post-close audit (2026-07-25)**: fresh eyes found five
   spirit-level gaps in the close — a half-deleted sentence left
   `generated-host-api.md` truncated mid-reference, the ADR index's
   thirteen links all carried `---` titles (the generator read
   frontmatter as the heading), `author-workflow.md` described a
   phantom legacy-surface gate, `code-generation.md` still taught the
   deleted annotation pipeline's analyzer machinery, and AGENTS.md
   carried a stale plan label plus a duplicate link. All five fixed
   at archive time; the letter-level checks (deletions, new pages,
   suites) had all held.
