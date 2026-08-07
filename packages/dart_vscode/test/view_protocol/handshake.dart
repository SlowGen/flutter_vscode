part of '../view_protocol_test.dart';

/// Handshake: version, session identity, nonce rotation, and admission ordering.
void registerViewProtocolHandshakeTests() {
  group('Host and Flutter View protocol: handshake', () {
    test('rejects a peer that speaks an unsupported version', () async {
      final transport = InMemoryViewTransportPair();
      final peer = transport.host.messages.listen((message) {
        final ready = (message! as Map<Object?, Object?>)
            .cast<String, Object?>();
        unawaited(
          transport.host.send({
            'protocol': 'flutter-vscode.view',
            'version': 3,
            'kind': 'readyAck',
            'session': ready['session'],
            'nonce': ready['nonce'],
            'activeNonce': 'active-1',
          }),
        );
      });

      await expectLater(
        FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        ),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.unsupportedVersion,
          ),
        ),
      );
      await peer.cancel();
    });

    test('rejects a message with fields outside its exact schema', () async {
      final transport = InMemoryViewTransportPair();
      final peer = transport.host.messages.listen((message) {
        final ready = (message! as Map<Object?, Object?>)
            .cast<String, Object?>();
        unawaited(
          transport.host.send({
            'protocol': 'flutter-vscode.view',
            'version': 2,
            'kind': 'readyAck',
            'session': ready['session'],
            'nonce': ready['nonce'],
            'activeNonce': 'active-1',
            'unexpected': true,
          }),
        );
      });

      await expectLater(
        FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        ),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );
      await peer.cancel();
    });

    test('rejects a handshake for another session', () async {
      final transport = InMemoryViewTransportPair();
      final peer = transport.host.messages.listen((message) {
        final ready = (message! as Map<Object?, Object?>)
            .cast<String, Object?>();
        unawaited(
          transport.host.send({
            'protocol': 'flutter-vscode.view',
            'version': 2,
            'kind': 'readyAck',
            'session': 'another-session',
            'nonce': ready['nonce'],
            'activeNonce': 'active-1',
          }),
        );
      });

      await expectLater(
        FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        ).timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.sessionMismatch,
          ),
        ),
      );
      await peer.cancel();
    });

    test('rejects a handshake with the wrong nonce', () async {
      final transport = InMemoryViewTransportPair();
      final peer = transport.host.messages.listen((message) {
        final ready = (message! as Map<Object?, Object?>)
            .cast<String, Object?>();
        unawaited(
          transport.host.send({
            'protocol': 'flutter-vscode.view',
            'version': 2,
            'kind': 'readyAck',
            'session': ready['session'],
            'nonce': 'wrong-bootstrap',
            'activeNonce': 'active-1',
          }),
        );
      });

      await expectLater(
        FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        ).timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.nonceMismatch,
          ),
        ),
      );
      await peer.cancel();
    });

    test('rejects a result frame before the ready acknowledgement', () async {
      final transport = InMemoryViewTransportPair();
      final peer = transport.host.messages.listen((message) {
        final ready = (message! as Map<Object?, Object?>)
            .cast<String, Object?>();
        unawaited(
          transport.host.send({
            'protocol': 'flutter-vscode.view',
            'version': 2,
            'kind': 'result',
            'session': ready['session'],
            'nonce': ready['nonce'],
            'id': 'request-1',
            'result': 'too early',
          }),
        );
      });

      await expectLater(
        FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        ).timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );
      await peer.cancel();
    });

    test(
      'Host ready acknowledgement send failure closes without escaping',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _KindFailingViewTransport(pair.host, 'readyAck');
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await expectLater(
          FlutterViewSession.connect(
            transport: pair.view,
            sessionId: 'session-1',
            bootstrapNonce: 'bootstrap-1',
          ),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await host.closed.timeout(const Duration(milliseconds: 100));
        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
      },
    );

    test(
      'async Host ready acknowledgement failure settles both sessions',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _DeferredFailingViewTransport(pair.host, 'readyAck');
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final connection = FlutterViewSession.connect(
          transport: pair.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final hostReady = expectLater(
          host.ready.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );
        final viewConnection = expectLater(
          connection.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await transport.deliveryStarted;
        transport.fail(StateError('native ready acknowledgement rejected'));

        await hostReady;
        await viewConnection;
        await host.closed.timeout(const Duration(milliseconds: 100));
        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
      },
    );

    test(
      'a reload rotates the nonce and abandons late Host Dart results',
      () async {
        final operation = _snapshotOperation('fixture.wait');
        final operationResult = Completer<Object?>();
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [operation.bind((_) => operationResult.future)],
        );
        final received = <Map<String, Object?>>[];
        final peer = transport.view.messages.listen((message) {
          received.add(
            (message! as Map<Object?, Object?>).cast<String, Object?>(),
          );
        });
        const ready = {
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'ready',
          'session': 'session-1',
          'nonce': 'bootstrap-1',
        };

        await transport.view.send(ready);
        final firstNonce = received.single['activeNonce'];
        await transport.view.send({
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'call',
          'session': 'session-1',
          'nonce': firstNonce,
          'id': 'request-1',
          'operation': 'fixture.wait',
          'arguments': null,
        });
        expect(host.pendingRequestCount, 1);

        await transport.view.send(ready);

        expect(received, hasLength(2));
        expect(received.last['kind'], 'readyAck');
        expect(received.last['activeNonce'], isNot(firstNonce));
        expect(host.pendingRequestCount, 1);
        expect(host.subscriptionCount, 1);

        operationResult.complete('late value');
        await Future<void>.delayed(Duration.zero);
        expect(
          received.where((message) => message['kind'] == 'result'),
          isEmpty,
        );
        expect(host.pendingRequestCount, 0);

        await host.close();
        await peer.cancel();
      },
    );

    test(
      'Host installs the active nonce before a synchronous ready ack',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _ReadyAckObservingViewTransport(pair.host);
        late HostViewSession host;
        late Future<ViewCloseReport> shutdown;
        host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await pair.view.send(const {
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'ready',
          'session': 'session-1',
          'nonce': 'bootstrap-1',
        });
        await host.ready;
        transport.onReadyAck = () {
          shutdown = host.shutdown();
          unawaited(
            shutdown.then<void>(
              (_) {},
              onError: (Object error, StackTrace stackTrace) {},
            ),
          );
        };
        await pair.view.send(const {
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'ready',
          'session': 'session-1',
          'nonce': 'bootstrap-1',
        });

        expect(transport.sentKinds, ['readyAck', 'readyAck', 'shutdown']);
        final readyAck = (transport.sent[1]! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final shutdownFrame = (transport.sent[2]! as Map<Object?, Object?>)
            .cast<String, Object?>();
        expect(
          shutdownFrame['nonce'],
          readyAck['activeNonce'],
          reason:
              'a shutdown emitted synchronously during ready-ack delivery '
              'must already carry the newly installed nonce',
        );
        await pair.view.send({
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'closing',
          'session': 'session-1',
          'nonce': readyAck['activeNonce'],
          'report': const {
            'pendingRequestCount': 0,
            'subscriptionCount': 0,
          },
        });
        final report = await shutdown.timeout(
          const Duration(milliseconds: 100),
        );
        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
        await host.closed;
      },
    );

    test('peer close during handshake fails Flutter View connect', () async {
      final transport = InMemoryViewTransportPair();
      final connection = FlutterViewSession.connect(
        transport: transport.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final connectionFailure = expectLater(
        connection.timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.sessionClosed,
          ),
        ),
      );

      await transport.host.send({
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'closing',
        'session': 'session-1',
        'nonce': 'bootstrap-1',
        'report': const {
          'pendingRequestCount': 0,
          'subscriptionCount': 0,
        },
      });

      await connectionFailure;
    });

    test(
      'peer shutdown during handshake settles Flutter View connect',
      () async {
        final transport = InMemoryViewTransportPair();
        final closingFrame = Completer<Map<String, Object?>>();
        final peer = transport.host.messages.listen((message) {
          final frame = (message! as Map<Object?, Object?>)
              .cast<String, Object?>();
          if (frame['kind'] == 'closing' && !closingFrame.isCompleted) {
            closingFrame.complete(frame);
          }
        });
        final connection = FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final connectionFailure = expectLater(
          connection.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await transport.host.send({
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'shutdown',
          'session': 'session-1',
          'nonce': 'bootstrap-1',
        });

        await connectionFailure;
        final frame = await closingFrame.future.timeout(
          const Duration(milliseconds: 100),
        );
        final report = (frame['report']! as Map<Object?, Object?>)
            .cast<String, Object?>();
        expect(report['pendingRequestCount'], 0);
        expect(report['subscriptionCount'], 0);
        await peer.cancel();
      },
    );
  });
}
