import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vscode/view.dart';

VSCodeThemeSnapshot _theme(int editorBackground) => VSCodeThemeSnapshot(
  kind: VSCodeThemeKind.dark,
  colors: {'editor-background': editorBackground},
);

ViewOperation<Object?, Object?> _identityOperation(String name) =>
    ViewOperation<Object?, Object?>(
      name: name,
      encodeArguments: (value) => value,
      decodeArguments: (value) => value,
      encodeResult: (value) => value,
      decodeResult: (value) => value,
    );

/// One connected Host role and [ViewShell] over an in-memory transport
/// pair, with the injected theme seam and transport-release recorder.
final class _ShellFixture {
  _ShellFixture._(this.host, this.shell, this.themeChanges, this.releases);

  static Future<_ShellFixture> connect({
    Iterable<ViewOperationBinding> operations = const [],
    Iterable<ViewOperationBinding> hostOperations = const [],
  }) async {
    final transport = InMemoryViewTransportPair();
    final host = HostViewSession.connect(
      transport: transport.host,
      sessionId: 'session-1',
      bootstrapNonce: 'bootstrap-1',
      operations: hostOperations,
    );
    final themeChanges = StreamController<VSCodeThemeSnapshot>();
    final releases = <String>[];
    final shell = await ViewShell.connect(
      operations: operations,
      sessionSource: ViewShellSessionSource(
        connect: (viewOperations) => FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: viewOperations,
        ),
        release: () async => releases.add('transport'),
      ),
      themeSource: ViewShellThemeSource(
        read: () => _theme(0xFF101010),
        changes: themeChanges.stream,
      ),
    );
    await host.ready;
    return _ShellFixture._(host, shell, themeChanges, releases);
  }

  final HostViewSession host;
  final ViewShell shell;

  /// The injected single-subscription upstream theme stream.
  final StreamController<VSCodeThemeSnapshot> themeChanges;

  /// Transport releases observed through the session-source seam.
  final List<String> releases;

  Future<void> close() async {
    await shell.dispose();
    await themeChanges.close();
  }
}

void main() {
  group('ViewShell.connect', () {
    test(
      'exposes the connected session and the initial theme snapshot',
      () async {
        final fixture = await _ShellFixture.connect();
        addTearDown(fixture.close);

        expect(fixture.shell.theme, _theme(0xFF101010));
        expect(fixture.shell.session.subscriptionCount, 1);
        expect(fixture.shell.session.activeNonce, isNotNull);
      },
    );

    test(
      'passes view operations through to the host-callable allowlist',
      () async {
        final echo = _identityOperation('view.echo');
        final fixture = await _ShellFixture.connect(
          operations: [echo.bind((value) => value)],
        );
        addTearDown(fixture.close);

        expect(await fixture.host.call(echo, {'ping': 1}), {'ping': 1});
      },
    );
  });

  group('ViewShell theme stream', () {
    test('tracks the current theme without any listeners', () async {
      final fixture = await _ShellFixture.connect();
      addTearDown(fixture.close);

      fixture.themeChanges.add(_theme(0xFF404040));
      await pumpEventQueue();

      expect(fixture.shell.theme, _theme(0xFF404040));
    });

    test('dedupes changes and shares one upstream subscription', () async {
      final fixture = await _ShellFixture.connect();
      addTearDown(fixture.close);
      // The injected upstream allows a single subscription: a shell that
      // subscribed once per listener would throw on the second listen.
      expect(fixture.themeChanges.hasListener, isTrue);

      final first = <VSCodeThemeSnapshot>[];
      final second = <VSCodeThemeSnapshot>[];
      final firstListener = fixture.shell.themeChanges.listen(first.add);
      final secondListener = fixture.shell.themeChanges.listen(second.add);
      addTearDown(firstListener.cancel);
      addTearDown(secondListener.cancel);

      fixture.themeChanges
        ..add(_theme(0xFF101010))
        ..add(_theme(0xFF202020))
        ..add(_theme(0xFF202020));
      await pumpEventQueue();

      expect(first, [_theme(0xFF202020)]);
      expect(second, [_theme(0xFF202020)]);
      expect(fixture.shell.theme, _theme(0xFF202020));
    });
  });

  group('ViewShell events and rendered reporting', () {
    test('events() round-trips a host emitEvent payload', () async {
      final fixture = await _ShellFixture.connect();
      addTearDown(fixture.close);

      final payloads = <Object?>[];
      final listener = fixture.shell
          .events('fixture.push')
          .listen(payloads.add);
      addTearDown(listener.cancel);
      await fixture.host.emitEvent('fixture.push', {'run': 1});
      await pumpEventQueue();

      expect(payloads, [
        {'run': 1},
      ]);
    });

    test('reportRendered reaches the host rendered future', () async {
      final fixture = await _ShellFixture.connect();
      addTearDown(fixture.close);

      await fixture.shell.reportRendered({'tiles': 3});

      expect(await fixture.host.rendered, {'tiles': 3});
    });
  });

  group('ViewShell.dispose', () {
    test('cancels everything the shell owns in one call', () async {
      final fixture = await _ShellFixture.connect();
      var eventsDone = false;
      var themesDone = false;
      fixture.shell
          .events('fixture.push')
          .listen(null, onDone: () => eventsDone = true);
      fixture.shell.themeChanges.listen(null, onDone: () => themesDone = true);

      await fixture.shell.dispose();
      await pumpEventQueue();

      expect(fixture.themeChanges.hasListener, isFalse);
      expect(fixture.shell.session.subscriptionCount, 0);
      expect(fixture.shell.session.pendingRequestCount, 0);
      expect(eventsDone, isTrue);
      expect(themesDone, isTrue);
      expect(fixture.releases, ['transport']);

      final hostReport = await fixture.host.closed;
      expect(hostReport.pendingRequestCount, 0);
      expect(hostReport.subscriptionCount, 0);

      await fixture.shell.dispose();
      expect(fixture.releases, ['transport']);
      await fixture.themeChanges.close();
    });
  });

  group('void-codec helpers', () {
    test('noArgs and noResult supply both void codec sides', () async {
      final snapshot = ViewOperation.noArgs<String>(
        'fixture.readSnapshot',
        encodeResult: (value) => value,
        decodeResult: (value) => value! as String,
      );
      final report = ViewOperation.noResult<String>(
        'fixture.report',
        encodeArguments: (value) => value,
        decodeArguments: (value) => value! as String,
      );
      final reported = <String>[];
      final transport = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
        operations: [
          snapshot.bind((_) => 'snapshot-1'),
          report.bind(reported.add),
        ],
      );
      final view = await FlutterViewSession.connect(
        transport: transport.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      await host.ready;
      addTearDown(() async {
        await view.close();
        await host.closed;
      });

      expect(await snapshot.call(view, null), 'snapshot-1');
      await report.call(view, 'dark');
      expect(reported, ['dark']);
    });

    test('the void decode guard rejects a non-null payload', () async {
      final permissive = _identityOperation('fixture.badAck');
      final strict = ViewOperation.noResult<Object?>(
        'fixture.badAck',
        encodeArguments: (value) => value,
        decodeArguments: (value) => value,
      );
      final transport = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
        operations: [permissive.bind((_) => 'not-null')],
      );
      final view = await FlutterViewSession.connect(
        transport: transport.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      await host.ready;
      addTearDown(() async {
        await view.close();
        await host.closed;
      });

      await expectLater(
        strict.call(view, null),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );
    });
  });
}
