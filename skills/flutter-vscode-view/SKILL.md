---
name: flutter-vscode-view
description: >-
  Author a Flutter View in a flutter_vscode Extension Project: ViewShell,
  VS Code theming, typed view operations, and host push events.
---

# Author a Flutter View

A Flutter View is a separate Flutter web runtime under `views/<name>/` that
renders inside a VS Code webview and talks to Host Dart only through the
versioned view protocol. Everything below comes from
`package:flutter_vscode/view.dart`.

## Boot with ViewShell and runFlutterView

```dart
import 'package:flutter_vscode/view.dart';

Future<void> main() async {
  final shell = await ViewShell.connect();
  runFlutterView(MyApp(shell: shell));
}
```

`ViewShell.connect` owns the protocol session, the live VS Code theme, and
every subscription it hands out; pass `operations:` with
`ViewOperation.bind(...)` bindings when Host Dart should be able to call
into the view. Boot with `runFlutterView`, never plain `runApp`: it disables
the web URL strategy first, because the webview's `vscode-webview://` origin
makes the default strategy throw a cross-origin `SecurityError` during
engine startup.

## Theme from VS Code

The shell exposes `shell.theme` (the latest `VSCodeThemeSnapshot`) and
`shell.themeChanges` (a deduplicated broadcast stream). Feed them through
`vsCodeThemeData` so the view restyles live when the user switches color
themes:

```dart
StreamBuilder<VSCodeThemeSnapshot>(
  stream: shell.themeChanges,
  initialData: shell.theme,
  builder: (context, snapshot) => MaterialApp(
    theme: vsCodeThemeData(snapshot.data ?? shell.theme),
    home: MyPage(shell: shell),
  ),
)
```

Underneath sit `readVSCodeTheme` (one snapshot from the webview document's
body class and `--vscode-*` variables) and `watchVSCodeTheme` (a shared
`MutationObserver` stream); prefer the shell's pre-wired surface over
calling them directly.

## Typed operations

Declare each cross-runtime call as a shared `ViewOperation` with explicit
codecs; `ViewOperation.noArgs` and `ViewOperation.noResult` supply the void
side:

```dart
final ViewOperation<void, Snapshot> snapshotOperation = ViewOperation.noArgs(
  'snapshot',
  encodeResult: encodeSnapshot,
  decodeResult: decodeSnapshot,
);
```

The calling side invokes, the serving side binds. View calls host:
`await snapshotOperation.call(shell.session, null)`, with Host Dart passing
`snapshotOperation.bind(handler)` in the `operations:` of
`FlutterViewHost.open`. Host calls view: the view passes bindings to
`ViewShell.connect(operations: [...])` and the host uses
`viewHost.session.call(operation, arguments)`. Only protocol-safe value
snapshots cross the boundary — never native VS Code objects.

## Host push events

For host-initiated refresh without polling, Host Dart pushes one-way events
and the view subscribes by stream name:

```dart
// Host Dart
await viewHost.session.emitEvent('snapshot-push', encodeSnapshot(snapshot));

// Flutter View
shell.events('snapshot-push').listen(applyPushedSnapshot);
```

Streams from `shell.events` end when the shell disposes, so widgets need no
per-subscription cancellation. Call `shell.dispose()` exactly once (for
example in `State.dispose`); it releases the theme subscription, event
forwards, session, and transport together.

## Webview constraints

The generated host HTML carries a strict CSP (`default-src 'none'` with
sources scoped to the webview resource origin), so the view has no network
at runtime. Bundle every asset — fonts included — in the view package's
`pubspec.yaml` (the shipped example bundles `fonts/Roboto-Variable.ttf`)
instead of fetching anything remotely. Built assets ship beneath
`out/views/<name>/` via `flutter_vscode build`.

A working consumer of all of the above is the shipped
`coverage_treemap` extension's `views/treemap_panel/lib/main.dart`. Keep
host behavior working when the view never opens, and see
`flutter-vscode-troubleshoot` when the panel misbehaves.
