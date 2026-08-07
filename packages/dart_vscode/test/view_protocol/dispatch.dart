part of '../view_protocol_test.dart';

/// Dispatch: allowlisted calls, their results, structured failures, and events.
void registerViewProtocolDispatchTests() {
  group('Host and Flutter View protocol: dispatch', () {
    test('in-memory transport snapshots outbound protocol frames', () async {
      final transport = InMemoryViewTransportPair();
      final received = <Map<String, Object?>>[];
      final subscription = transport.host.messages.listen((message) {
        received.add(
          (message! as Map<Object?, Object?>).cast<String, Object?>(),
        );
      });
      addTearDown(subscription.cancel);
      final arguments = <String, Object?>{'value': 'before'};
      final result = <String, Object?>{'value': 'before'};
      final errorDetails = <String, Object?>{'value': 'before'};
      final rendered = <String, Object?>{'value': 'before'};
      final call = <String, Object?>{
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'call',
        'session': 'session-1',
        'nonce': 'active-1',
        'id': 'request-1',
        'operation': 'fixture.echo',
        'arguments': arguments,
      };

      await transport.view.send(call);
      await transport.view.send({
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'result',
        'session': 'session-1',
        'nonce': 'active-1',
        'id': 'request-1',
        'result': result,
      });
      await transport.view.send({
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'error',
        'session': 'session-1',
        'nonce': 'active-1',
        'id': 'request-2',
        'error': {
          'code': ViewProtocolErrorCode.operationFailed.wireName,
          'message': 'The operation failed.',
          'details': errorDetails,
        },
      });
      await transport.view.send({
        'protocol': 'flutter-vscode.view',
        'version': 2,
        'kind': 'rendered',
        'session': 'session-1',
        'nonce': 'active-1',
        'value': rendered,
      });

      call['operation'] = 'mutated';
      arguments['value'] = 'after';
      result['value'] = 'after';
      errorDetails['value'] = 'after';
      rendered['value'] = 'after';

      expect(received, hasLength(4));
      expect(received[0]['operation'], 'fixture.echo');
      expect(received[0]['arguments'], {'value': 'before'});
      expect(received[1]['result'], {'value': 'before'});
      expect(
        (received[2]['error']! as Map<Object?, Object?>)['details'],
        {'value': 'before'},
      );
      expect(received[3]['value'], {'value': 'before'});
    });

    test(
      'calls an allowlisted Host operation through a typed contract',
      () async {
        final operation = ViewOperation<String, String>(
          name: 'fixture.readHostValue',
          encodeArguments: (key) => {'key': key},
          decodeArguments: (value) {
            if (value case {'key': final String key} when value.length == 1) {
              return key;
            }
            throw const FormatException('Expected exactly one string key.');
          },
          encodeResult: (value) => value,
          decodeResult: (value) {
            if (value is String) {
              return value;
            }
            throw const FormatException('Expected a string result.');
          },
        );
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind(
              (key) => key == 'greeting' ? 'hello from Host Dart' : 'unknown',
            ),
          ],
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        final result = await operation.call(view, 'greeting');

        expect(result, 'hello from Host Dart');
        await view.close();
        await host.closed;
        expect(host.subscriptionCount, 0);
      },
    );

    test('connects and completes an allowlisted call', () async {
      final operation = _snapshotOperation('fixture.readHostValue');
      final transport = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
        operations: [
          operation.bind((arguments) async {
            expect(arguments, {'key': 'greeting'});
            return 'hello from Host Dart';
          }),
        ],
      );

      final view = await FlutterViewSession.connect(
        transport: transport.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      await host.ready;
      expect(
        await operation.call(view, {'key': 'greeting'}),
        'hello from Host Dart',
      );

      await view.close();
      await host.closed;
      expect(view.pendingRequestCount, 0);
      expect(view.subscriptionCount, 0);
      expect(host.pendingRequestCount, 0);
      expect(host.subscriptionCount, 0);
    });

    test('rejects a call outside the Host Dart operation allowlist', () async {
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

      final operation = _snapshotOperation('fixture.notAllowed');
      await expectLater(
        operation.call(view, null).timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.operationNotAllowed,
          ),
        ),
      );

      await view.close();
      expect(host.pendingRequestCount, 0);
    });

    test(
      'rejects a duplicate request ID without invoking Host Dart twice',
      () async {
        final operation = _snapshotOperation('fixture.readHostValue');
        final operationResult = Completer<Object?>();
        var invocationCount = 0;
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind((_) {
              invocationCount += 1;
              return operationResult.future;
            }),
          ],
        );
        final responses = StreamIterator<Object?>(transport.view.messages);

        final readyResponse = responses.moveNext();
        await transport.view.send({
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'ready',
          'session': 'session-1',
          'nonce': 'bootstrap-1',
        });
        expect(await readyResponse, isTrue);
        final readyAck = (responses.current! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final call = {
          'protocol': 'flutter-vscode.view',
          'version': 2,
          'kind': 'call',
          'session': 'session-1',
          'nonce': readyAck['activeNonce'],
          'id': 'request-1',
          'operation': 'fixture.readHostValue',
          'arguments': null,
        };

        await transport.view.send(call);
        await transport.view.send(call);

        expect(
          await responses.moveNext().timeout(const Duration(milliseconds: 100)),
          isTrue,
        );
        final error = (responses.current! as Map<Object?, Object?>)
            .cast<String, Object?>();
        final structuredError = (error['error']! as Map<Object?, Object?>)
            .cast<String, Object?>();
        expect(error['kind'], 'error');
        expect(
          structuredError['code'],
          ViewProtocolErrorCode.duplicateRequest.wireName,
        );
        expect(invocationCount, 1);
        expect(host.pendingRequestCount, 1);

        operationResult.complete('value');
        expect(await responses.moveNext(), isTrue);
        await Future<void>.delayed(Duration.zero);
        expect(host.pendingRequestCount, 0);
        await responses.cancel();
        await host.close();
      },
    );

    test(
      'returns a structured error when a Host Dart operation fails',
      () async {
        final operation = _snapshotOperation('fixture.fail');
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind((_) => throw StateError('database offline')),
          ],
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await expectLater(
          operation.call(view, null).timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>()
                .having(
                  (error) => error.code,
                  'code',
                  ViewProtocolErrorCode.operationFailed,
                )
                .having(
                  (error) => error.message,
                  'message',
                  contains('database offline'),
                ),
          ),
        );
        expect(view.pendingRequestCount, 0);
        expect(host.pendingRequestCount, 0);
        await view.close();
      },
    );

    test(
      'async Host result delivery failure settles the call and sessions',
      () async {
        final operation = _snapshotOperation('fixture.echo');
        final pair = InMemoryViewTransportPair();
        final transport = _DeferredFailingViewTransport(pair.host, 'result');
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

        final call = operation.call(view, 'value');
        await transport.deliveryStarted;
        transport.fail(StateError('native result delivery rejected'));

        await expectLater(
          call.timeout(const Duration(milliseconds: 100)),
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

    test('reports the rendered Flutter value through a typed future', () async {
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

      await view.reportRendered({'text': 'hello from Flutter'});

      expect(
        await host.rendered,
        {'text': 'hello from Flutter'},
      );
      await view.close();
    });

    test('ignores a late result for an already completed request', () async {
      final operation = _snapshotOperation('fixture.read');
      final transport = InMemoryViewTransportPair();
      final peer = transport.host.messages.listen((rawMessage) {
        final message = (rawMessage! as Map<Object?, Object?>)
            .cast<String, Object?>();
        switch (message['kind']) {
          case 'ready':
            unawaited(
              transport.host.send({
                'protocol': 'flutter-vscode.view',
                'version': 2,
                'kind': 'readyAck',
                'session': message['session'],
                'nonce': message['nonce'],
                'activeNonce': 'active-1',
              }),
            );
          case 'call':
            final result = {
              'protocol': 'flutter-vscode.view',
              'version': 2,
              'kind': 'result',
              'session': message['session'],
              'nonce': message['nonce'],
              'id': message['id'],
              'result': 'first value',
            };
            unawaited(transport.host.send(result));
            unawaited(
              transport.host.send({...result, 'result': 'late value'}),
            );
        }
      });
      final view = await FlutterViewSession.connect(
        transport: transport.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      expect(await operation.call(view, null), 'first value');
      expect(view.pendingRequestCount, 0);
      expect(view.subscriptionCount, 1);

      await view.close();
      await peer.cancel();
    });
  });
}
