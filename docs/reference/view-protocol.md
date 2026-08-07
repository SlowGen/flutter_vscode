# Flutter View Protocol

The version-2 view protocol is the only thing that crosses between
Host Dart and a Flutter View: a small set of exact-schema frames
carried over the webview message channel. This page is the wire
contract for Extension Authors — what `FlutterViewHost.open` binds on
the host side, what `ViewShell.connect` speaks from the view side, and
how every frame fails closed. The implementation is
[`lib/src/view_protocol.dart`](../../lib/src/view_protocol.dart); the
design and its verifying gates live in the
[architecture capture](../../specs/architecture/view-protocol.md).

## Where authors meet the protocol

Authors compose sessions, not frames. On the host side, view-bearing
projects receive the generated `flutter_view_host.g.dart` Framework
Module: `FlutterViewHost.open` creates the webview panel, generates
the session and bootstrap identifiers, connects a `HostViewSession`,
and closes everything when the user closes the panel. Its
`operations` argument is the host's allowlist — the only operations a
view may call:

```dart
_viewHost = FlutterViewHost.open(
  context: _context,
  vscode: _vscode,
  viewName: 'treemap_panel',
  viewType: 'coverageTreemap.panel',
  title: 'Coverage Treemap',
  onClosed: () => _viewHost = null,
  operations: [
    _themeReportOperation.bind((report) {
      _lastThemeReport = report;
    }),
  ],
);
```

On the view side, `ViewShell.connect` from
`package:flutter_vscode/view.dart` connects a `FlutterViewSession`,
owns the live theme stream and every protocol subscription, and
releases them all in one `dispose()`. Its `operations` argument is the
view's allowlist for host-initiated calls:

```dart
Future<void> main() async {
  final shell = await ViewShell.connect();
  runFlutterView(TreemapApp(shell: shell));
}
```

Both snippets are trimmed from the shipped
[`coverage_treemap`](../../extensions/coverage_treemap/host/lib/extension.dart)
extension, which exercises every surface on this page.

## The envelope

Every frame is a string-keyed map with the same five envelope keys —
`protocol`, `version`, `kind`, `session`, `nonce` — plus the exact
payload keys of its kind. A `call` frame on the wire:

```json
{
  "protocol": "flutter-vscode.view",
  "version": 2,
  "kind": "call",
  "session": "1f6c…",
  "nonce": "8d02…",
  "id": "request-1",
  "operation": "coverageTreemap.getSnapshot",
  "arguments": null
}
```

`protocol` is always `flutter-vscode.view` and `version` is always
`2`. There is no negotiation: both protocol halves ship from one
build, so a frame carrying any other version fails closed as
`unsupported_version` and is never executed or answered. `session`
names the session — the host generates it and stamps it into the
view's HTML as `flutter-vscode-session` metadata — and `nonce` names
the session phase: the bootstrap nonce during the handshake, the
active nonce after it.

Every payload value — arguments, results, event payloads, rendered
values, error details — must be a protocol-safe snapshot: `null`,
booleans, strings, finite numbers, lists of snapshots, and
string-keyed maps of snapshots, with no cycles. Live host objects
never cross; codecs turn typed values into snapshots and back.

### Frame kinds

| Kind | Direction | Payload keys |
| --- | --- | --- |
| `ready` | View to Host | none |
| `readyAck` | Host to View | `activeNonce` |
| `call` | View to Host | `id`, `operation`, `arguments` |
| `result` | Host to View | `id`, `result` |
| `error` | Host to View | `id`, `error` |
| `hostCall` | Host to View | `id`, `operation`, `arguments` |
| `hostResult` | View to Host | `id`, `result` |
| `hostError` | View to Host | `id`, `error` |
| `cancel` | Initiator to peer | `id` |
| `rendered` | View to Host | `value` |
| `event` | Host to View | `stream`, `payload` |
| `shutdown` | Host to View | none |
| `closing` | Either | `report` |

## Handshake

The view opens the session: `FlutterViewSession.connect` (inside
`ViewShell.connect`) sends `ready` carrying the bootstrap nonce its
document was stamped with. Host Dart accepts with `readyAck`, which
carries a freshly generated `activeNonce`; every subsequent frame of
the phase must carry that active nonce. `ViewShell.connect` returns
only after the acknowledgement arrives, and `HostViewSession.ready`
completes on the host — until then, host calls and events fail with
`session_closed`. A webview reload replays `ready` on the same
bootstrap nonce: the host rotates the active nonce and abandons
responses that belong to the previous generation.

## Typed operations

A `ViewOperation<Request, Result>` names one operation and carries
four deterministic codecs — encode and decode for the arguments and
for the result. The name is matched against the receiving side's
explicit allowlist; there is no reflection and no generic dispatcher.
`ViewOperation.noArgs` and `ViewOperation.noResult` supply the void
codec pair for the request or result side, replacing the
encode-null/decode-guard ceremony every acknowledgement-style
operation otherwise repeats.

Contract types declare their wire shape once with a `ViewValueSchema`:
each field is declared a single time — wire key, `ViewValueKind`,
getter — and the schema derives `encode`, `decode`, and the
exact-schema guard (missing, extra, and wrong-typed keys throw
`FormatException` naming the key). Kinds compose through `orNull`,
`listOf`, and a lazily referenced `nested` schema for recursive
trees; scalar kinds double as bare payload codecs:

```dart
final ViewValueSchema<CoverageSnapshot> coverageSnapshotSchema =
    ViewValueSchema((field) {
  final lcovPath = field(
    'lcovPath',
    ViewValueKind.string,
    (CoverageSnapshot snapshot) => snapshot.lcovPath,
  );
  final root = field(
    'root',
    ViewValueKind.nested(() => coverageNodeSchema),
    (snapshot) => snapshot.root,
  );
  return (fields) =>
      CoverageSnapshot(lcovPath: lcovPath(fields), root: root(fields));
});

final ViewOperation<void, CoverageSnapshot> snapshotOperation =
    ViewOperation.noArgs(
  coverageSnapshotOperationName,
  encodeResult: coverageSnapshotSchema.encode,
  decodeResult: coverageSnapshotSchema.decode,
);
```

Assembled operations live in the project's shared package, whose
generated `view_protocol.g.dart` copy the host module re-exports, so
host and view import one declaration. On the view side, where the
session comes from `package:flutter_vscode/view.dart` (a different
generated copy of the protocol), calls ride the structural seam:
`operation.callThrough(shell.session.operationCaller, arguments)` —
a plain function type, so no nominal session type crosses the copies.

Calls run in both directions, typed end to end:

- **View to Host** — `operation.call(shell.session, arguments)` sends
  a `call` frame; the bound host handler runs and Host Dart answers
  `result` or `error`:

  ```dart
  final snapshot = await snapshotOperation.call(shell.session, null);
  ```

- **Host to View** — `viewHost.session.call(operation, arguments)`
  sends `hostCall` against the bindings the view passed to
  `ViewShell.connect`; the view answers `hostResult` or `hostError`.

A failed handler crosses as a structured error — `code`, `message`,
`details` — and surfaces to the caller as a `ViewProtocolException`
with one of the nine stable codes below. Request IDs are
session-unique: a reused ID is answered `duplicate_request`, and an
unbound operation name `operation_not_allowed`.

## Host events

`HostViewSession.emitEvent(stream, payload)` pushes one `event` frame
on a named stream — one-way, with no response frame:

```dart
await viewHost.session.emitEvent(
  snapshotPushStreamName,
  coverageSnapshotSchema.encode(snapshot),
);
```

The view listens through `ViewShell.events(stream)` (a forward of
`FlutterViewSession.events` that ends when the shell disposes), which
delivers payloads as a broadcast stream in delivery order:

```dart
shell.events(snapshotPushStreamName).listen(_applyPushedSnapshot);
```

When receipt matters, pair the push with an ordinary acknowledgement
operation — the treemap view calls its `pushReceived` operation after
applying each pushed snapshot.

## Cancellation

`HostViewSession.callWithHandle` returns a `HostViewCall` for the
in-flight request; `call` is `callWithHandle(...).result` for calls
that never cancel. `HostViewCall.cancel()` completes the caller's
`result` future with the `cancelled` code and sends a `cancel` frame.

Cancellation is per-request disposal, not preemption. The receiving
side drops the request's response eligibility, so a late result or
error is discarded fail-closed — never delivered — but a handler that
is already running is not aborted. The wire accepts `cancel` from
either initiator; the shipped view-side API does not expose a cancel
handle.

## Rendered reporting

The view reports the protocol-safe value it currently renders with
`ViewShell.reportRendered` (`FlutterViewSession.reportRendered`
underneath), which sends a `rendered` frame. The host's
`HostViewSession.rendered` future completes with the first reported
value — the supported way for a host to know its view is showing
meaningful content rather than merely connected.

## Shutdown and closing

`HostViewSession.shutdown()` sends a `shutdown` frame asking the view
to close in an orderly way; the view runs its close path and answers
with `closing`, whose `report` carries a measured `ViewCloseReport` —
pending-request and live-subscription counts taken after cleanup,
never constant zeros — and `shutdown()` completes with that report.
Both roles send `closing` from their own `close()`, every terminal
path (peer close, transport failure, receive-stream completion)
funnels into one idempotent cleanup, and each session's `closed`
future completes with its local report. `FlutterViewHost.open` wires
panel disposal into the same path and then fires `onClosed`.

## Fail-closed rules

Every inbound frame is validated before it is dispatched, against the
exact schema of its declared kind: the five envelope keys plus
exactly the payload keys in the table above. A missing key, an extra
key, an unknown kind, or a foreign `version` fails parsing. What
happens next depends on the role:

- **Host Dart is the session authority.** A frame that does not parse
  — including any `version` other than 2 — or that carries the wrong
  `session` or a non-active `nonce` is ignored: never executed, never
  answered.
- **The Flutter View trusts only its own host.** A frame that fails
  to parse, or whose `session` or `nonce` does not match, rejects the
  connection and terminates the session.

### Error codes

| Code | Meaning |
| --- | --- |
| `unsupported_version` | The peer selected a protocol version this runtime cannot speak. |
| `invalid_message` | A frame did not match the exact schema for its declared kind. |
| `session_mismatch` | A frame belongs to another Host/Flutter View session. |
| `nonce_mismatch` | A frame did not carry the nonce active for its session phase. |
| `operation_not_allowed` | A call named an operation the receiver did not expose. |
| `duplicate_request` | A request ID was reused within one active session. |
| `operation_failed` | An allowed operation failed while executing. |
| `session_closed` | The session closed before an operation could complete. |
| `cancelled` | An in-flight request was cancelled by its initiator. |

The generated host artifact surrounding the host half is documented
in [Generated Host API](generated-host-api.md); the measured cost of
opening a view — webview load to first rendered frame — is recorded
in [Flutter View Startup](startup.md).
