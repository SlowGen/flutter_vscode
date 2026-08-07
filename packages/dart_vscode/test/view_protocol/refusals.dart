part of '../view_protocol_test.dart';

/// Refusals: values and bindings the protocol refuses before anything reaches the wire.
void registerViewProtocolRefusalsTests() {
  group('Host and Flutter View protocol: refusals', () {
    test('rejects an empty structured error message at construction', () {
      expect(
        () => ViewProtocolException(
          ViewProtocolErrorCode.operationFailed,
          '',
        ),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );
    });

    test('rejects unsafe structured error details at construction', () {
      expect(
        () => ViewProtocolException(
          ViewProtocolErrorCode.operationFailed,
          'The operation failed.',
          details: DateTime.utc(2026),
        ),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );
    });

    test('structured error details remain a protocol-safe snapshot', () {
      final mutableDetails = <Object?>['safe'];
      final error = ViewProtocolException(
        ViewProtocolErrorCode.operationFailed,
        'The operation failed.',
        details: mutableDetails,
      );

      mutableDetails.add(DateTime.utc(2026));

      expect(error.details, ['safe']);
    });

    test('rejects duplicate typed Host operation bindings', () {
      final operation = _snapshotOperation('fixture.readHostValue');
      final transport = InMemoryViewTransportPair();

      expect(
        () => HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind((value) => value),
            operation.bind((value) => value),
          ],
        ),
        throwsA(
          isA<ArgumentError>().having(
            (error) => error.message,
            'message',
            contains('fixture.readHostValue'),
          ),
        ),
      );
    });

    test('rejects an empty Host operation name before binding', () {
      final operation = _snapshotOperation('');

      expect(
        () => operation.bind((value) => value),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );
    });

    test('Host rejects empty session identifiers before listening', () async {
      final sessions = <HostViewSession>[];
      addTearDown(() async {
        for (final session in sessions) {
          await session.close();
        }
      });

      for (final identifiers in const [
        (sessionId: '', bootstrapNonce: 'bootstrap-1'),
        (sessionId: 'session-1', bootstrapNonce: ''),
      ]) {
        expect(
          () => sessions.add(
            HostViewSession.connect(
              transport: InMemoryViewTransportPair().host,
              sessionId: identifiers.sessionId,
              bootstrapNonce: identifiers.bootstrapNonce,
            ),
          ),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.invalidMessage,
            ),
          ),
        );
      }

      expect(sessions, isEmpty);
    });

    test(
      'Flutter View rejects empty session identifiers before sending',
      () async {
        for (final identifiers in const [
          (sessionId: '', bootstrapNonce: 'bootstrap-1'),
          (sessionId: 'session-1', bootstrapNonce: ''),
        ]) {
          final transport = _ControllableViewTransport();
          addTearDown(transport.closeMessages);

          await expectLater(
            FlutterViewSession.connect(
              transport: transport,
              sessionId: identifiers.sessionId,
              bootstrapNonce: identifiers.bootstrapNonce,
            ).timeout(const Duration(milliseconds: 100)),
            throwsA(
              isA<ViewProtocolException>().having(
                (error) => error.code,
                'code',
                ViewProtocolErrorCode.invalidMessage,
              ),
            ),
          );
          expect(transport.sent, isEmpty);
        }
      },
    );

    test('rejects an empty operation name before sending a call', () async {
      final operation = _snapshotOperation('');
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
      addTearDown(() async {
        await view.close();
        await host.closed;
      });

      await expectLater(
        operation.call(view, null).timeout(const Duration(milliseconds: 100)),
        throwsA(
          isA<ViewProtocolException>().having(
            (error) => error.code,
            'code',
            ViewProtocolErrorCode.invalidMessage,
          ),
        ),
      );

      expect(view.pendingRequestCount, 0);
      expect(host.pendingRequestCount, 0);
    });

    test(
      'rejects call arguments that are not protocol-safe snapshots',
      () async {
        final operation = _snapshotOperation('fixture.echo');
        var invocationCount = 0;
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind((value) {
              invocationCount += 1;
              return value;
            }),
          ],
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await expectLater(
          operation
              .call(view, DateTime.utc(2026))
              .timeout(const Duration(milliseconds: 100)),
          throwsA(
            isA<ViewProtocolException>().having(
              (error) => error.code,
              'code',
              ViewProtocolErrorCode.invalidMessage,
            ),
          ),
        );
        expect(invocationCount, 0);
        expect(view.pendingRequestCount, 0);
        expect(host.pendingRequestCount, 0);
        await view.close();
      },
    );

    test(
      'returns a structured failure for a non-snapshot Host Dart result',
      () async {
        final operation = _snapshotOperation('fixture.invalidResult');
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [operation.bind((_) => DateTime.utc(2026))],
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        await expectLater(
          operation.call(view, null),
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
                  contains('protocol-safe snapshot'),
                ),
          ),
        );
        expect(view.pendingRequestCount, 0);
        expect(host.pendingRequestCount, 0);
        await view.close();
      },
    );
  });
}
