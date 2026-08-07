# Parity Runtime Verification Plan

Status: Implemented and verified — valid only while the parity, unit, and host-gate suites are green at HEAD
Date: 2026-07-23

Graduates the parity follow-ups from `futures.md` per owner direction:
runtime proof lives in the real Extension Host (no fake-module harness —
fakes prove marshaling, not VS Code), the two helper families ADR 0012
originally promised ship for real, the emitter gains rule-level unit
tests, and "behavioral burn-down" is pinned to a machine-checked
definition: at least one live-executed representative per API family.

Rules (inherited): the exit bar is frozen; reds are commits; discoveries
go to [`futures.md`](futures.md).

## Exit bar

- [x] V-1 Registered type literals get derived stable typedefs
  (deterministic name from the owning declaration path, e.g.
  `PositionWith$change`) so fixture and author code never references a
  shape-hash name. Check: emitter unit tests + parity suite.
- [x] V-2 The promised helper families ship: every class `Ctor` type
  gains `isInstance`/`cast` narrowing against the module-rooted class
  function (planned via the SDK's `instanceOf`, which turned out not to
  exist; shipped via `prototype.isPrototypeOf` — see ledger entry 2), and unions consisting only
  of string literals emit zero-cost typed wrappers (`static const` per
  literal; named aliases keep their alias name; generic positions keep
  erasure). ADR 0012's amendment note is superseded accordingly. Check:
  emitter unit tests, parity suite, and a live narrowing probe in V-4.
- [x] V-3 A table-driven emitter unit suite exercises every Total
  Mapping Rule and every totality throw site through the public
  `emitParityLayer` with minimal synthetic IRs — rule-level failure
  localization the byte-compare cannot give. Check:
  `flutter test test/parity_emitter_unit_test.dart`.
- [x] V-4 Per-family live execution: the real-host parity smoke
  exercises at least one representative member of EVERY namespace family
  in the pinned API plus the core value-class families (default-ctor
  construction via `CancellationTokenSource`/`EventEmitter` round-trips,
  a `WorkspaceEdit` applied to a real document, clipboard round-trip,
  output channel, provider/controller registrations disposed). A
  repository test derives the required family list from the IR's
  namespaces so a future API family cannot be silently skipped. Check:
  `./scripts/test_host_extension.sh` green with the family assertions;
  the completeness test in the parity suite.
- [x] V-5 The burn-down definition is recorded: `docs/reference/parity.md`
  states that family-level live coverage is measured by the smoke and
  member-level evidence by the capability fixtures; futures.md drops the
  graduated items. Check: report regeneration test.

## TDD Ledger

Tallies are values at recording time; the executing suites are the
current authority.

1. **Red** (commit c32e7f3): the table-driven emitter unit suite landed
   with three honest failures — derived stable typedefs, Ctor
   narrowing, and string-literal wrappers did not exist — alongside 23
   born-green rule and throw-site cases.
2. **Green V-1..V-3** (commit 736af4b): 66 derived stable typedefs
   (`PositionWith$1` style); `isInstance`/`cast` on all 122 class
   objects via `prototype.isPrototypeOf` after the SDK's constructor
   `instanceOf` proved nonexistent; the literal-wrapper rule proven on
   synthetic IR (zero sites in the pinned baseline); unit suite 25/25;
   layer regenerated analyze-clean.
3. **Red V-4**: the live gate exited 1 at the per-family assertion with
   the fixture reporting no families (full log captured); the
   completeness test derives the required sixteen families from the IR.
4. **Green V-4**: all sixteen namespace families execute against live
   VS Code in one smoke — subscriptions, controllers, providers, chat
   participant, clipboard and l10n round-trips, an applied
   WorkspaceEdit on a document opened through an overload-suffixed
   options literal, EventEmitter and CancellationTokenSource default-
   ctor round-trips, isInstance narrowing, and a stable-typedef `lit$`
   change object through `with$$2`. Compiling the fixture against the
   real layer corrected three call sites (options typedef ordinal;
   reserved-word-plus-overload mangling) — exactly the class of fact
   only live usage surfaces. Final gate green at the lint-clean HEAD.
5. **V-5**: ADR 0012 restored to describe shipped reality; the parity
   report states the family-level coverage definition; futures drops
   the graduated items.
6. **Post-close audit (2026-07-23)**: a synthetic-IR probe showed the
   V-2 named-alias clause unimplemented — an all-string-literal alias
   erases its typedef to `JSString` while the wrapper takes a
   shape-hash name that appears in member signatures. Latent: the
   pinned 1.129.1 baseline contains zero string-literal-union aliases,
   so no shipped output is affected. The alias-named-wrapper rule
   lands with [developer-experience.md](developer-experience.md) D-2.
