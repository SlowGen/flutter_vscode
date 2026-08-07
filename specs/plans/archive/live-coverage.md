# Construct-Class Live Coverage Plan

Status: Implemented and verified — valid only while the parity, unit, and host-gate suites are green at HEAD
Date: 2026-07-23

Per the domain language, live coverage has two axes: API Families
(wiring/reachability — floor of one, already enforced) and Construct
Classes (do the mappings work against real objects). This plan fills the
empty construct-class rows and makes both axes machine-derived.

## Exit bar

- [x] C-1 The canonical Construct Class list is code
  (`parityConstructClasses` in the emitter library) with an explicit
  live-exemption map (each exemption naming its reason, e.g. zero sites
  in the pinned baseline). Check: the two-axis completeness test.
- [x] C-2 Every Construct Class has an emitter unit case, including the
  previously missing intersection, call-signature, and external-setter
  cases. Check: completeness assertion over the unit suite source.
- [x] C-3 Every non-exempt Construct Class has a tagged live probe
  (`cc:<class>`) in the real-host smoke, including the new rows: tuples
  via `workspace.fs.readDirectory(extensionUri)`, the
  Memento-intersection via `context.globalState`
  (setKeysForSync/update/get), an external setter via
  `createQuickPick().value`, index operators against real
  `workspace.getConfiguration()`, real-union narrowing via
  `tabGroups...activeTab.input` and `TabInputText.isInstance`, and
  reverse-direction callback arguments via `withProgress` with a `lit$`
  progress report. Check: `./scripts/test_host_extension.sh` green with
  the new assertions; two-axis completeness test.
- [x] C-4 `docs/reference/parity.md` states the two-axis definition with
  both lists machine-derived (families from the IR, classes from the
  emitter constant); member-level live accounting via generated
  observation hooks is recorded in futures as the next burn-down
  instrument. Check: report regeneration test.

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **Red C-1..C-3** (commit at the time): the two-axis completeness
   test landed against the canonical `parityConstructClasses` list and
   `parityLiveExemptions` map — six construct classes had no tagged
   live probe and three had no unit case; the live gate exited 1 at
   the tuple assertion in the real Extension Host (full log captured).
2. **Green C-1..C-3** (commit 04eaafa): every emitter unit case name
   carries a `(cc:<class>)` tag; tuple/type-literal/function-type unit
   cases added (56/56); the fixture's paritySmoke gained the six
   probes — directory-entry tuples, the globalState
   Memento-intersection, a QuickPick setter round-trip, configuration
   `operator []`, TabInputText union narrowing on the active tab
   input, and `withProgress` callback arguments with a `lit$` report —
   and the real-host gate ran green (exit 0, 11/11 harness tests).
   Compiling against the real layer surfaced nothing this round; the
   analyzer demanded two cascades.
3. **Red C-4** (commit 8468750): the report test requires the two-axis
   definition with families quoted from the IR, classes quoted from
   the emitter constant, and every exemption reason present — the
   generated report had only family-level prose.
4. **Green C-4**: `buildParityReport` takes the pinned IR, derives the
   16 families and 23 construct classes, and emits both lists plus the
   exemption reasons; futures records member-level live accounting via
   generated observation hooks as the next burn-down instrument.
