part of '../view_protocol_test.dart';

/// Teardown: send failures, closes, and the cleanup both sides must converge on.
void registerViewProtocolTeardownTests() {
  group('Host and Flutter View protocol: teardown', () {
    test(
      'Host result send failure closes both sessions without a zone error',
      () async {
        final operation = _snapshotOperation('fixture.echo');
        final pair = InMemoryViewTransportPair();
        final transport = _KindFailingViewTransport(pair.host, 'result');
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [operation.bind((value) => value)],
        );
        final view = await FlutterViewSession.connect(
          transport: pair.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await expectLater(
          operation
              .call(view, 'value')
              .timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await host.closed.timeout(const Duration(milliseconds: 100));
        await view.closed.timeout(const Duration(milliseconds: 100));
        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
      },
    );

    test(
      'Host error send failure closes both sessions without a zone error',
      () async {
        final operation = _snapshotOperation('fixture.fail');
        final pair = InMemoryViewTransportPair();
        final transport = _KindFailingViewTransport(pair.host, 'error');
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind((_) => throw StateError('operation failed')),
          ],
        );
        final view = await FlutterViewSession.connect(
          transport: pair.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await expectLater(
          operation.call(view, null).timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await host.closed.timeout(const Duration(milliseconds: 100));
        await view.closed.timeout(const Duration(milliseconds: 100));
        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
      },
    );

    test(
      'host close fails pending calls and releases both session listeners',
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
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        final pendingCall = operation.call(view, null);
        expect(view.pendingRequestCount, 1);
        expect(host.pendingRequestCount, 1);

        final pendingFailure = expectLater(
          pendingCall,
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );
        await host.close();
        await pendingFailure;
        await view.closed.timeout(const Duration(milliseconds: 100));
        final hostCloseReport = await host.closed;
        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
        expect(host.pendingRequestCount, 1);
        expect(host.subscriptionCount, 0);
        expect(hostCloseReport.pendingRequestCount, 1);

        operationResult.complete('late value');
        await Future<void>.delayed(Duration.zero);
        expect(view.pendingRequestCount, 0);
        expect(host.pendingRequestCount, 0);
      },
    );

    test(
      'render report delivery failure terminates the Flutter View',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _SwitchableViewTransport(pair.view);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        addTearDown(host.close);
        transport.failSends = true;

        await expectLater(view.reportRendered('hello'), throwsStateError);

        final report = await view.closed.timeout(
          const Duration(milliseconds: 100),
        );
        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
      },
    );

    test('async render delivery failure terminates the Flutter View', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _DeferredFailingViewTransport(pair.view, 'rendered');
      final host = HostViewSession.connect(
        transport: pair.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      addTearDown(host.close);

      final render = Future<void>.sync(() => view.reportRendered('hello'));
      await transport.deliveryStarted;
      transport.fail(StateError('native rendered delivery rejected'));

      await expectLater(render, throwsStateError);
      final report = await view.closed.timeout(
        const Duration(milliseconds: 100),
      );
      expect(report.pendingRequestCount, 0);
      expect(report.subscriptionCount, 0);
      expect(view.pendingRequestCount, 0);
      expect(view.subscriptionCount, 0);
    });

    test(
      'host shutdown observes the Flutter View zero-count close report',
      () async {
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        final viewClosed = view.closed;
        final hostClosed = host.closed;
        final report = await host.shutdown().timeout(
          const Duration(milliseconds: 100),
        );
        final viewReport = await viewClosed;
        final hostReport = await hostClosed;

        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
        expect(viewReport.pendingRequestCount, 0);
        expect(viewReport.subscriptionCount, 0);
        expect(hostReport.pendingRequestCount, 0);
        expect(hostReport.subscriptionCount, 0);
        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
      },
    );

    test('shutdown after peer close preserves its measured report', () async {
      final transport = InMemoryViewTransportPair();
      late String activeNonce;
      final peer = transport.view.messages.listen((rawMessage) {
        final message = (rawMessage! as Map<Object?, Object?>)
            .cast<String, Object?>();
        if (message['kind'] == 'readyAck') {
          activeNonce = message['activeNonce']! as String;
        }
      });
      addTearDown(peer.cancel);
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      await transport.view.send(const {
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'ready',
        'session': 'session-1',
        'nonce': 'bootstrap-1',
      });
      await host.ready;
      await transport.view.send({
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'closing',
        'session': 'session-1',
        'nonce': activeNonce,
        'report': const {
          'pendingRequestCount': 3,
          'subscriptionCount': 2,
        },
      });
      await host.closed;

      final report = await host.shutdown();

      expect(report.pendingRequestCount, 3);
      expect(report.subscriptionCount, 2);
    });

    test(
      'Flutter View reports counts after its listener actually cancels',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _DelayedCancelViewTransport(pair.view);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        final shutdown = host.shutdown();
        await transport.cancellationStarted;

        expect(transport.sentClosing, isFalse);
        expect(view.subscriptionCount, 1);

        transport.allowCancellation();
        final report = await shutdown.timeout(
          const Duration(milliseconds: 100),
        );

        expect(transport.sentClosingAfterCancellation, isTrue);
        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
        expect(view.subscriptionCount, 0);
      },
    );

    test('concurrent Flutter View closes join the same cleanup', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _DelayedCancelViewTransport(pair.view);
      final host = HostViewSession.connect(
        transport: pair.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      final firstClose = view.close();
      await transport.cancellationStarted;
      var secondCloseCompleted = false;
      final secondClose = view.close().then((_) {
        secondCloseCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(secondCloseCompleted, isFalse);

      transport.allowCancellation();
      await Future.wait([firstClose, secondClose]);
      await host.closed;
      expect(secondCloseCompleted, isTrue);
      expect(view.subscriptionCount, 0);
    });

    test(
      'Flutter View close joins peer-triggered cleanup in progress',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _DelayedCancelViewTransport(pair.view);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        final hostClose = host.close();
        await transport.cancellationStarted;
        var viewCloseCompleted = false;
        final viewClose = view.close().then((_) {
          viewCloseCompleted = true;
        });
        await Future<void>.delayed(Duration.zero);

        expect(viewCloseCompleted, isFalse);

        transport.allowCancellation();
        await Future.wait([hostClose, viewClose]);
        expect(viewCloseCompleted, isTrue);
        expect(view.subscriptionCount, 0);
      },
    );

    test(
      'Flutter View closes native receiving before reporting counts',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _ReceivingLifecycleViewTransport(pair.view);
        addTearDown(transport.closeReceiving);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        final report = await host.shutdown().timeout(
          const Duration(milliseconds: 100),
        );

        expect(transport.sentClosingAfterReceivingClose, isTrue);
        expect(transport.receivingSubscriptionCount, 0);
        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
      },
    );

    test('host close before ready fails the pending ready future', () async {
      final transport = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final readyFailure = expectLater(
        host.ready.timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.sessionClosed,
          ),
        ),
      );

      await host.close();

      await readyFailure;
      expect(host.subscriptionCount, 0);
    });

    test(
      'Host receive completion terminates every pending lifecycle',
      () async {
        final transport = _ControllableViewTransport();
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final readyFailure = expectLater(
          host.ready.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );
        final renderedFailure = expectLater(
          host.rendered.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await transport.closeMessages();

        await readyFailure;
        await renderedFailure;
        final report = await host.closed.timeout(
          const Duration(milliseconds: 100),
        );
        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
        await expectLater(
          host.shutdown(),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );
      },
    );

    test('Host receive error is preserved as the shutdown failure', () async {
      final transport = _ControllableViewTransport();
      addTearDown(transport.closeMessages);
      final host = HostViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      transport.addReceiveError(StateError('transport receive failed'));

      await host.closed.timeout(const Duration(milliseconds: 100));
      await expectLater(
        host.shutdown(),
        throwsA(
          isA<ViewProtocolException>()
              .having(
                (error) => error.code,
                'code',
                ViewProtocolErrorCode.sessionClosed,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Host receive stream failed'),
              )
              .having(
                (error) => error.details,
                'details',
                contains('transport receive failed'),
              ),
        ),
      );
    });

    test('Host reports counts after its listener actually cancels', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _DelayedCancelViewTransport(pair.host);
      final host = HostViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      final close = host.close();
      await transport.cancellationStarted;

      expect(transport.sentClosing, isFalse);
      expect(host.subscriptionCount, 1);

      transport.allowCancellation();
      await close.timeout(const Duration(milliseconds: 100));

      expect(transport.sentClosingAfterCancellation, isTrue);
      expect(host.pendingRequestCount, 0);
      expect(host.subscriptionCount, 0);
    });

    test('concurrent Host closes join the same cleanup', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _DelayedCancelViewTransport(pair.host);
      final host = HostViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      final firstClose = host.close();
      await transport.cancellationStarted;
      var secondCloseCompleted = false;
      final secondClose = host.close().then((_) {
        secondCloseCompleted = true;
      });
      await Future<void>.delayed(Duration.zero);

      expect(secondCloseCompleted, isFalse);

      transport.allowCancellation();
      await Future.wait([firstClose, secondClose]);
      expect(secondCloseCompleted, isTrue);
      expect(host.subscriptionCount, 0);
    });

    test(
      'Host close joins peer-triggered cleanup already in progress',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _DelayedCancelViewTransport(pair.host);
        late String activeNonce;
        final peer = pair.view.messages.listen((rawMessage) {
          final message = (rawMessage! as Map<Object?, Object?>)
              .cast<String, Object?>();
          if (message['kind'] == 'readyAck') {
            activeNonce = message['activeNonce']! as String;
          }
        });
        addTearDown(peer.cancel);
        final host = HostViewSession.connect(
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
        await pair.view.send({
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'closing',
          'session': 'session-1',
          'nonce': activeNonce,
          'report': const {
            'pendingRequestCount': 0,
            'subscriptionCount': 0,
          },
        });
        await transport.cancellationStarted;
        var closeCompleted = false;
        final close = host.close().then((_) {
          closeCompleted = true;
        });
        await Future<void>.delayed(Duration.zero);

        expect(closeCompleted, isFalse);

        transport.allowCancellation();
        await close;
        expect(closeCompleted, isTrue);
        expect(host.subscriptionCount, 0);
      },
    );

    test('Host closes native receiving before reporting counts', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _ReceivingLifecycleViewTransport(pair.host);
      addTearDown(transport.closeReceiving);
      final host = HostViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: pair.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      await host.close();
      final report = await view.closed.timeout(
        const Duration(milliseconds: 100),
      );

      expect(transport.sentClosingAfterReceivingClose, isTrue);
      expect(transport.receivingSubscriptionCount, 0);
      expect(report.pendingRequestCount, 0);
      expect(report.subscriptionCount, 0);
    });

    test(
      'Flutter peer termination reports after its listener cancels',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _DelayedCancelViewTransport(pair.view);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        await view.reportRendered(null);
        await host.rendered;

        final close = host.close();
        await transport.cancellationStarted;

        expect(view.subscriptionCount, 1);

        transport.allowCancellation();
        await close.timeout(const Duration(milliseconds: 100));
        final report = await view.closed.timeout(
          const Duration(milliseconds: 100),
        );

        expect(report.pendingRequestCount, 0);
        expect(report.subscriptionCount, 0);
        expect(view.subscriptionCount, 0);
      },
    );

    test('Flutter peer termination closes native receiving', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _ReceivingLifecycleViewTransport(pair.view);
      addTearDown(transport.closeReceiving);
      final host = HostViewSession.connect(
        transport: pair.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      await host.close();
      final report = await view.closed.timeout(
        const Duration(milliseconds: 100),
      );

      expect(transport.receivingSubscriptionCount, 0);
      expect(report.pendingRequestCount, 0);
      expect(report.subscriptionCount, 0);
    });

    test(
      'view close before rendering fails the host rendered future',
      () async {
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final renderedFailure = expectLater(
          host.rendered.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await view.close();

        await renderedFailure;
        expect(host.subscriptionCount, 0);
      },
    );

    test('host close interrupts a pending orderly shutdown report', () async {
      final transport = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final peer = transport.view.messages.listen((_) {});
      await transport.view.send({
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'ready',
        'session': 'session-1',
        'nonce': 'bootstrap-1',
      });
      await host.ready;
      final shutdownFailure = expectLater(
        host.shutdown().timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.sessionClosed,
          ),
        ),
      );

      await host.close();

      await shutdownFailure;
      expect(host.subscriptionCount, 0);
      await peer.cancel();
    });

    test(
      'Flutter receive completion terminates a pending connection',
      () async {
        final transport = _ControllableViewTransport();
        final connection = FlutterViewSession.connect(
          transport: transport,
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

        await transport.closeMessages();

        await connectionFailure;
      },
    );

    test('Flutter receive error fails pending calls and closes', () async {
      final operation = _snapshotOperation('fixture.wait');
      final transport = _ControllableViewTransport();
      addTearDown(transport.closeMessages);
      final connection = FlutterViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      transport.addMessage(const {
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'readyAck',
        'session': 'session-1',
        'nonce': 'bootstrap-1',
        'activeNonce': 'active-1',
      });
      final view = await connection;
      final callFailure = expectLater(
        operation.call(view, null).timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>()
              .having(
                (error) => error.code,
                'code',
                ViewProtocolErrorCode.sessionClosed,
              )
              .having(
                (error) => error.message,
                'message',
                contains('Flutter View receive stream failed'),
              )
              .having(
                (error) => error.details,
                'details',
                contains('transport receive failed'),
              ),
        ),
      );
      expect(view.pendingRequestCount, 1);

      transport.addReceiveError(StateError('transport receive failed'));

      await callFailure;
      final report = await view.closed.timeout(
        const Duration(milliseconds: 100),
      );
      expect(report.pendingRequestCount, 0);
      expect(report.subscriptionCount, 0);
    });

    test(
      'Host close releases its listener when transport send throws',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _SwitchableViewTransport(pair.host);
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        transport.failSends = true;

        await expectLater(host.close(), throwsStateError);

        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
        expect(
          await host.closed.timeout(const Duration(milliseconds: 100)),
          isA<ViewCloseReport>(),
        );
      },
    );

    test(
      'Host shutdown releases its listener when transport send throws',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _SwitchableViewTransport(pair.host);
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: pair.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        transport.failSends = true;

        await expectLater(
          Future<ViewCloseReport>.sync(host.shutdown),
          throwsStateError,
        );

        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
        await host.closed.timeout(const Duration(milliseconds: 100));
        await view.close();
      },
    );

    test('async Host shutdown delivery failure releases Host state', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _DeferredFailingViewTransport(pair.host, 'shutdown');
      final host = HostViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: pair.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      addTearDown(view.close);

      final shutdown = host.shutdown();
      await transport.deliveryStarted;
      transport.fail(StateError('native shutdown delivery rejected'));

      await expectLater(shutdown, throwsStateError);
      await host.closed.timeout(const Duration(milliseconds: 100));
      expect(host.pendingRequestCount, 0);
      expect(host.subscriptionCount, 0);
    });

    test(
      'Host cancellation failure still completes every lifecycle future',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _CancelFailingViewTransport(pair.host);
        final host = HostViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final readyFailure = expectLater(
          host.ready.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );
        final renderedFailure = expectLater(
          host.rendered.timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.sessionClosed,
            ),
          ),
        );

        await expectLater(host.close(), throwsStateError);

        await readyFailure;
        await renderedFailure;
        await host.closed.timeout(const Duration(milliseconds: 100));
        expect(host.pendingRequestCount, 0);
        expect(host.subscriptionCount, 0);
      },
    );

    test('Flutter View cancellation failure still completes closed', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _CancelFailingViewTransport(pair.view);
      final host = HostViewSession.connect(
        transport: pair.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      await expectLater(view.close(), throwsStateError);

      await view.closed.timeout(const Duration(milliseconds: 100));
      await host.closed.timeout(const Duration(milliseconds: 100));
      expect(view.pendingRequestCount, 0);
      expect(view.subscriptionCount, 0);
      expect(host.pendingRequestCount, 0);
      expect(host.subscriptionCount, 0);
    });

    test('background Host cancellation failure is observed', () async {
      final pair = InMemoryViewTransportPair();
      final transport = _CancelFailingViewTransport(pair.host);
      final host = HostViewSession.connect(
        transport: transport,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );
      final view = await FlutterViewSession.connect(
        transport: pair.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      await view.close();

      await host.closed.timeout(const Duration(milliseconds: 100));
      expect(host.pendingRequestCount, 0);
      expect(host.subscriptionCount, 0);
    });

    test(
      'Flutter View call rolls back and closes when transport send throws',
      () async {
        final operation = _snapshotOperation('fixture.echo');
        final pair = InMemoryViewTransportPair();
        final transport = _SwitchableViewTransport(pair.view);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [operation.bind((value) => value)],
        );
        final view = await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        transport.failSends = true;

        await expectLater(
          Future<Object?>.sync(() => operation.call(view, null)),
          throwsStateError,
        );

        await view.closed.timeout(const Duration(milliseconds: 100));
        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
        await host.close();
      },
    );

    test(
      'Flutter View close completes cleanup when transport send throws',
      () async {
        final pair = InMemoryViewTransportPair();
        final transport = _SwitchableViewTransport(pair.view);
        final host = HostViewSession.connect(
          transport: pair.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        final view = await FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );
        transport.failSends = true;

        await expectLater(view.close(), throwsStateError);

        expect(view.pendingRequestCount, 0);
        expect(view.subscriptionCount, 0);
        await view.closed.timeout(const Duration(milliseconds: 100));
        await host.close();
      },
    );
  });
}
