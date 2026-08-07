import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dart_vscode/view_protocol.dart';
import 'package:test/test.dart';

import 'support/repository.dart';

/// The wire maps below are the version-2 protocol schema, one per kind,
/// written in the exact key order the runtime emits.
const Map<String, Map<String, Object?>> _canonicalFrames = {
  'ready': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'ready',
    'session': 'session-1',
    'nonce': 'bootstrap-1',
  },
  'readyAck': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'readyAck',
    'session': 'session-1',
    'nonce': 'bootstrap-1',
    'activeNonce': 'active-1',
  },
  'call': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'call',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'request-1',
    'operation': 'fixture.echo',
    'arguments': {'key': 'value'},
  },
  'result': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'result',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'request-1',
    'result': ['a', 1, true, null],
  },
  'rendered': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'rendered',
    'session': 'session-1',
    'nonce': 'active-1',
    'value': {'text': 'hello'},
  },
  'error': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'error',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'request-1',
    'error': {
      'code': 'operation_failed',
      'message': 'The operation failed.',
      'details': {'cause': 'offline'},
    },
  },
  'hostCall': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'hostCall',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'host-request-1',
    'operation': 'view.echo',
    'arguments': null,
  },
  'hostResult': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'hostResult',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'host-request-1',
    'result': 'ok',
  },
  'hostError': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'hostError',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'host-request-1',
    'error': {
      'code': 'cancelled',
      'message': 'The call was cancelled.',
      'details': null,
    },
  },
  'cancel': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'cancel',
    'session': 'session-1',
    'nonce': 'active-1',
    'id': 'host-request-1',
  },
  'event': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'event',
    'session': 'session-1',
    'nonce': 'active-1',
    'stream': 'coverage',
    'payload': {'run': 1},
  },
  'shutdown': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'shutdown',
    'session': 'session-1',
    'nonce': 'active-1',
  },
  'closing': {
    'protocol': 'flutter-vscode.view',
    'version': 2,
    'kind': 'closing',
    'session': 'session-1',
    'nonce': 'active-1',
    'report': {
      'pendingRequestCount': 2,
      'subscriptionCount': 1,
    },
  },
};

Matcher _throwsProtocolError(ViewProtocolErrorCode code, String message) {
  return throwsA(
    isA<ViewProtocolException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.message, 'message', message),
  );
}

void main() {
  group('typed protocol frames', () {
    test('every kind parses to its own type and round-trips its wire map', () {
      const expectedTypes = <String, Type>{
        'ready': ViewReadyFrame,
        'readyAck': ViewReadyAckFrame,
        'call': ViewCallFrame,
        'result': ViewResultFrame,
        'rendered': ViewRenderedFrame,
        'error': ViewErrorFrame,
        'hostCall': ViewHostCallFrame,
        'hostResult': ViewHostResultFrame,
        'hostError': ViewHostErrorFrame,
        'cancel': ViewCancelFrame,
        'event': ViewEventFrame,
        'shutdown': ViewShutdownFrame,
        'closing': ViewClosingFrame,
      };
      for (final entry in _canonicalFrames.entries) {
        final frame = ViewProtocolFrame.parse(entry.value);

        expect(frame.runtimeType, expectedTypes[entry.key], reason: entry.key);
        expect(frame.kind, entry.key);
        expect(frame.session, 'session-1');
        expect(frame.toWire(), entry.value, reason: entry.key);
        expect(
          jsonEncode(frame.toWire()),
          jsonEncode(entry.value),
          reason: '${entry.key} must serialize with the exact wire key order',
        );
      }
    });

    test('typed fields expose the validated kind-specific payloads', () {
      final call =
          ViewProtocolFrame.parse(_canonicalFrames['call']) as ViewCallFrame;
      expect(call.id, 'request-1');
      expect(call.operation, 'fixture.echo');
      expect(call.arguments, {'key': 'value'});

      final readyAck =
          ViewProtocolFrame.parse(_canonicalFrames['readyAck'])
              as ViewReadyAckFrame;
      expect(readyAck.activeNonce, 'active-1');

      final error =
          ViewProtocolFrame.parse(_canonicalFrames['error']) as ViewErrorFrame;
      expect(error.id, 'request-1');
      expect(error.error.code, ViewProtocolErrorCode.operationFailed);
      expect(error.error.message, 'The operation failed.');
      expect(error.error.details, {'cause': 'offline'});

      final closing =
          ViewProtocolFrame.parse(_canonicalFrames['closing'])
              as ViewClosingFrame;
      expect(closing.report.pendingRequestCount, 2);
      expect(closing.report.subscriptionCount, 1);

      final event =
          ViewProtocolFrame.parse(_canonicalFrames['event']) as ViewEventFrame;
      expect(event.stream, 'coverage');
      expect(event.payload, {'run': 1});
    });

    test('rejects a frame that is not a string-keyed map', () {
      for (final value in [null, 'frame', 7, <Object?>[]]) {
        expect(
          () => ViewProtocolFrame.parse(value),
          _throwsProtocolError(
            ViewProtocolErrorCode.invalidMessage,
            'The protocol frame must be a string-keyed map.',
          ),
        );
      }
      expect(
        () => ViewProtocolFrame.parse({1: 'one'}),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The protocol frame must be a string-keyed map.',
        ),
      );
    });

    test('rejects a missing or foreign protocol marker', () {
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['ready']!,
          'protocol': 'another.protocol',
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The protocol marker is missing or invalid.',
        ),
      );
    });

    test('rejects a non-integer protocol version', () {
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['ready']!,
          'version': '2',
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The protocol version must be an integer.',
        ),
      );
    });

    test('rejects an unsupported protocol version', () {
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['ready']!,
          'version': 3,
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.unsupportedVersion,
          'The peer selected an unsupported Flutter View protocol version.',
        ),
      );
    });

    test('rejects a non-string or unknown frame kind', () {
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['ready']!,
          'kind': 7,
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The protocol frame kind must be a string.',
        ),
      );
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['ready']!,
          'kind': 'bogus',
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The protocol frame kind "bogus" is unknown.',
        ),
      );
    });

    test('rejects any frame outside its exact key schema', () {
      for (final entry in _canonicalFrames.entries) {
        expect(
          () => ViewProtocolFrame.parse({
            ...entry.value,
            'unexpected': true,
          }),
          _throwsProtocolError(
            ViewProtocolErrorCode.invalidMessage,
            'The "${entry.key}" frame does not match its exact schema.',
          ),
          reason: '${entry.key} with an extra key',
        );

        final missingOne = {...entry.value}..remove('nonce');
        expect(
          () => ViewProtocolFrame.parse(missingOne),
          _throwsProtocolError(
            ViewProtocolErrorCode.invalidMessage,
            'The "${entry.key}" frame does not match its exact schema.',
          ),
          reason: '${entry.key} with a missing key',
        );
      }
    });

    test('rejects empty session or nonce values on every kind', () {
      for (final entry in _canonicalFrames.entries) {
        expect(
          () => ViewProtocolFrame.parse({...entry.value, 'session': ''}),
          _throwsProtocolError(
            ViewProtocolErrorCode.invalidMessage,
            'Session and nonce values must be non-empty strings.',
          ),
          reason: '${entry.key} with an empty session',
        );
        expect(
          () => ViewProtocolFrame.parse({...entry.value, 'nonce': ''}),
          _throwsProtocolError(
            ViewProtocolErrorCode.invalidMessage,
            'Session and nonce values must be non-empty strings.',
          ),
          reason: '${entry.key} with an empty nonce',
        );
      }
    });

    test('rejects kind-specific field violations with the pinned messages', () {
      final violations = <String, (Map<String, Object?>, String)>{
        'readyAck activeNonce': (
          {..._canonicalFrames['readyAck']!, 'activeNonce': ''},
          'The active nonce must be a non-empty string.',
        ),
        'call id': (
          {..._canonicalFrames['call']!, 'id': ''},
          'The call frame contains invalid fields.',
        ),
        'call operation': (
          {..._canonicalFrames['call']!, 'operation': ''},
          'The call frame contains invalid fields.',
        ),
        'call arguments': (
          {..._canonicalFrames['call']!, 'arguments': double.infinity},
          'The call frame contains invalid fields.',
        ),
        'result id': (
          {..._canonicalFrames['result']!, 'id': 7},
          'The result frame contains invalid fields.',
        ),
        'result value': (
          {..._canonicalFrames['result']!, 'result': double.nan},
          'The result frame contains invalid fields.',
        ),
        'rendered value': (
          {..._canonicalFrames['rendered']!, 'value': double.nan},
          'The rendered frame value is invalid.',
        ),
        'error id': (
          {..._canonicalFrames['error']!, 'id': ''},
          'The error frame request ID is invalid.',
        ),
        'hostCall id': (
          {..._canonicalFrames['hostCall']!, 'id': ''},
          'The hostCall frame contains invalid fields.',
        ),
        'hostCall operation': (
          {..._canonicalFrames['hostCall']!, 'operation': 7},
          'The hostCall frame contains invalid fields.',
        ),
        'hostResult id': (
          {..._canonicalFrames['hostResult']!, 'id': 7},
          'The hostResult frame contains invalid fields.',
        ),
        'hostError id': (
          {..._canonicalFrames['hostError']!, 'id': ''},
          'The hostError frame request ID is invalid.',
        ),
        'cancel id': (
          {..._canonicalFrames['cancel']!, 'id': ''},
          'The cancel frame request ID is invalid.',
        ),
        'event stream': (
          {..._canonicalFrames['event']!, 'stream': ''},
          'The event frame contains invalid fields.',
        ),
        'event payload': (
          {..._canonicalFrames['event']!, 'payload': double.nan},
          'The event frame contains invalid fields.',
        ),
      };
      for (final entry in violations.entries) {
        final (frame, message) = entry.value;
        expect(
          () => ViewProtocolFrame.parse(frame),
          _throwsProtocolError(ViewProtocolErrorCode.invalidMessage, message),
          reason: entry.key,
        );
      }
    });

    test('rejects malformed structured error payloads', () {
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['error']!,
          'error': 'broken',
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The structured error must be a string-keyed map.',
        ),
      );
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['error']!,
          'error': {'code': 'operation_failed', 'message': 'It failed.'},
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The structured error does not match its schema.',
        ),
      );
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['hostError']!,
          'error': {
            'code': 'bogus_code',
            'message': 'It failed.',
            'details': null,
          },
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The structured error code "bogus_code" is unknown.',
        ),
      );
    });

    test('rejects malformed close reports', () {
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['closing']!,
          'report': 'broken',
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The close report must be a string-keyed map.',
        ),
      );
      expect(
        () => ViewProtocolFrame.parse({
          ..._canonicalFrames['closing']!,
          'report': {'pendingRequestCount': -1, 'subscriptionCount': 0},
        }),
        _throwsProtocolError(
          ViewProtocolErrorCode.invalidMessage,
          'The close report does not match its exact schema.',
        ),
      );
    });

    test('the active-frame predicate matches session and phase nonce', () {
      final frame = ViewProtocolFrame.parse(_canonicalFrames['call']);

      expect(frame.isActive(session: 'session-1', nonce: 'active-1'), isTrue);
      expect(frame.isActive(session: 'session-2', nonce: 'active-1'), isFalse);
      expect(frame.isActive(session: 'session-1', nonce: 'active-2'), isFalse);
      expect(frame.isActive(session: 'session-1', nonce: null), isFalse);
    });
  });

  group('shared session core', () {
    test(
      'a duplicate inbound host-call ID is refused through the core',
      () async {
        final transport = _ScriptedViewTransport();
        addTearDown(transport.close);
        final operation = ViewOperation<Object?, Object?>(
          name: 'view.echo',
          encodeArguments: (value) => value,
          decodeArguments: (value) => value,
          encodeResult: (value) => value,
          decodeResult: (value) => value,
        );
        var invocationCount = 0;
        final connection = FlutterViewSession.connect(
          transport: transport,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [
            operation.bind((_) {
              invocationCount += 1;
              return 'ok';
            }),
          ],
        );
        transport.deliver(_canonicalFrames['readyAck']);
        final view = await connection;

        transport
          ..deliver(_canonicalFrames['hostCall'])
          ..deliver(_canonicalFrames['hostCall']);
        await pumpEventQueue();

        expect(invocationCount, 1);
        final results = transport.sent.where(
          (frame) => frame['kind'] == 'hostResult',
        );
        expect(results, hasLength(1));
        expect(results.single['id'], 'host-request-1');
        expect(results.single['result'], 'ok');
        final errors = transport.sent.where(
          (frame) => frame['kind'] == 'hostError',
        );
        expect(errors, hasLength(1));
        final structuredError =
            (errors.single['error']! as Map<Object?, Object?>)
                .cast<String, Object?>();
        expect(
          structuredError['code'],
          ViewProtocolErrorCode.duplicateRequest.wireName,
        );
        expect(
          structuredError['message'],
          'A host request ID may be used only once in a session.',
        );
        await view.close();
      },
    );
  });

  group('wire schema locality', () {
    test('envelope key literals appear only in the frames part', () {
      // The frame module is a file now, not a region between comment
      // markers. A file boundary is checkable by anyone reading the tree;
      // a marker was a promise that the next edit could quietly break.
      const protocolRoot = 'packages/dart_vscode/lib/src';
      const framesPart = '$protocolRoot/view_protocol/frames.dart';
      final everythingElse = [
        '$protocolRoot/view_protocol.dart',
        '$protocolRoot/view_protocol/host_session.dart',
        '$protocolRoot/view_protocol/view_session.dart',
      ];

      expect(File(repoPath(framesPart)).existsSync(), isTrue);

      const wireLiterals = [
        "'protocol'",
        "'version'",
        "'kind'",
        "'session'",
        "'nonce'",
        "'flutter-vscode.view'",
      ];
      final frames = File(repoPath(framesPart)).readAsStringSync();
      for (final literal in wireLiterals) {
        expect(
          frames.contains(literal),
          isTrue,
          reason: 'the frames part is where $literal belongs',
        );
      }
      for (final path in everythingElse) {
        final source = File(repoPath(path)).readAsStringSync();
        for (final literal in wireLiterals) {
          expect(
            source.contains(literal),
            isFalse,
            reason:
                '$path must not read or write the $literal wire key; '
                'that belongs to the frames part alone',
          );
        }
      }
    });
  });
}

final class _ScriptedViewTransport implements ViewTransport {
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast(sync: true);

  /// Outbound frames, snapshotted the way a JSON transport would carry them.
  final List<Map<String, Object?>> sent = [];

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> send(Object? message) {
    sent.add(
      (jsonDecode(jsonEncode(message)) as Map<Object?, Object?>)
          .cast<String, Object?>(),
    );
    return Future.value();
  }

  void deliver(Object? message) => _messages.add(message);

  Future<void> close() => _messages.close();
}
