# Parity Layer Plan

Status: Implemented and verified — sixth-audit hardening applied; valid only while the parity suite and gates are green at HEAD
Date: 2026-07-22

Per the updated vision and ADR 0012, the entire pinned stable API surface
is emitted as one mechanically generated, typed Dart layer produced only
by Total Mapping Rules — zero judgment calls, hard generation errors for
anything unmapped. Strategy and per-construct rules:
[`specs/research/js-to-dart-mapping.md`](../research/js-to-dart-mapping.md).
The IR census behind the rules: 6 intersection sites, 21 tuple sites, 26
rest parameters, 28 index signatures, one call-signature interface
(`Event`), `with`×6 and `toString`×1 reserved/core-name manglings, and
the platform-wide `undefined`/`null` conflation documented as `T?`.

Rules of this plan (inherited from the evidence-chain methodology): the
exit bar below is frozen; reds are commits; discoveries go to
[`futures.md`](futures.md); behavioral verification of parity members in
a real Extension Host is explicitly NOT part of this bar (ADR 0012 moves
it to the burn-down in [`futures.md`](futures.md)). (Post-bar note: the
sixth-audit round nevertheless added a real-host parity smoke to the
gate — work beyond the frozen bar, recorded in ledger entries 3–4; the
per-capability behavioral burn-down itself remains future work.)

## Exit bar

- [x] P-1 A parity emitter (`generate.dart --parity-layer .`) consumes the
  pinned IR and emits `lib/src/generated/vscode_parity_layer.g.dart`,
  exported as `package:flutter_vscode/vscode_parity.dart`. The module
  object an extension receives at activation is the only root: no new
  globals; constructors and statics reach JS through the module wrapper.
  Check: `flutter test test/parity_layer_test.dart` (regeneration
  byte-compare).
- [x] P-2 Totality accounting: every declaration in the IR is either
  emitted or recorded in a generated ledger naming its rule (permitted
  erasure classes: symbol-keyed members, Thenable-as-JSPromise,
  non-public); a declaration in neither set fails the test. Check: the
  suite's totality assertions over `tool/bindings/parity-ledger.json`.
- [x] P-3 The generated layer analyzes cleanly (`dart analyze
  --fatal-infos` on the generated library runs inside the suite) and
  regenerates byte-identically.
- [x] P-4 Per-construct rules hold, asserted structurally on the real
  output: LUB union erasure at external boundaries, overload expansion
  with deterministic `$n` suffixes bound via `@JS`, numeric-enum `int`
  typedefs with module-rooted value accessors, type-literal extension
  types, `[]`/`[]=` index signatures, typed tuple accessors over
  `JSArray`, implements-both intersections, `JSPromise<T>` for
  Thenable/Promise, reserved-word `$` mangling, readonly-as-getter,
  `T?` optionality, call-signature interfaces over `JSFunction`.
- [x] P-5 Unmapped constructs fail generation with a
  `ParityGenerationException` naming the declaration and missing rule
  (proven with a synthetic IR fragment).

Status update: all exit-bar items closed; see the ledger.

## TDD Ledger

Tallies and line counts are values at each entry's recording time; the
executing suites and files are the current authority.

1. **Red** (commit 643eb85): `flutter test test/parity_layer_test.dart`
   failed across the bar — the emitter stub threw UnimplementedError and
   no generated library, ledger, or export existed.
2. **Green**: `tool/binding_generator/parity_layer.dart` implements the
   Total Mapping Rules from the research decision table; the emitted
   6,018-line library covers the full pinned surface. Reality corrected
   three rules mid-implementation, all mechanically: VS Code's own rest
   parameters are named `args` (helper locals are now collision-proof by
   construction), registered anonymous types and tuples hoisted to the
   top level erase in-scope type parameters to `JSAny?`, and generic
   classes' constructors carry the class's type-parameter clause on
   `new$`. Two emitter robustness gaps surfaced by the analyzer loop —
   leading-underscore JS names becoming Dart-private, and duplicate
   anonymous shapes at distinct sites — closed by `$`-prefix mangling
   and shape-hash deduplication. `flutter test
   test/parity_layer_test.dart` passes 15/15: byte-compare regeneration,
   totality accounting over all 2,982 declarations, `dart analyze
   --fatal-infos` clean on the generated library (zero issues), every
   structural rule, and the synthetic totality error. The SDK floor rose
   to 3.6 for extension types and `JSArray` operators; the evidence
   chain regenerated for the receipted pubspec change.
3. **Sixth-audit hardening** (red committed before the fixes). The audit
   and its execution probe confirmed the layer works against a module
   object and found the recurring proof-weaker-than-sentence pattern
   plus three substantive holes. Red — nine new structural tests, three
   failing honestly: mixed-category unions emitted a spurious `JSAny?`
   (the research rule says `JSAny`), six ctor-less classes
   (EventEmitter, WorkspaceEdit, CancellationTokenSource, DataTransfer,
   SignatureHelp, LanguageModelError) were silently unconstructable, and
   the blessed object-literal creation rule was unimplemented. Green —
   mixed unions erase to `JSAny`; every ctor-less class gets a default
   `new$`; interfaces and registered type literals with plain-identifier
   members gain `lit$` object-literal factories (method members typed
   `JSFunction`, making provider interfaces implementable); the suite
   passes 23/23 with the output still analyze-clean. A real-Extension-
   Host parity smoke joins the host gate: version, negative enums,
   construction, `toString$`/`with$` renames, an awaited promise
   round-trip, an Event subscription, and a hover provider created
   entirely from literal factories, registered, exercised, and disposed
   against live VS Code.
4. **Real-host execution proof.** Red — `./scripts/test_host_extension.sh`
   exited 1 with `command 'flutter-vscode.host-test.paritySmoke' not
   found` (the committed red; full log captured). Greens required three
   honest harness corrections, each observed in the live gate: the
   rollback expectation grew from six to eight registrations, the hover
   assertions had to distinguish the parity provider from the facade's
   own json provider by content (the parity provider itself worked on
   first contact), and the smoke's document open had to run after the
   event-unsubscribe accounting. Final green — the gate exits 0 with all
   twelve sections passing: the parity layer's version read, negative
   enum values, `Position.new$` plus `translate`, `Uri.file` and
   `toString$`, an awaited `getCommands` JSPromise round-trip, an Event
   subscription and disposal, and a hover provider constructed from
   `lit$` object-literal factories serving real hovers on live VS Code
   documents and disposing on command. `flutter_vscode build` now emits
   the layer into every Extension Project as
   `vscode_parity_layer.g.dart`, and the receipt closure covers it.
