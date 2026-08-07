part of '../view_protocol.dart';

// Wire keys are read and written here and nowhere else: one file is a
// boundary a reviewer can check, where a comment marker was only a promise.

// === View protocol frames: the only region that reads or writes wire keys ===

const String _protocolMarker = 'flutter-vscode.view';
const int _protocolVersion = 2;

/// One version-2 Host/Flutter View protocol frame.
///
/// This sealed hierarchy owns the wire schema. [parse] is the single place
/// the exact per-kind schema is validated, and [toWire] is the single place
/// wire maps are produced, so envelope and payload keys are written in one
/// module. Sessions dispatch on the typed frames and never touch wire keys.
sealed class ViewProtocolFrame {
  ViewProtocolFrame({required this.session, required this.nonce});

  /// Parses and validates [value] as the exact schema of its declared kind.
  ///
  /// Throws a [ViewProtocolException] with
  /// [ViewProtocolErrorCode.invalidMessage] for any schema violation and
  /// [ViewProtocolErrorCode.unsupportedVersion] for a foreign version.
  static ViewProtocolFrame parse(Object? value) {
    if (value is! Map<Object?, Object?> ||
        value.keys.any((key) => key is! String)) {
      throw _invalidMessage('The protocol frame must be a string-keyed map.');
    }
    final message = value.cast<String, Object?>();
    if (message['protocol'] != _protocolMarker) {
      throw _invalidMessage('The protocol marker is missing or invalid.');
    }
    final version = message['version'];
    if (version is! int) {
      throw _invalidMessage('The protocol version must be an integer.');
    }
    if (version != _protocolVersion) {
      throw ViewProtocolException(
        ViewProtocolErrorCode.unsupportedVersion,
        'The peer selected an unsupported Flutter View protocol version.',
      );
    }
    final kind = message['kind'];
    if (kind is! String) {
      throw _invalidMessage('The protocol frame kind must be a string.');
    }
    const envelopeKeys = {'protocol', 'version', 'kind', 'session', 'nonce'};
    final expectedKeys = switch (kind) {
      'ready' || 'shutdown' => envelopeKeys,
      'readyAck' => const {...envelopeKeys, 'activeNonce'},
      'call' || 'hostCall' => const {
        ...envelopeKeys,
        'id',
        'operation',
        'arguments',
      },
      'result' || 'hostResult' => const {...envelopeKeys, 'id', 'result'},
      'rendered' => const {...envelopeKeys, 'value'},
      'error' || 'hostError' => const {...envelopeKeys, 'id', 'error'},
      'cancel' => const {...envelopeKeys, 'id'},
      'event' => const {...envelopeKeys, 'stream', 'payload'},
      'closing' => const {...envelopeKeys, 'report'},
      _ => throw _invalidMessage('The protocol frame kind "$kind" is unknown.'),
    };
    final presentKeys = message.keys.toSet();
    if (presentKeys.difference(expectedKeys).isNotEmpty ||
        expectedKeys.difference(presentKeys).isNotEmpty) {
      throw _invalidMessage(
        'The "$kind" frame does not match its exact schema.',
      );
    }
    if (!_isNonEmptyString(message['session']) ||
        !_isNonEmptyString(message['nonce'])) {
      throw _invalidMessage(
        'Session and nonce values must be non-empty strings.',
      );
    }
    final session = message['session']! as String;
    final nonce = message['nonce']! as String;
    switch (kind) {
      case 'ready':
        return ViewReadyFrame(session: session, nonce: nonce);
      case 'readyAck':
        if (!_isNonEmptyString(message['activeNonce'])) {
          throw _invalidMessage('The active nonce must be a non-empty string.');
        }
        return ViewReadyAckFrame(
          session: session,
          nonce: nonce,
          activeNonce: message['activeNonce']! as String,
        );
      case 'call':
        if (!_isNonEmptyString(message['id']) ||
            !_isNonEmptyString(message['operation']) ||
            !_isProtocolValue(message['arguments'])) {
          throw _invalidMessage('The call frame contains invalid fields.');
        }
        return ViewCallFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
          operation: message['operation']! as String,
          arguments: message['arguments'],
        );
      case 'hostCall':
        if (!_isNonEmptyString(message['id']) ||
            !_isNonEmptyString(message['operation']) ||
            !_isProtocolValue(message['arguments'])) {
          throw _invalidMessage('The hostCall frame contains invalid fields.');
        }
        return ViewHostCallFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
          operation: message['operation']! as String,
          arguments: message['arguments'],
        );
      case 'result':
        if (!_isNonEmptyString(message['id']) ||
            !_isProtocolValue(message['result'])) {
          throw _invalidMessage('The result frame contains invalid fields.');
        }
        return ViewResultFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
          result: message['result'],
        );
      case 'hostResult':
        if (!_isNonEmptyString(message['id']) ||
            !_isProtocolValue(message['result'])) {
          throw _invalidMessage(
            'The hostResult frame contains invalid fields.',
          );
        }
        return ViewHostResultFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
          result: message['result'],
        );
      case 'rendered':
        if (!_isProtocolValue(message['value'])) {
          throw _invalidMessage('The rendered frame value is invalid.');
        }
        return ViewRenderedFrame(
          session: session,
          nonce: nonce,
          value: message['value'],
        );
      case 'error':
        if (!_isNonEmptyString(message['id'])) {
          throw _invalidMessage('The error frame request ID is invalid.');
        }
        return ViewErrorFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
          error: _errorFromFrame(message),
        );
      case 'hostError':
        if (!_isNonEmptyString(message['id'])) {
          throw _invalidMessage('The hostError frame request ID is invalid.');
        }
        return ViewHostErrorFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
          error: _errorFromFrame(message),
        );
      case 'cancel':
        if (!_isNonEmptyString(message['id'])) {
          throw _invalidMessage('The cancel frame request ID is invalid.');
        }
        return ViewCancelFrame(
          session: session,
          nonce: nonce,
          id: message['id']! as String,
        );
      case 'event':
        if (!_isNonEmptyString(message['stream']) ||
            !_isProtocolValue(message['payload'])) {
          throw _invalidMessage('The event frame contains invalid fields.');
        }
        return ViewEventFrame(
          session: session,
          nonce: nonce,
          stream: message['stream']! as String,
          payload: message['payload'],
        );
      case 'shutdown':
        return ViewShutdownFrame(session: session, nonce: nonce);
      case 'closing':
        return ViewClosingFrame(
          session: session,
          nonce: nonce,
          report: _closeReportFromFrame(message),
        );
    }
    // Unreachable: the exact-schema switch already rejected unknown kinds.
    throw _invalidMessage('The protocol frame kind "$kind" is unknown.');
  }

  /// The session identity this frame belongs to.
  final String session;

  /// The bootstrap or active nonce naming the session phase.
  final String nonce;

  /// The stable wire kind discriminator.
  String get kind;

  /// Whether this frame is active for [session] in the phase named [nonce].
  ///
  /// This is the active-frame predicate both session roles share: [parse]
  /// already proved the protocol marker and version, so the session identity
  /// and phase nonce complete the four-field check.
  bool isActive({required String session, required String? nonce}) =>
      this.session == session && this.nonce == nonce;

  /// Serializes this frame as its exact wire map, in stable key order.
  Map<String, Object?> toWire() => {
    'protocol': _protocolMarker,
    'version': _protocolVersion,
    'kind': kind,
    'session': session,
    'nonce': nonce,
    ..._payloadEntries(),
  };

  /// Kind-specific wire fields, in their stable wire order.
  Map<String, Object?> _payloadEntries();
}

/// A Flutter View announces itself on the bootstrap nonce.
final class ViewReadyFrame extends ViewProtocolFrame {
  /// Creates a `ready` frame.
  ViewReadyFrame({required super.session, required super.nonce});

  @override
  String get kind => 'ready';

  @override
  Map<String, Object?> _payloadEntries() => const {};
}

/// Host Dart accepts a handshake and advertises the active nonce.
final class ViewReadyAckFrame extends ViewProtocolFrame {
  /// Creates a `readyAck` frame.
  ViewReadyAckFrame({
    required super.session,
    required super.nonce,
    required this.activeNonce,
  });

  /// The nonce all subsequent frames of this session phase must carry.
  final String activeNonce;

  @override
  String get kind => 'readyAck';

  @override
  Map<String, Object?> _payloadEntries() => {'activeNonce': activeNonce};
}

/// A Flutter View calls an allowlisted Host Dart operation.
final class ViewCallFrame extends ViewProtocolFrame {
  /// Creates a `call` frame.
  ViewCallFrame({
    required super.session,
    required super.nonce,
    required this.id,
    required this.operation,
    required this.arguments,
  });

  /// The session-unique request ID.
  final String id;

  /// The allowlisted operation name.
  final String operation;

  /// The protocol-safe operation arguments.
  final Object? arguments;

  @override
  String get kind => 'call';

  @override
  Map<String, Object?> _payloadEntries() => {
    'id': id,
    'operation': operation,
    'arguments': arguments,
  };
}

/// Host Dart answers a Flutter View call with its result.
final class ViewResultFrame extends ViewProtocolFrame {
  /// Creates a `result` frame.
  ViewResultFrame({
    required super.session,
    required super.nonce,
    required this.id,
    required this.result,
  });

  /// The request ID this result answers.
  final String id;

  /// The protocol-safe operation result.
  final Object? result;

  @override
  String get kind => 'result';

  @override
  Map<String, Object?> _payloadEntries() => {'id': id, 'result': result};
}

/// Host Dart answers a Flutter View call with a structured failure.
final class ViewErrorFrame extends ViewProtocolFrame {
  /// Creates an `error` frame.
  ViewErrorFrame({
    required super.session,
    required super.nonce,
    required this.id,
    required this.error,
  });

  /// The request ID this failure answers.
  final String id;

  /// The structured protocol failure.
  final ViewProtocolException error;

  @override
  String get kind => 'error';

  @override
  Map<String, Object?> _payloadEntries() => {
    'id': id,
    'error': _errorPayload(error),
  };
}

/// A Flutter View reports the protocol-safe value it currently renders.
final class ViewRenderedFrame extends ViewProtocolFrame {
  /// Creates a `rendered` frame.
  ViewRenderedFrame({
    required super.session,
    required super.nonce,
    required this.value,
  });

  /// The protocol-safe rendered value.
  final Object? value;

  @override
  String get kind => 'rendered';

  @override
  Map<String, Object?> _payloadEntries() => {'value': value};
}

/// Host Dart calls an operation the Flutter View allowlisted.
final class ViewHostCallFrame extends ViewProtocolFrame {
  /// Creates a `hostCall` frame.
  ViewHostCallFrame({
    required super.session,
    required super.nonce,
    required this.id,
    required this.operation,
    required this.arguments,
  });

  /// The session-unique host request ID.
  final String id;

  /// The allowlisted operation name.
  final String operation;

  /// The protocol-safe operation arguments.
  final Object? arguments;

  @override
  String get kind => 'hostCall';

  @override
  Map<String, Object?> _payloadEntries() => {
    'id': id,
    'operation': operation,
    'arguments': arguments,
  };
}

/// A Flutter View answers a host call with its result.
final class ViewHostResultFrame extends ViewProtocolFrame {
  /// Creates a `hostResult` frame.
  ViewHostResultFrame({
    required super.session,
    required super.nonce,
    required this.id,
    required this.result,
  });

  /// The host request ID this result answers.
  final String id;

  /// The protocol-safe operation result.
  final Object? result;

  @override
  String get kind => 'hostResult';

  @override
  Map<String, Object?> _payloadEntries() => {'id': id, 'result': result};
}

/// A Flutter View answers a host call with a structured failure.
final class ViewHostErrorFrame extends ViewProtocolFrame {
  /// Creates a `hostError` frame.
  ViewHostErrorFrame({
    required super.session,
    required super.nonce,
    required this.id,
    required this.error,
  });

  /// The host request ID this failure answers.
  final String id;

  /// The structured protocol failure.
  final ViewProtocolException error;

  @override
  String get kind => 'hostError';

  @override
  Map<String, Object?> _payloadEntries() => {
    'id': id,
    'error': _errorPayload(error),
  };
}

/// An initiator abandons its in-flight request.
final class ViewCancelFrame extends ViewProtocolFrame {
  /// Creates a `cancel` frame.
  ViewCancelFrame({
    required super.session,
    required super.nonce,
    required this.id,
  });

  /// The request ID losing response eligibility.
  final String id;

  @override
  String get kind => 'cancel';

  @override
  Map<String, Object?> _payloadEntries() => {'id': id};
}

/// Host Dart pushes a one-way event to the Flutter View.
final class ViewEventFrame extends ViewProtocolFrame {
  /// Creates an `event` frame.
  ViewEventFrame({
    required super.session,
    required super.nonce,
    required this.stream,
    required this.payload,
  });

  /// The event stream name.
  final String stream;

  /// The protocol-safe event payload.
  final Object? payload;

  @override
  String get kind => 'event';

  @override
  Map<String, Object?> _payloadEntries() => {
    'stream': stream,
    'payload': payload,
  };
}

/// Host Dart requests an orderly Flutter View shutdown.
final class ViewShutdownFrame extends ViewProtocolFrame {
  /// Creates a `shutdown` frame.
  ViewShutdownFrame({required super.session, required super.nonce});

  @override
  String get kind => 'shutdown';

  @override
  Map<String, Object?> _payloadEntries() => const {};
}

/// A closing runtime reports its final protocol resource counts.
final class ViewClosingFrame extends ViewProtocolFrame {
  /// Creates a `closing` frame.
  ViewClosingFrame({
    required super.session,
    required super.nonce,
    required this.report,
  });

  /// The measured final resource counts.
  final ViewCloseReport report;

  @override
  String get kind => 'closing';

  @override
  Map<String, Object?> _payloadEntries() => {
    'report': {
      'pendingRequestCount': report.pendingRequestCount,
      'subscriptionCount': report.subscriptionCount,
    },
  };
}

Map<String, Object?> _errorPayload(ViewProtocolException error) => {
  'code': error.code.wireName,
  'message': error.message,
  'details': error.details,
};

bool _isNonEmptyString(Object? value) => value is String && value.isNotEmpty;

ViewProtocolException _errorFromFrame(Map<String, Object?> message) {
  final value = message['error'];
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw _invalidMessage('The structured error must be a string-keyed map.');
  }
  final error = value.cast<String, Object?>();
  const expectedKeys = {'code', 'message', 'details'};
  if (error.keys.toSet().difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(error.keys.toSet()).isNotEmpty ||
      error['code'] is! String ||
      !_isNonEmptyString(error['message']) ||
      !_isProtocolValue(error['details'])) {
    throw _invalidMessage('The structured error does not match its schema.');
  }
  final codeName = error['code']! as String;
  final code = ViewProtocolErrorCode.values.where(
    (candidate) => candidate.wireName == codeName,
  );
  if (code.length != 1) {
    throw _invalidMessage('The structured error code "$codeName" is unknown.');
  }
  return ViewProtocolException(
    code.single,
    error['message']! as String,
    details: error['details'],
  );
}

ViewCloseReport _closeReportFromFrame(Map<String, Object?> message) {
  final value = message['report'];
  if (value is! Map<Object?, Object?> ||
      value.keys.any((key) => key is! String)) {
    throw _invalidMessage('The close report must be a string-keyed map.');
  }
  final report = value.cast<String, Object?>();
  const expectedKeys = {'pendingRequestCount', 'subscriptionCount'};
  final pendingRequestCount = report['pendingRequestCount'];
  final subscriptionCount = report['subscriptionCount'];
  if (report.keys.toSet().difference(expectedKeys).isNotEmpty ||
      expectedKeys.difference(report.keys.toSet()).isNotEmpty ||
      pendingRequestCount is! int ||
      pendingRequestCount < 0 ||
      subscriptionCount is! int ||
      subscriptionCount < 0) {
    throw _invalidMessage('The close report does not match its exact schema.');
  }
  return ViewCloseReport(
    pendingRequestCount: pendingRequestCount,
    subscriptionCount: subscriptionCount,
  );
}

// === End of view protocol frames ===
