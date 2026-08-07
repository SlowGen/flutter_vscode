# V0 Removal Plan

Status: Implemented and verified — valid only while the absence gate,
the fast suites, and the real-host gates are green at HEAD
Date: 2026-07-25

Deletes the legacy v0 pipeline, per the owner's directive: we build on
a branch and carry no legacy surface. The docs died in the docs-truth
round; this round deletes the code so reality matches the docs.

Rules (inherited): exit bar frozen; reds are commits; discoveries to
[`futures.md`](futures.md).

## Exit bar

- [x] V0-1 The v0 pipeline is gone: `bin/generate_vscode_extension.dart`,
  the annotation/builder surface in `lib/` (annotations, builder,
  flutter_vscode, runtime, vscode, vscode_codegen_helpers,
  vscode_controller_base, vscode_generator, vscode_ts_generator,
  vscode_validation, vscode_webview_helper, webview_bridge*),
  `build.yaml`, `example/`, and `tool/legacy-agent-skills/` are
  deleted; pubspec drops the executable and every dependency only the
  v0 pipeline used (build, source_gen, build_runner, build_test —
  verified unused by v1 before dropping). Check: an absence gate in
  the repository suite; `flutter analyze` clean.
  Closed (red b134e29, green 12a60e2): `test/v0_removal_test.dart`
  landed red with all six absence cases failing; the deletion (57
  tracked files, 5,928 lines) made them green. Dependency
  verification before dropping: a repo grep found `package:build`,
  `package:source_gen`, `package:build_runner`, and
  `package:build_test` imported only by v0 sources (`lib/builder.dart`,
  the three v0 generator modules, `tool/check_*_generator.dart`,
  `tool/build_test_support.dart`), so all four dropped without a
  carve-out; `flutter_web_plugins` stays because the v1
  `lib/src/view_transport_web.dart` imports it. The one v1 reference
  into the deleted surface — `resolvePackageRoot` in
  `lib/src/cli/baselines.dart` probing
  `package:flutter_vscode/flutter_vscode.dart` — retargeted to the
  live `vscode_dart.dart` export at the same depth. The receipted
  `pubspec.yaml`, root `pubspec.lock`, and fixture-view
  `pubspec.lock` changes rotated the contract chain:
  `generate.dart --contract` converged on the second pass and
  `build_host_fixture.sh` rebuilt the fixture, updating only
  `coverage.json`'s contract `artifactSha256` pin. `flutter analyze`
  clean at recording time.
- [x] V0-2 The test and gate surface follows its subject:
  generate_vscode_extension_test, vscode_controller_base_test,
  webview_bridge_test, and the tool/check_*_generator checks retire
  with the code they tested (none of their assertions guard v1
  behavior — verified before deletion); `scripts/test_all.sh` drops
  the build_runner smoke, generator checks, and example steps;
  repository_gate_test's legacy-label pins (example/README routing,
  PRD historical label, example main.dart label) retire with their
  subjects; PRD.md (the v0-era product document, already unlinked)
  is deleted. Check: full fast suite green; test_all.sh's remaining
  steps enumerated in the plan note.
  Closed (red b134e29, green 12a60e2). Retirement verdicts, read
  before deletion: `generate_vscode_extension_test` (2 cases)
  asserted only the v0 scaffolder's output tree and legacy skills —
  v1 scaffolding stays pinned by `cli_create_test`;
  `vscode_controller_base_test` (6) exercised the v0
  request/response runtime whose v1 replacement is covered by the
  view-protocol and `host_webview_transport` suites;
  `webview_bridge_test` (1) was a stub smoke; `vscode_test` (3)
  drove `VSCode.instance.invoke` over that same v0 runtime;
  `vscode_codegen_helpers_test` (5) pinned v0 builder string
  emission; `flutter_vscode_test` (3) pinned v0 annotation
  existence; `tool/check_dart_generator.dart` and
  `tool/check_ts_generator.dart` were build_test integration checks
  of the v0 builders, and `tool/build_test_support.dart` was
  imported only by those two. None guarded v1 behavior; all retired.
  `scripts/test_all.sh` remaining steps: (1) `flutter pub get`,
  (2) `flutter test`, (3) `./scripts/test_binding_importer.sh`,
  (4) `./scripts/test_host_extension.sh`,
  (5) `./scripts/test_packaged_extension.sh`,
  (6) `./scripts/test_coverage_extension.sh`.
  repository_gate_test retires the whole legacy-label test — its
  PRD/example pins died with their subjects and its `bin/init.dart`
  absence pin moved into the absence gate — plus the
  `.pubignore` legacy-skills assertion; the three dead `/tool/`
  ignore entries dropped. `check_round5_exit.sh` R5-10 (shipped-
  surface honesty) now verifies deletion via the absence gate
  instead of labels, a strengthening of its frozen "labeled or
  gone" bar. Full fast suite green: 519 tests (534 before the
  round; 21 cases retired with their subjects, 6 absence gates
  added).
- [x] V0-3 Final bar: full fast suite + analyze green; the three
  real-host gates green at HEAD; `.pubignore`/receipts carry no dead
  entries; a repo-wide sweep finds zero references to the deleted
  surfaces outside archives and history.

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **V0-1/V0-2** (red b134e29, green 12a60e2): the six-case absence
   gate `test/v0_removal_test.dart` landed red against the promised
   end state — v0 entry points, directories, and `lib/` sources
   absent; pubspec free of the executable and the four v0-only
   dependencies; v0 test suites and generator checks gone; no v0
   step in `test_all.sh`; no dead `.pubignore` entries — and failed
   all six cases. Green: 57 tracked files (5,928 lines) deleted;
   `baselines.dart` retargeted its package probe; the contract chain
   (contract artifact, both override pins, fixture `coverage.json`)
   regenerated to convergence; the full fast suite is 519 tests
   green (down from 534: 21 cases retired with their subjects, 6
   gates added) and `flutter analyze` is clean. The heavy real-host
   gates remain V0-3's exit evidence.
2. **V0-3** (2026-07-25): full fast suite 519 green and analyze clean
   at HEAD; all four real-host gates exited 0 on the v0-free tree
   (host fixture, packaged install, coverage extension, breakpoints).
   One environmental note, per the round's caution: stray generated
   pub state regrew an empty `example/.dart_tool` skeleton once after
   a root `pub get`; only generated files, removed, absence gate
   green since.
