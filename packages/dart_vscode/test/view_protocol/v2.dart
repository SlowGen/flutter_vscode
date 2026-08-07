part of '../view_protocol_test.dart';

/// The version-2 session, with the paired-connection fixture its tests share.
void registerViewProtocolV2Tests() {
  group('Host and Flutter View protocol v2', () {
    Future<(HostViewSession, FlutterViewSession)> connectPair({
      Iterable<ViewOperationBinding> hostOperations = const [],
      Iterable<ViewOperationBinding> viewOperations = const [],
    }) async {
      final pair = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: pair.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
        operations: hostOperations,
      );
      final view = await FlutterViewSession.connect(
        transport: pair.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
        operations: viewOperations,
      );
      return (host, view);
    }

    test('the host calls a view-bound operation', () async {
      final operation = _snapshotOperation('view.echo');
      final (host, view) = await connectPair(
        viewOperations: [
          operation.bind((value) => 'view saw $value'),
        ],
      );

      final result = await host.call(operation, 'ping');

      expect(result, 'view saw ping');
      await view.close();
    });

    test(
      'a failing view-bound operation surfaces a structured error',
      () async {
        final operation = _snapshotOperation('view.fails');
        final (host, view) = await connectPair(
          viewOperations: [
            operation.bind((_) => throw StateError('view exploded')),
          ],
        );

        await expectLater(
          host.call(operation, null),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.operationFailed,
            ),
          ),
        );
        await view.close();
      },
    );

    test('a cancelled host call completes with cancellation', () async {
      final operation = _snapshotOperation('view.slow');
      final gate = Completer<Object?>();
      final (host, view) = await connectPair(
        viewOperations: [
          operation.bind((_) => gate.future),
        ],
      );

      final call = host.callWithHandle(operation, null);
      await pumpEventQueue();
      call.cancel();

      await expectLater(
        call.result,
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.cancelled,
          ),
        ),
      );
      expect(host.pendingHostCallCount, 0);
      gate.complete('too late');
      await pumpEventQueue();
      expect(host.pendingHostCallCount, 0);
      await view.close();
    });

    test('host events reach view stream subscribers in order', () async {
      final (host, view) = await connectPair();
      final seen = <Object?>[];
      final subscription = view.events('coverage').listen(seen.add);

      await host.emitEvent('coverage', {'run': 1});
      await host.emitEvent('coverage', {'run': 2});
      await host.emitEvent('other', {'run': 3});
      await pumpEventQueue();

      expect(seen, [
        {'run': 1},
        {'run': 2},
      ]);
      await subscription.cancel();
      await view.close();
    });

    test('a version-1 frame fails closed as unsupported', () async {
      final pair = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: pair.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: pair.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      await pair.view.send({
        'protocol': 'flutter-vscode.view',
        'version': 1,
        'kind': 'call',
        'session': 'session-1',
        'nonce': view.activeNonce,
        'id': 'stale-1',
        'operation': 'view.echo',
        'arguments': null,
      });
      await pumpEventQueue();

      // A stale-version frame is ignored fail-closed: never executed,
      // never answered, and the session stays healthy.
      expect(host.pendingRequestCount, 0);
      await view.close();
      await host.closed;
    });
  });
}
