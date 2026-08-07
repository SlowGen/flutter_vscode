/// One deep interface over the Flutter View side of a session: connect,
/// the shared theme stream, host-event subscriptions, and rendered
/// reporting, all released by a single [ViewShell.dispose].
library;

import 'dart:async';

import 'package:dart_vscode/view_protocol.dart';
import 'package:flutter_vscode/src/view_shell_platform_stub.dart'
    if (dart.library.html) 'package:flutter_vscode/src/view_shell_platform_web.dart'
    as platform;
import 'package:flutter_vscode/src/view_theme_parser.dart';

/// Where a [ViewShell] captures and watches the VS Code theme.
///
/// The default source reads the live webview document; tests inject a
/// deterministic snapshot and stream instead.
final class ViewShellThemeSource {
  /// Creates a theme source over [read] and [changes].
  const ViewShellThemeSource({required this.read, required this.changes});

  /// Captures the current theme snapshot.
  final VSCodeThemeSnapshot Function() read;

  /// Emits one snapshot per subsequent theme change.
  final Stream<VSCodeThemeSnapshot> changes;
}

/// How a [ViewShell] connects its protocol session and releases the
/// transport that session rode on.
///
/// The default source acquires the VS Code webview transport; tests
/// inject an [InMemoryViewTransportPair] endpoint instead.
final class ViewShellSessionSource {
  /// Creates a session source over [connect] and an optional [release].
  const ViewShellSessionSource({required this.connect, this.release});

  /// Connects the session, exposing the given operations for
  /// host-initiated calls.
  final Future<FlutterViewSession> Function(
    Iterable<ViewOperationBinding> operations,
  )
  connect;

  /// Releases the underlying transport after the session has closed.
  final Future<void> Function()? release;
}

/// The Flutter View shell: one module owning session connect, the theme
/// stream, host-event subscriptions, and rendered reporting, with one
/// [dispose] releasing everything it created.
///
/// The shell is widget-free — Streams and Futures only — so application
/// code composes it into any widget tree and unit tests drive it over an
/// [InMemoryViewTransportPair] with an injected [ViewShellThemeSource].
final class ViewShell {
  ViewShell._(
    this.session,
    VSCodeThemeSnapshot theme,
    Stream<VSCodeThemeSnapshot> themeChanges,
    Future<void> Function()? release,
  ) : _theme = theme,
      _release = release {
    _themeSubscription = themeChanges.listen((snapshot) {
      if (snapshot == _theme) {
        return;
      }
      _theme = snapshot;
      _themeChanges.add(snapshot);
    });
  }

  /// Connects a shell for one Flutter View session.
  ///
  /// [operations] are the typed operations this view allows Host Dart to
  /// call. [sessionSource] and [themeSource] default to the live VS Code
  /// webview transport and document; tests inject deterministic seams
  /// instead.
  static Future<ViewShell> connect({
    Iterable<ViewOperationBinding> operations = const [],
    ViewShellSessionSource? sessionSource,
    ViewShellThemeSource? themeSource,
  }) async {
    final sessions = sessionSource ?? platform.defaultViewShellSessionSource();
    final themes = themeSource ?? platform.defaultViewShellThemeSource();
    final session = await sessions.connect(operations);
    return ViewShell._(
      session,
      themes.read(),
      themes.changes,
      sessions.release,
    );
  }

  /// The connected protocol session, for typed [ViewOperation] calls.
  final FlutterViewSession session;

  final Future<void> Function()? _release;
  final StreamController<VSCodeThemeSnapshot> _themeChanges =
      StreamController<VSCodeThemeSnapshot>.broadcast();
  final Map<String, _ShellEventForward> _eventForwards = {};
  late final StreamSubscription<VSCodeThemeSnapshot> _themeSubscription;
  VSCodeThemeSnapshot _theme;
  Future<void>? _disposal;

  /// The most recent VS Code theme snapshot.
  VSCodeThemeSnapshot get theme => _theme;

  /// Deduplicated theme changes behind one shared upstream subscription.
  ///
  /// The stream is a broadcast view over the single subscription this
  /// shell owns; it closes when the shell is disposed.
  Stream<VSCodeThemeSnapshot> get themeChanges => _themeChanges.stream;

  /// Host-pushed events for [stream], ending when this shell disposes.
  Stream<Object?> events(String stream) {
    if (_disposal != null) {
      return const Stream<Object?>.empty();
    }
    return _eventForwards
        .putIfAbsent(stream, () => _ShellEventForward(session.events(stream)))
        .controller
        .stream;
  }

  /// Reports the protocol-safe value this view currently renders.
  Future<void> reportRendered(Object? value) => session.reportRendered(value);

  /// Releases everything this shell owns — the theme subscription, the
  /// event forwards, the protocol session, and the transport it acquired
  /// — exactly once; later calls await the same disposal.
  Future<void> dispose() => _disposal ??= _runDispose();

  Future<void> _runDispose() async {
    await _themeSubscription.cancel();
    await _themeChanges.close();
    for (final forward in _eventForwards.values) {
      await forward.close();
    }
    _eventForwards.clear();
    try {
      await session.close();
    } finally {
      await _release?.call();
    }
  }
}

/// One shell-owned re-exposure of a session event stream, so disposing
/// the shell ends every downstream listener.
final class _ShellEventForward {
  _ShellEventForward(Stream<Object?> upstream) {
    subscription = upstream.listen(controller.add);
  }

  final StreamController<Object?> controller =
      StreamController<Object?>.broadcast();
  late final StreamSubscription<Object?> subscription;

  Future<void> close() async {
    await subscription.cancel();
    await controller.close();
  }
}
