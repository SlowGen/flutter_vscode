# View Protocol (v2)

Each optional Flutter View runs in its own webview runtime. The only
thing that crosses between Host Dart and a View is the version-2
protocol (`lib/src/view_protocol.dart`); view DTOs are protocol-safe
snapshots, never live host objects. Host commands and providers work
when no view exists. Both protocol halves always ship from one build,
so the wire version is 2 wholesale: a frame carrying any other version
fails closed as `unsupported_version` and is never executed or
answered.

## What v2 provides

- Versioned session + nonce handshake: `ready` → `readyAck` carrying a
  newly generated active nonce, installed before it is advertised
  (including on reload) so a synchronous peer cannot lose its first
  valid frame.
- Typed calls in both directions, each against an explicit allowlist.
  View-to-Host `call`/`result`/`error` frames dispatch on the
  operation bindings given to `HostViewSession.connect`; Host-to-View
  `hostCall`/`hostResult`/`hostError` frames dispatch on the bindings
  the view passes to `FlutterViewSession.connect`. Both directions
  return results or structured errors (nine stable codes); every
  frame kind has an exact schema; session and nonce mismatches fail
  closed.
- One-way host events on named streams: `HostViewSession.emitEvent`
  sends an `event` frame, and `FlutterViewSession.events(stream)`
  exposes its payloads as a broadcast stream in delivery order.
- Protocol-level cancellation with per-request disposal:
  `HostViewSession.callWithHandle` returns a `HostViewCall` whose
  `cancel()` completes the caller with the `cancelled` code and sends
  a `cancel` frame; a cancelled request loses response eligibility on
  the receiving side, so a late result or error is discarded
  fail-closed, never delivered. Cancellation drops responses; it does
  not abort a running handler.
- One idempotent terminal cleanup path shared by close, shutdown, peer
  close, stream completion/error, and delivery failure; concurrent
  closes join the same future; measured close reports count live
  requests and subscriptions after awaited cancellation and transport
  shutdown — never constant zeros.
- Delivery honesty: every transport send returns an awaitable; the Host
  adapter awaits VS Code's asynchronous `postMessage` acceptance and a
  `false` acceptance rejects the send; the void Flutter View API
  promises only synchronous handoff.
- Reload truth: stale responses are abandoned by generation; Host
  handler futures stay counted until application settlement.
- Webview safety: CSP with `Webview.cspSource` and a nonce'd script tag,
  private `acquireVsCodeApi` handling, webview-safe asset URLs. A real
  webview adds two requirements. The web URL strategy must be disabled
  before `runApp`: Flutter's default strategy calls
  `history.replaceState` with a `vscode-resource` base inside a
  document whose real origin is `vscode-webview://`, and the resulting
  cross-origin `SecurityError` kills engine startup — so views boot
  through `runFlutterView(app)` from `package:flutter_vscode/view.dart`
  (`lib/src/view_transport_web.dart`). And fonts must be bundled in
  the view's pubspec: Flutter web fetches its default Roboto and Noto
  fallbacks from `fonts.gstatic.com` at runtime, the CSP blocks those
  requests, and missing-glyph frames retry forever.
- Theme bridge: views derive their look from the host theme instead of
  hardcoding one. `parseCssColor` and `VSCodeThemeSnapshot` are pure
  Dart (`lib/src/view_theme_parser.dart`); `readVSCodeTheme`,
  `watchVSCodeTheme` (a `MutationObserver` on the webview body's
  class/style attributes, deduped by snapshot equality), and
  `vsCodeThemeData` (a Material theme with VS Code dark-palette
  fallbacks) are web-side (`lib/src/view_theme_web.dart`). All of it
  is exported via `package:flutter_vscode/view.dart`.
- The view side has one composition seam: `ViewShell`
  (`lib/src/view_shell.dart`, platform pair
  `view_shell_platform_web.dart`/`_stub.dart`) owns session connect,
  a deduplicated shared theme stream, host-event forwards, rendered
  reporting, and a single idempotent `dispose()`; injectable
  session/theme sources make it unit-testable over the in-memory
  transport. `ViewOperation.noArgs`/`noResult` erase the void-codec
  ceremony for operations with no arguments or no result.
- Declare-once codecs: `ViewValueSchema` declares each contract field
  a single time (wire key, `ViewValueKind`, getter) and derives
  encode, decode, and the exact-schema guard — missing, extra, and
  wrong-typed keys throw `FormatException` naming the key; kinds
  compose via `orNull`, `listOf`, and a lazy `nested` reference for
  recursive trees. A view-bearing build emits the verbatim protocol
  copy into `shared/lib/generated/view_protocol.g.dart` and re-exports
  it from the host's `view_protocol.g.dart`, so the shared package
  assembles each `ViewOperation` once for host and view; the view,
  whose session comes from `package:flutter_vscode/view.dart` (a
  distinct generated copy), calls through the structural
  `operationCaller`/`callThrough` function seam.
- Host-side hosting is generated, not hand-copied: view-bearing
  projects receive `flutter_view_host.g.dart`
  (`packages/flutter_vscode/lib/src/cli/flutter_view_host_source.dart`) carrying
  `HostWebviewTransport` and `FlutterViewHost.open` with the
  CSP-correct webview HTML plus its production seams — `extraHead`
  fragments, an optional `scriptNonce` (joined into `script-src` and
  stamped on the bootstrap tag), an `onIncomingMessage` observer
  pass-through, a `loadStartedAt` timestamp for cold-start
  measurement, and `reload()` regenerating same-session HTML under a
  bumped reload-generation meta. The host-extension fixture composes
  this skeleton and keeps only its adversity machinery.

Proven by `test/view_protocol_test.dart` (in-memory pair that
JSON-round-trips payloads), `test/host_webview_transport_test.dart`
(real dart2js/Node seam), the real-host adversarial probes (frames
corrupted before native `postMessage`, unsupported-version frames
injected and never executed, reload with live work, independent render
observation), and the coverage-extension gate, where the host watcher
pushes a fresh snapshot to the open panel and the view applies and
acknowledges it (`scripts/test_coverage_extension.sh`).

## Explicitly deferred (backlog)

Handles and backpressure. CSP *content* is not yet gate-asserted (only
that `cspSource` is exercised).
