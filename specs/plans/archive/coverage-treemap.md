# Coverage Treemap Extension Plan

Status: Implemented and verified — valid only while the shared suite and scripts/test_coverage_extension.sh are green at HEAD
Date: 2026-07-23

The first shipped example extension, per the owner's direction: a test
coverage dashboard that parses `lcov.info`, paints per-line coverage
into the editor, and renders an interactive coverage treemap in a
Flutter View. It lives in `extensions/` as a product surface (the
vision: examples are shipped product surfaces) and is deliberately a
consumer of the framework, not a fixture of it. A Dart-only example
extension follows once this one works and ships.

Rules (inherited): the exit bar is frozen; reds are commits;
discoveries go to [`futures.md`](futures.md). Marketplace publication
needs a publisher account and is the owner's call; it is recorded here
as the goal but is not an exit-bar item.

## Guardrails

An extension under `extensions/` must consume the framework the way an
Extension Author would:

- scaffolded and built only with the `flutter_vscode` CLI;
- no imports from the repository's `lib/`, `tool/`, or test fixtures —
  only CLI-generated files and the published package surface
  (`package:flutter_vscode/view.dart` in views);
- when the extension needs something the framework lacks, the gap is
  recorded (futures or a plan) and the framework change lands with its
  own tests first — the extension then consumes it like any author.

## Exit bar

- [x] T-1 The `extensions/` area exists with the guardrails recorded in
  `extensions/README.md`, and the pub archive excludes `extensions/`.
  Check: repository gate suite.
- [x] T-2 A pure-Dart lcov parser in the extension's shared package,
  red-green: `SF`/`DA`/`LF`/`LH` records, per-file line hit maps,
  per-file and per-directory aggregation, and actionable
  `FormatException`s on malformed input. Check: `dart test` in
  `extensions/coverage_treemap/shared`.
- [x] T-3 Host behavior compiled by `flutter_vscode build`: reads
  `coverage/lcov.info` from the first workspace folder via
  `workspace.fs`, decorates covered and uncovered lines in the active
  editor, shows a status-bar coverage percentage, refreshes from a
  `FileSystemWatcher` on the coverage file, and contributes commands
  (show treemap, refresh, toggle line highlights). Check: build green.
- [x] T-4 The treemap Flutter View: a squarified treemap of
  per-directory and per-file coverage, connected over the versioned
  view protocol with a typed coverage-snapshot operation and a refresh
  action (protocol v1 has no host-to-view push; that gap is already
  recorded in futures). Check: build green including the view;
  the shared codec has round-trip tests.
- [x] T-5 `flutter_vscode package` writes an installable
  `coverage-treemap-<version>.vsix`. Check: package green.
- [x] T-6 Real-host proof: a scripted gate installs the packaged VSIX
  into the pinned Extension Host against a workspace with a real
  `lcov.info` and executes a smoke command returning parsed-coverage
  evidence. Check: the script exits 0 with assertions on the returned
  snapshot.
- [x] T-7 Docs: `extensions/README.md` describes the area and each
  extension's build/run/debug story; the root README points at the
  shipped examples. Check: repository gate suite.

## Owner additions (2026-07-23)

Added by owner direction after the original bar froze; the original
items above are unchanged.

- [x] T-8 Coverage runs from inside VS Code: the status-bar item is
  clickable and a `Coverage: Run Tests with Coverage` command runs
  `flutter test --coverage` in a VS Code terminal, so the watcher picks
  up fresh numbers with no external CLI session. The README explains
  that the Dart extension's Testing-UI coverage feeds VS Code's native
  Test Coverage API and never writes `coverage/lcov.info`. Check: gate
  and README.
- [x] T-9 Ecosystem showcase: the view integrates a well-known pub.dev
  package (`fl_chart`) rendering a coverage summary alongside the
  treemap, demonstrating Flutter-ecosystem code reuse inside VS Code.
  Check: build green with the dependency; view analyze-clean.
- [x] T-10 The blank-panel defect observed on desktop VS Code (macOS,
  current release) is root-caused via the T-6 gate: if the view boots
  in the pinned host, the defect is a newer-VS Code regression to
  diagnose against the webview console; either way the root cause and
  fix land before this plan closes. Check: T-6 green plus a recorded
  root cause.

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **Red T-2** (commit 7b0d10c): `extensions/` scaffolded through the
   CLI, pub archive exclusion added, and the shared lcov suite landed
   failing — `parseLcov` did not exist.
2. **Green T-2**: the parser plus the view-contract snapshot codec pass
   13/13 (`dart test` in the shared package): per-file hit maps, LF/LH
   derivation, directory-tree rollups, ignored record kinds, actionable
   `FormatException`s with line numbers, and strict snapshot
   encode/decode round-trips.
3. **Red T-3** (build failures, in order): the descriptor parser
   rejects adjacent-string concatenation (single literal only); the
   host boundary checker scanned `shared/test/` and failed on
   `package:test` — an author-blocking framework gap. The framework fix
   landed red-green in `test/cli_build_test.dart` ("build ignores
   package test directories in the boundary check"): package `test/`
   directories are skipped because they never execute in the Extension
   Host.
4. **Green T-3/T-4/T-5**: `flutter_vscode build` compiles the full
   extension — decorations built via `ThemableDecorationRenderOptions`
   wrapped into `DecorationRenderOptions` (the `lit$` factory does not
   include inherited members; recorded as developer-experience D-2),
   status bar via `createStatusBarItem$2`, watcher, four commands, and
   the squarified-treemap Flutter View connected over the typed
   snapshot operation. `flutter_vscode package` writes
   `coverage-treemap-0.0.1.vsix`. Repo `flutter analyze` clean.
5. **Red T-6/T-10** (commit 18c8538 landed the gate; first runs): the
   real-host gate installed the VSIX into pinned VS Code 1.129.1,
   passed the parsed-snapshot assertions, and failed `viewSmoke` after
   120s — reproducing the blank panel seen on desktop macOS VS Code.
   Rerunning with `--enable-logging` captured the webview console:
   Flutter's engine booted, then died with `SecurityError: Failed to
   execute 'replaceState' on 'History'` — the default web URL strategy
   (exercised by `MaterialApp`'s history integration) writes a
   `vscode-resource` base URL into a `vscode-webview://`-origin
   document. The bare-widget fixture view never touches history, which
   is why five prior gates missed it.
6. **Green T-6/T-8/T-9/T-10**: `setUrlStrategy(null)` before `runApp`
   (plus `flutter_web_plugins`) fixes the boot; the gate passes all
   assertions including the live view-protocol snapshot round-trip in
   a real webview. T-8's clickable status bar runs
   `flutter test --coverage` in a VS Code terminal; T-9 ships
   `fl_chart` 1.2.0 charts over the same snapshot. The README's view
   walkthrough now mandates the URL-strategy line and the D-1 item
   grew a view-side `runFlutterView` boot helper.
7. **Post-close audit and D-1 adoption (2026-07-23)**: a fresh-eyes
   audit found five honesty gaps, all remedied — the T-1/T-7
   "repository gate" checks gained real assertions (pubignore
   exclusion, guardrail prose, no direct framework imports in
   extension host/shared code), `scripts/test_all.sh` now runs the
   extension gate, the driver exercises `runTests` and asserts the
   coverage terminal, and the auto-descend logic moved to a pure
   `drilldown.dart` with a 7-test unit suite. The extension then
   adopted the D-1 framework module: `FlutterViewHost.open` and
   `runFlutterView` replaced the hand-copied transport, HTML, and
   URL-strategy boot code. Both real-host gates re-ran green on the
   result.
