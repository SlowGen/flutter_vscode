# Pubspec Lens Plan

Status: Implemented and verified — valid only while the fast suites
and the four real-host gates are green at HEAD
Date: 2026-07-26

The second shipped example extension and the first Host-Only
Extension: dependency intelligence for `pubspec.yaml`, built without a
Flutter View to demonstrate that VS Code's native UI surface — hovers,
diagnostics, CodeLens, QuickPick, tree views, the status bar — is
fully drivable from plain Dart (ADR 0003 made tangible). The host-side
reuse story mirrors the treemap's fl_chart: `pub_semver` and `yaml`,
both Dart-team packages, do the real semantics.

First-cut scope by owner direction: hover, outdated-pin diagnostics,
a CodeLens update via WorkspaceEdit, and a dependencies tree view.
Completion and add-dependency wait until the first cut earns them.

Rules (inherited): exit bar frozen; reds are commits; the extension
consumes the framework only through the CLI and generated files (the
extensions/ guardrails); discoveries to [`futures.md`](futures.md).

## Exit bar

- [x] PL-1 Pure-Dart analysis in the shared package: parse
  `pubspec.yaml` (via `yaml`) into dependency models with source
  spans; compare pinned constraints against registry versions (via
  `pub_semver`) into per-dependency verdicts (current, outdated with
  the suggested `^latest`, unknown); actionable `FormatException`s on
  malformed input. Check: a red unit suite in the extension's shared
  package covering constraints, spans, verdicts, and malformed input.
  Closed: `parsePubspec` models hosted/sdk/path/git entries with
  zero-based name and constraint spans, `verdictFor` yields
  current/outdated/unknown/skipped (non-hosted dependencies are
  skipped by design), and `parsePackageInfo` reads the pub API's
  `{"latest": {"version": ..., "pubspec": ...}}` shape — 24/24 in the
  shared suite.
- [x] PL-2 Registry client over `hostFetch`: fetch package metadata
  from the pub.dev API with the base URL read from workspace
  configuration (so gates point it at a local fake registry), an
  in-memory cache, and graceful offline degradation (no diagnostics
  churn on network failure). Check: pure parts unit-tested; the live
  path proven in the PL-4 gate. Closed: `packageInfoUrl` and
  `RegistryCache` live in the shared package (29/29 with PL-1);
  `RegistryClient` in `host/lib/registry_client.dart` rides the
  generated `hostFetch` with the documented degradation contract —
  any failure returns null uncached, so verdicts fall back to
  unknown and refresh retries.
- [x] PL-3 Host features on the native UI surface, via the generated
  layer and `ExtensionCommands`: hover on a dependency shows the
  latest version and description; outdated pins get diagnostics; a
  CodeLens per outdated dependency applies the `^latest` constraint
  through a `WorkspaceEdit`; a dependencies tree view lists direct
  dependencies with their verdicts; a refresh command re-queries.
  Check: the extension builds and packages through the CLI alone.
  Closed: one controller (treemap pattern) registers everything on
  activate — a `pubspec-lens` DiagnosticCollection (severity
  Information by design: a newer release is ecosystem advice, not a
  file defect), yaml hover/CodeLens providers, the tree data
  provider with an EventEmitter refresh, and three
  `ExtensionCommands` (refresh/update/smoke). Analysis triggers:
  activation reads the workspace root's pubspec (open buffers
  preferred over `workspace.fs`), and every open/change of a
  pubspec.yaml re-analyzes; runs serialize on one chain so an older
  registry answer can never clobber a newer one. `flutter_vscode
  build` and `package` pass.
- [x] PL-4 Real-host gate: `scripts/test_pubspec_lens.sh` (mirroring
  the coverage-extension gate) installs the packaged VSIX into the
  pinned Extension Host against a workspace whose `pubspec.yaml` has
  known-current and known-outdated pins, serves a fake pub.dev from
  the driver, and asserts the hover content, the diagnostics, the
  CodeLens edit actually rewriting the document, and the tree
  children. Wired into `test_all.sh` with the repository-gate
  assertion updated. Check: the gate exits 0. Closed: the driver
  solves the port problem inside the host — it starts the fake
  registry on an ephemeral port, then writes
  `pubspecLens.registryUrl` through the configuration API; the
  driver's own package.json contributes that setting (the API
  rejects unregistered keys) and the `pubspecLens.dependencies`
  view (manifest contribution gaps recorded in futures). Proven by
  local non-Docker runner runs on macOS against pinned VS Code
  1.129.1: red at "command 'pubspec-lens.refresh' not found" before
  PL-3, then exit 0 with every assertion — smoke counts, hover with
  the fake latest and description, the Information diagnostic, the
  CodeLens `WorkspaceEdit` rewriting the pin to `^2.0.0`, and the
  post-edit tree flipping old_pkg to current. The Docker path runs
  in the aggregate gate at PL-5 close.
- [x] PL-5 Docs and closure: `extensions/README.md` gains the
  Pubspec Lens section (with the native-UI-vs-Flutter-View dividing
  line stated); the root README's examples section mentions both
  examples; futures' "Dart-only sibling" clause retires (the
  framework-external extension remains). Final bar: fast suites +
  analyze green; the pubspec-lens gate plus the existing three
  real-host gates green at HEAD.

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **Red PL-1** (commit 7c52b3d): `extensions/pubspec_lens` scaffolded
   through the CLI and shaped as the first Host-Only Extension —
   typed descriptor targeting 1.129.1, empty `views/` root, shared
   package depending on `yaml` and `pub_semver`. The shared suite
   landed failing: `parsePubspec`, `verdictFor`, and
   `parsePackageInfo` did not exist.
2. **Green PL-1**: 24/24 in the shared package (`dart test`): hosted
   constraints (caret, exact, bare-any, unparsable-stays-unknown),
   sdk/path/git classification, hosted-map `version:` support,
   zero-based name/constraint spans sized for text edits, actionable
   `FormatException`s (invalid YAML with position, non-map root,
   non-map section), verdict semantics (a pin admitting latest is
   current; outside the pin is outdated with `^latest`), and the pub
   API response model with tolerated missing descriptions. `dart
   analyze` clean.
3. **Red PL-2** (commit c20c6ff): the shared suite demanded
   `packageInfoUrl` (pub API path, trailing-slash tolerance,
   local-registry bases) and the `RegistryCache` store/miss/clear
   contract; neither existed.
4. **Green PL-2**: 29/29 in the shared package. The host-side
   `RegistryClient` composes the pure parts over the generated
   `hostFetch` seam with the degradation contract documented on the
   class: failures return null and cache nothing (offline keeps
   verdicts unknown, no churn), successes stay cached until the
   refresh command clears them. Both extension packages analyze
   clean; the network path itself is deferred to the PL-4 gate by
   design.
5. **Red PL-4** (commit dca0fb1): the complete gate landed before the
   features — driver fixture, runner, `scripts/test_pubspec_lens.sh`,
   `test_all.sh` wiring, and the repository-gate assertion. Red
   proven by the fast route (a local non-Docker runner run on macOS,
   `TMPDIR=/tmp`, pinned VS Code 1.129.1): the VSIX installed, the
   extension activated, the registry-URL write was accepted, and the
   run failed at "command 'pubspec-lens.refresh' not found".
6. **Green PL-3/PL-4**: the controller registers the whole native UI
   surface as ordinary Dart — DiagnosticCollection, hover and
   CodeLens providers on yaml, the tree data provider with
   EventEmitter refresh, and refresh/update/smoke through
   `ExtensionCommands`; `flutter_vscode build` and `package` pass
   through the CLI alone. The local runner then exited 0 with every
   assertion green on the first full run, including the CodeLens
   `WorkspaceEdit` rewriting `old_pkg: ^0.9.0` to `^2.0.0` in a real
   buffer and the follow-up smoke reporting zero outdated pins. At
   recording time: shared suite 29/29, root `flutter test` 555/555
   (repository gate and plan truth included), root `flutter analyze`
   clean after nested pub gets.
7. **PL-5** (2026-07-26): extensions/README gained the Pubspec Lens
   section with the native-UI-vs-Flutter-View dividing line, the root
   README describes both examples, and futures' Dart-only clause
   retired. Final bar: 554 fast tests green (plus the known cli_watch
   contention flake, green standalone) with analyze clean, and all
   four real-host gates exited 0 at HEAD — the pubspec-lens gate's
   first Docker run passed every assertion (hover with the fake
   registry's latest, the Information diagnostic, the CodeLens
   WorkspaceEdit, the tree children) alongside the host fixture,
   coverage extension, and breakpoint gates.
