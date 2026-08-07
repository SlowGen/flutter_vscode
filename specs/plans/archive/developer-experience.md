# Developer Experience Plan

Status: Implemented and verified — valid only while the fast suites
and the real-host gates are green at HEAD; every D-item is closed
Date: 2026-07-23

Captures the framework-compelling/dev-friendly direction agreed with
the owner, plus the gaps that building the first real extension
(Coverage Treemap) surfaced within hours of real usage. Each item
graduates here from [`futures.md`](futures.md) or from a build
discovery; when a round opens, its items freeze into that round's exit
bar with the usual rules (reds are commits, machine-checked closure).

## Queue

- [x] D-1 One-call Flutter View hosting (closed; both real-host gates
  green on the module)
- [x] D-2 Mechanical ergonomics layer over the Parity Layer
- [x] D-3 The dev loop: watch, reload, breakpoints
- [x] D-4 View protocol v2: push, streams, cancellation
- [x] D-5 Theme bridge (closed; the real-host toggle proof remains
  for the gate follow-up)
- [x] D-6 Startup honesty
- [x] D-7 `doctor` and `test` commands
- [x] D-8 Multi-baseline support (closed; 1.129.1 and 1.130.0 pinned)
- [x] D-9 Nested-package analysis honesty
- [x] D-10 Host network story

## D-1 One-call Flutter View hosting

The single biggest authoring gap: opening a view today takes ~80
author-owned lines (panel + hand-copied webview transport + session +
hand-rolled CSP HTML). Graduate the host-side webview transport out of
the test fixture into the framework and ship a `FlutterViewHost`-style
API: one call takes a view name and operation bindings, and owns panel
creation, resource roots, session identifiers, CSP-correct HTML, and
disposal. Coverage Treemap's `host_webview_transport.dart` +
`_viewHtml` are the reference implementation to delete. The view side
gets a matching `runFlutterView(app)` boot helper that disables the
web URL strategy before `runApp` (discovered shipping Coverage
Treemap: `MaterialApp`'s history integration throws a cross-origin
`SecurityError` in webviews and the engine never renders a frame) and
connects the session.
Check: the extension and the host fixture both consume the framework
module; the copies are gone.

D-1 round exit bar:

- [x] D-1a `build` emits `host/lib/generated/flutter_view_host.g.dart`
  (transport + `FlutterViewHost.open` + CSP HTML) for view-bearing
  projects only, byte-equal to the framework template. Check:
  cli_build_test.
- [x] D-1b The host fixture consumes the emitted module; its local
  transport copy is deleted. Check: `./scripts/test_host_extension.sh`.
- [x] D-1c Coverage Treemap consumes `FlutterViewHost.open`; its
  transport and HTML copies are deleted. Check:
  `./scripts/test_coverage_extension.sh`.
- [x] D-1d `runFlutterView(app)` ships in
  `package:flutter_vscode/view.dart` (URL strategy + runApp); the
  extension's view uses it. Check: view analyze + the same gates.
- [x] D-1e The README's Flutter View walkthrough is rewritten on the
  new APIs. Check: prose matches the shipped surface.

## D-2 Mechanical ergonomics layer over the Parity Layer

Not the reviewed Idiomatic Facade — a second *generated, total,
judgment-free* rule set that layers Dart-first types over the parity
surface: ordinary `String`/`int`/`bool` at every boundary, `Future<T>`
from `JSPromise<T>`, `Stream<T>` from `Event<T>`, named optional
parameters from options interfaces, and `lit$` factories that include
inherited interface members (discovered building Coverage Treemap:
`DecorationRenderOptions.lit$` cannot set `backgroundColor` because it
lives on the superinterface), plus the parity-runtime post-close audit
find: an all-string-literal alias must name its wrapper after the
alias instead of erasing to `JSString` beside a hash-named wrapper. Kills most `.toJS` noise while keeping
the zero-judgment guarantee; the hand-reviewed facade remains a later,
separate product for the places that need taste.
Check: emitter unit cases per new rule; the extension's host rewritten
on the layer with a large measured drop in interop noise.

D-2 round exit bar:

- [x] D-2a The mechanical layer ships (red c66d70c), generated from
  the same pinned IR as the parity layer into
  `lib/src/generated/vscode_dart_layer.g.dart` (exported as
  `package:flutter_vscode/vscode_dart.dart`, regenerated via
  `generate.dart --dart-layer .`): boundary de-JS on helper scalars,
  `Future` from `JSPromise`, broadcast `onDidXStream` accessors gained
  beside `Event` members (additive, not redeclared — a Stream getter
  beside an inherited Event setter is illegal at the package language
  level, and provider objects still take raw Events), `lit$` factories
  flattened across the declared hierarchy (`DecorationRenderOptions`
  gains `backgroundColor`), the alias-named literal wrapper landed in
  the parity emitter (ledger entry 6 closed; zero baseline
  occurrences, parity bytes unchanged), and a full totality ledger
  (2,982 dispositions: 741 emitted, 2,229 passthrough-identical, 12
  carried parity erasures, zero dart-layer erasures). Check: the
  dart-layer emitter unit suite; byte-compare regeneration, ledger
  totality, and `--fatal-infos` analysis in the dart-layer suite.
- [x] D-2b `build` emits `host/lib/generated/vscode_dart_layer.g.dart`
  beside the parity layer from the same pinned inputs, byte-stable
  across identical builds and within the Host Dart import boundary
  (red 9715d58). Check: cli_build_test.
- [x] D-2c Coverage Treemap's host adopted the layer: the flattened
  `DecorationRenderOptionsDart.lit$` replaces the wrap-and-cascade
  (with `backgroundColor` and `isWholeLine` in one call), watcher and
  active-editor events are Dart `Stream`s with `StreamSubscription`
  lifecycle instead of `.toJS` listener plumbing, `readFile` awaits a
  `Future`, `showErrorMessage` and ctor helpers take ordinary
  `String`/`num`. Interop-noise tokens (`.toJS`/`.toDart`/JS types)
  dropped 42 → 30 (−29%); the remainder is genuine boundary work
  (command callbacks, jsonEncode results, snapshot codecs). Check:
  both real-host gates green on the rewritten host. The plan's
  original "named optional parameters from options interfaces" idea
  shipped as the flattened `lit$` factories; a broader
  options-to-named-parameters rewrite graduates to futures with the
  Idiomatic Facade.

## D-3 The dev loop: watch, reload, breakpoints

`flutter_vscode build --watch` plus automatic Extension Development
Host reload, and a gated proof that F5 breakpoints bind to Dart source
lines through the emitted source maps (graduates the deferred
breakpoint/source-map hardening item). Edit-rebuild-restart is the
difference between a demo and a daily tool.
Check: a scripted gate sets a breakpoint via the debug adapter in the
pinned host and observes a stop on a Dart line.

Closed in three parts. (a) `build --watch` rebuilds on host/shared/
view source changes with debounced, self-trigger-proof scheduling
(red dd0a200). (b) Development-mode hosts watch the emitted bundle
and reload the window when it changes (red 901737e). (c)
`scripts/test_breakpoints.sh` proves breakpoints bind to Dart source
lines through the emitted source maps in the pinned host
(red 6f337f4): the driver hand-decodes the fixture's source map
(base64 VLQ, no npm deps), locates the openEventCount command
callback line by content, and an out-of-process inspector client
arms every mapped generated position over `--inspect-extensions`;
executing the command pauses the Extension Host on a location that
maps back to the same Dart line, then resumes it.

## D-4 View protocol v2: push, streams, cancellation

Graduates the protocol futures item, now with a concrete requirement:
Coverage Treemap's host cannot tell its view that coverage changed —
the view must poll or the user must click Refresh. Add host-to-view
requests/events (streams), protocol-level cancellation, and
per-request disposal, versioned alongside v1.
Check: protocol suite plus the extension's watcher pushing a fresh
snapshot to an open panel in the real-host gate.

Closed: the protocol gains hostCall/hostResult/hostError frames with
typed view-bound operations, one-way host events on named streams,
and cancellation with per-request disposal on both directions; the
wire version is 2 wholesale (both halves always ship from one build;
mixed generations fail closed as unsupported_version, and
stale-version frames are ignored, never executed, never answered —
red ff8e9ea, spec correction 158c652). Proven three ways: 67-test
protocol suite over the in-memory pair; Coverage Treemap's watcher
pushing a fresh snapshot to the open panel in the real-host gate,
with the view applying and acknowledging it; the host fixture's
adversity probes re-running green on v2 (the unsupported-version
probe now speaks 3).

## D-5 Theme bridge

Generate a Flutter theme from VS Code's webview CSS variables so views
look native in dark/light/high-contrast without hand-tuning (Coverage
Treemap hardcodes a dark palette today).
Check: the view renders with host-derived colors in the real-host
gate; toggling the host theme changes the view.

Closed: `parseCssColor`, `VSCodeThemeKind` (high contrast before
dark), and `VSCodeThemeSnapshot` ship as pure Dart through
`package:flutter_vscode/view.dart`; `readVSCodeTheme`,
`watchVSCodeTheme` (a MutationObserver on the body class/style,
deduped by snapshot equality), and `vsCodeThemeData` ship web-side
with dark fallbacks (red c9339a1). Coverage Treemap's view drops its
hardcoded dark chrome for the derived theme — the red-amber-green
coverage ramp stays fixed as data encoding — and reports its resolved
theme through the new `coverageTreemap.reportTheme` operation;
`coverage-treemap.themeSmoke` returns the last stored report as JSON.
The live toggle proof in the real-host gate remains for the gate
follow-up; themeSmoke is its hook.

## D-6 Startup honesty

Measure webview cold-start for a minimal Flutter View in the pinned
host (wall-clock to first frame), publish the number in docs, and
evaluate wasm/deferred loading against it. Flutter-web weight is the
first objection every evaluator raises; meet it with data.
Check: the measurement runs in a gate and the doc cites its output.

Closed: both real-host gates measure webview-load-to-first-rendered-
frame via the fixture's render observer, assert sanity, and print the
number; `docs/reference/startup.md` defines the span and records
284ms (dev flow) / 315ms (installed VSIX) on the pinned host
(red 80defa9). Wasm/deferred-loading evaluation stays deferred until
a real extension regresses the number.

## D-7 `doctor` and `test` commands

Graduates the product-workflow futures item (minus `upgrade`, which
depends on D-8): `doctor` validates the toolchain and project layout
with actionable errors; `test` gives Extension Authors a first-class
way to run shared/host suites (the boundary checker now skips package
`test/` directories — shipped during the Coverage Treemap round).
Check: CLI tests for both commands; quickstart documents the flow.

Closed: `doctor` checks the Dart and Flutter toolchains, project
layout existence and safety, the descriptor, and pinned-input
availability for the API target, with `[ok]`/`[!!]` lines and exit
codes (red 038b416); `test` discovers and runs `shared/test`,
`host/test`, and per-view suites, aggregating failures. Five CLI
tests cover healthy, broken-layout, outside-project, failing-suite,
and no-suite flows; the quickstart documents both.

## D-8 Multi-baseline support

The machinery to *add* a pinned VS Code release rather than replace
it: N pinned IRs, `apiTarget` selecting among them, and a documented
procedure for onboarding a new release. "Supported releases, plural"
is the difference between a demo and a dependency, and unlocks a real
`upgrade` story.
Check: two baselines in-tree; a fixture builds against each.

D-8 round exit bar:

- [x] D-8a A second pinned stable VS Code baseline ships in-tree
  beside the 1.129.1 seed: pinned inputs with verified checksums,
  imported IR, and a same-version Semantic Override file, with no
  orphaned IR or override files. Check: cli_multi_baseline_test
  structural case; the importer baseline series gate.
- [x] D-8b `build` resolves binding inputs by enumerating the pinned
  baselines and rejects an unknown `apiTarget` with an actionable
  error naming every shipped target. Check: cli_multi_baseline_test.
- [x] D-8c A scaffolded Extension Project builds against each pinned
  baseline — walking-slice facade, runtime, and Complete Parity Layer
  included — selected only by its descriptor `apiTarget`. Check:
  cli_multi_baseline_test.
- [x] D-8d `docs/guides/new-baseline.md` documents the onboarding
  procedure actually used for the second baseline. Check:
  cli_multi_baseline_test doc case.

Closed in four parts (reds 5fe437e, 6f105f2, f2f1c08, 30b6853).
(a) VS Code 1.130.0 — the newest stable after the seed — is pinned
beside 1.129.1 by the seed mechanism: the six official inputs fetched
at tag commit 1b6a188, checksummed into pins.json, imported into
canonical IR with the pinned parser, and classified by a same-version
Semantic Override file. The public API delta was empty — vscode.d.ts
and the schema/validator inputs were byte-identical and only the
transitive strings.ts helper changed outside the extracted validation
projection — so the seed's reviewed classifications carried over
unchanged and the Complete Parity Layer emitted with no new Total
Mapping Rule. (b) apiTarget selection enumerates the pinned baselines
(inputs + IR + overrides all present) and the unknown-target error
names every shipped target; the contract writer repins every
baseline's overrides. (c) cli_multi_baseline_test builds a scaffolded
project against each pinned baseline with the engine floor following
the selected target. (d) docs/guides/new-baseline.md records the
procedure as executed.

## D-9 Nested-package analysis honesty

Discovered during the view build: the root `analysis_options.yaml`'s
`very_good_analysis` include silently fails to resolve for nested
packages (it is only a dev dependency of the root), so `dart analyze`
in `extensions/*`, fixtures, and view packages does not actually
enforce the strict lint set. Make the gates mean what they say
(per-package options, a shared include that resolves, or a repo check
that proves the lint set is active).
Check: a deliberately violating probe file fails analysis in a nested
package.

Closed: every nested package (extensions and fixtures, host/shared/
views) carries `analysis_options.yaml` including the strict set plus a
`very_good_analysis` dev dependency; `test/nested_analysis_test.dart`
enforces the wiring structurally and proves activation with a
violating probe that must fail standalone `dart analyze`
(red c659677).

## D-10 Host network story

Host Dart has no HTTP client: Node's `fetch` is reachable but unbound.
Decide and ship the supported path (a total-rule binding or a runtime
helper), unblocking the pub.dev-explorer class of extensions.
Check: a fixture host performs a real request in the packaged gate
against a local server.

Closed: the generated runtime ships `hostFetch` — Node's WHATWG
`fetch` bound with method/headers/body support, returning a
protocol-safe status+body snapshot (red d0e5332). Proven two ways: a
compiled-probe unit test round-trips against a local Node server, and
the packaged gate's driver serves HTTP from inside VS Code while the
installed fixture's `hostFetchProbe` command fetches it live.
