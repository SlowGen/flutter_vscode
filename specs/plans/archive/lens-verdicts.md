# Lens Verdicts Plan

Status: Implemented and verified — valid only while the fast suites
and the pubspec-lens real-host gate are green at HEAD
Date: 2026-07-27

Pubspec Lens only speaks when a constraint *excludes* the latest
release. Because caret constraints admit every minor and patch below
the next major, the extension stays silent on the common case: a
pinned lower bound that trails what pub.dev publishes. In the owner's
live session four of five dependencies (`path ^1.8.0` vs 1.9.1,
`http ^1.5.0` vs 1.6.0, `test ^1.24.0` vs 1.31.2) were silently
"current", and the one flagged dependency was the lone major bump.
That reads as a broken lens, not a conservative one.

This round makes a trailing lower bound its own verdict, so the lens
offers the bump while the Problems panel keeps meaning "this
constraint blocks the latest release".

Rules (inherited): exit bar frozen; reds are commits; no legacy or
compatibility surface — the branch is the product; discoveries to
[`futures.md`](futures.md).

## Decisions

- **Two signals, not one.** `outdated` (the constraint excludes the
  latest — nothing will resolve to it) keeps the diagnostic *and* the
  lens. `behind` (the constraint admits the latest but the pinned
  lower bound trails it) gets the lens only. Squiggles stay reserved
  for constraints that actually block.
- **Never suggest a downgrade.** A constraint whose lower bound sits
  at or above the latest published version has nothing to suggest and
  is `current` — including the ahead-of-registry case (`^2.0.0` while
  the registry says 1.6.0), which the old rule called `outdated` and
  offered to "fix" by rewriting the pin *backwards*.
- **The lower bound is the comparison point**, read structurally from
  `pub_semver` (`VersionRange.min`, `VersionUnion.ranges.first.min`;
  `Version` is its own `min`), not by re-parsing constraint text.
- A constraint with no lower bound (`any`, or a bare `name:`) is
  `behind` with a `^latest` suggestion; the host's existing
  constraint-span guard means no lens renders for a bare entry, since
  there is no written constraint to replace.

## Exit bar

- [x] LV-1 Verdict semantics: `VerdictKind` gains `behind`;
  `verdictFor` compares the constraint's lower bound against the
  registry's latest and never suggests a downgrade. Check: a red
  shared-model suite over the new kinds — the trailing caret
  (`^3.1.0` vs 3.1.3), the blocking pin, the exact-latest pin, the
  ahead-of-registry pin, and the bare/`any` entry — with the existing
  unknown/skipped cases green and unmodified.
  Closed (red 54b9147, green f764a79): the bound is read structurally
  through a `_lowerBoundOf` switch over `pub_semver`'s own types, so
  exact pins (`Version.min` returns itself) and hand-written ranges
  need no text re-parsing. Two cases arrived from writing the tests
  rather than the plan: `VersionConstraint.parse` rejects `||`, so a
  union cannot come from pubspec text at all — the union arm survives
  because it is what keeps a union sitting entirely above the
  registry from being rewritten backwards, and it is now exercised
  through the model type's public constructor rather than an
  unreachable parse. Suite: 36 green.
- [x] LV-2 Host surfaces: hover, tree labels, and the smoke report
  carry `behind` (the enum's exhaustive switches force each site);
  diagnostics stay `outdated`-only and the CodeLens follows
  `suggestedConstraint`, so both actionable verdicts get a lens.
  Check: the extension builds and packages; `flutter analyze` clean.
  Closed (f764a79): adding the enum value turned the three surfaces
  that judge a verdict into compile errors and nothing else — the
  diagnostic and CodeLens sites needed no edit, because they were
  already written against "is this outdated" and "is there a
  suggestion" rather than against the enum. The hover now separates
  the two tiers in words ("already allows 1.6.0 — bump to `^1.6.0` to
  require it" versus "excludes the latest release").
- [x] LV-3 Real-host proof: the gate's workspace grows a pin that is
  exactly current (silent) alongside the trailing and blocking pins;
  the driver asserts two lenses (selected by package, not by
  position), exactly one diagnostic, the silent pin's absence from
  both, and applies the *trailing* lens to prove the bump lands.
  Check: `scripts/test_pubspec_lens.sh` exits 0.
  Closed (f764a79): the driver's old lens lookup took the first
  `pubspec-lens.update` lens in document order, which silently
  becomes the wrong lens the moment more than one pin trails — it now
  selects by the lens command's package argument. Both lenses are
  applied in one run, proving the update path is keyed by name rather
  than by a range that the first edit invalidates. Gate exit 0.
  Honest note: the driver's assertions were written against the new
  semantics and verified green; the red for this round lives in
  LV-1's shared suite.
- [x] LV-4 Final bar: docs state the two-tier rule; full fast suite
  and `flutter analyze` green; the pubspec-lens gate green at HEAD.
  Closed: 555 fast tests green (no cli_watch flake this run) with
  `flutter analyze` clean, the shared package's 36 green, and the
  pubspec-lens gate exit 0 on the pinned 1.129.1 host. Both READMEs
  state the two tiers and the no-downgrade guarantee.

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **LV-1** (red 54b9147, green f764a79): the rewritten `verdictFor`
   group landed against the promised end state — trailing caret,
   lower-bound-at-latest, blocking pin, exact-latest pin,
   ahead-of-registry pin, hand-written range, union, and the bare/
   `any` entry — and the suite failed to *load*, since `VerdictKind`
   had no `behind` and a placeholder would have meant shipping the
   new kind before the rule that fills it. Green implemented the
   bound comparison; every case passed except the union, which
   exposed that pubspec text cannot express one. Rewriting that case
   through the public constructor (rather than deleting the arm, which
   would have re-opened the downgrade hazard for a union above the
   registry) took the suite to 36 green.
2. **LV-2** (f764a79): the three exhaustive switches — smoke report,
   hover, tree labels — were the complete list of sites needing the
   new kind, and the analyzer produced it. The diagnostic site
   (`kind != outdated`) and the CodeLens site
   (`suggestedConstraint != null`) compiled unchanged and did the
   right thing, which is the round's one piece of luck: both were
   already written against the question they meant rather than the
   enum they had.
3. **LV-3** (f764a79, gate exit 0): the workspace grew `behind_pkg`
   and moved `current_pkg` to `^1.2.3` so all three hosted verdicts
   are live in one file. The driver's position-based lens lookup was
   a latent defect the old fixture could not surface (one lens only);
   selecting by package argument fixed it. Assertions now pin: four
   dependencies analyzed, `behind` 1, `outdated` 1, `skipped` 1,
   exactly one diagnostic, no lens on the current pin, both trailing
   lenses applied, and a tree that reads all-current afterwards.
4. **LV-4** (2026-07-27): 555 fast tests green with analyze clean,
   36 shared green, gate exit 0. The live report that opened the
   round — `http ^1.5.0` silent against a published 1.6.0 — now
   produces a lens, and a scratch Extension Host repro built during
   diagnosis confirmed the change-event and refresh paths were never
   at fault.
