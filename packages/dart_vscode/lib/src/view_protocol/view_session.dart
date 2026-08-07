part of '../view_protocol.dart';

// The Flutter View side of a session, and the in-memory transport pair the
// tests drive it with.

/// The Flutter View side of one version-2 Host Dart session.
final class FlutterViewSession extends _ViewSessionCore {
  FlutterViewSession._(
    super.transport,
    super.sessionId,
    super.bootstrapNonce,
    super.operations,
  ) {
    _observeOptionalError(_connected.future);
  }

  /// Connects to Host Dart using a bootstrap session and nonce.
  ///
  /// [operations] are the typed operations this Flutter View allows the
  /// host to call over the version-2 host-to-view direction.
  static Future<FlutterViewSession> connect({
    required ViewTransport transport,
    required String sessionId,
    required String bootstrapNonce,
    Iterable<ViewOperationBinding> operations = const [],
  }) async {
    _requireNonEmptyProtocolIdentifier(sessionId, 'sessionId');
    _requireNonEmptyProtocolIdentifier(bootstrapNonce, 'bootstrapNonce');
    final handlers = <String, _HostViewOperation>{};
    for (final operation in operations) {
      if (handlers.containsKey(operation._name)) {
        throw ArgumentError.value(
          operation._name,
          'operations',
          'Flutter View operation names must be unique; '
              '"${operation._name}" was bound more than once.',
        );
      }
      handlers[operation._name] = operation._handler;
    }
    final session = FlutterViewSession._(
      transport,
      sessionId,
      bootstrapNonce,
      Map.unmodifiable(handlers),
    ).._listen();
    try {
      await session._sendFrame(
        ViewReadyFrame(session: sessionId, nonce: bootstrapNonce),
      );
    } on Object catch (error, stackTrace) {
      try {
        await session._terminate();
      } on Object {
        // Preserve the first failure: the connection frame was not delivered.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    final connected = session._connected.future;
    await connected;
    return session;
  }

  final Completer<void> _connected = Completer<void>();
  final Map<String, StreamController<Object?>> _eventStreams = {};
  var _nextRequestId = 0;

  /// Number of calls waiting for a Host Dart result.
  @override
  int get pendingRequestCount => _pendingResponses.length;

  /// The nonce active for this session phase, once connected.
  String? get activeNonce => _activeNonce;

  @override
  String get _receiveFailureMessage =>
      'The Flutter View receive stream failed.';

  @override
  void _onMalformedFrame(ViewProtocolException error) {
    // The view fails closed: a frame that does not parse rejects the
    // connection and terminates the session.
    _observeOptionalError(_rejectConnection(error));
  }

  @override
  void _onFrame(ViewProtocolFrame frame) {
    if (frame.session != _sessionId) {
      _observeOptionalError(
        _rejectConnection(
          ViewProtocolException(
            ViewProtocolErrorCode.sessionMismatch,
            'The protocol frame belongs to another Flutter View session.',
          ),
        ),
      );
      return;
    }
    final expectedNonce = _connected.isCompleted
        ? _activeNonce
        : _bootstrapNonce;
    if (frame.nonce != expectedNonce) {
      _observeOptionalError(
        _rejectConnection(
          ViewProtocolException(
            ViewProtocolErrorCode.nonceMismatch,
            'The protocol frame nonce is not active for this session.',
          ),
        ),
      );
      return;
    }
    if (!_connected.isCompleted &&
        frame is! ViewReadyAckFrame &&
        frame is! ViewShutdownFrame &&
        frame is! ViewClosingFrame) {
      _observeOptionalError(
        _rejectConnection(
          _invalidMessage(
            'Only a ready acknowledgement or terminal frame is valid during '
            'the Flutter View handshake.',
          ),
        ),
      );
      return;
    }
    switch (frame) {
      case ViewReadyAckFrame() when frame.nonce == _bootstrapNonce:
        _activeNonce = frame.activeNonce;
        if (!_connected.isCompleted) {
          _connected.complete();
        }
      case ViewResultFrame():
        _pendingResponses.remove(frame.id)?.complete(frame.result);
      case ViewErrorFrame():
        _pendingResponses.remove(frame.id)?.completeError(frame.error);
      case ViewHostCallFrame():
        _observeOptionalError(
          _acceptInboundCall(frame.id, frame.operation, frame.arguments),
        );
      case ViewCancelFrame():
        _inboundCancellationMarks.add(frame.id);
      case ViewEventFrame():
        _eventStreams[frame.stream]?.add(frame.payload);
      case ViewShutdownFrame():
        _observeOptionalError(close());
      case ViewClosingFrame():
        _observeOptionalError(_terminate());
      default:
        // A ready acknowledgement outside the bootstrap phase is ignored.
        break;
    }
  }

  @override
  String get _duplicateRequestMessage =>
      'A host request ID may be used only once in a session.';

  @override
  String _operationNotAllowedMessage(String operation) =>
      'The Flutter View does not allow the "$operation" operation.';

  @override
  String _operationFailedMessage(String operation, Object error) =>
      'Flutter View operation "$operation" failed: $error';

  @override
  String _nonSnapshotResultMessage(String operation) =>
      'Flutter View operation "$operation" did not '
      'return a protocol-safe snapshot.';

  @override
  Object? _beginInboundOperation(String id) => null;

  @override
  void _endInboundOperation() {}

  @override
  bool _mayDeliverInboundResponse(String id, Object? token) =>
      !_closed && !_inboundCancellationMarks.remove(id);

  @override
  ViewProtocolFrame _inboundResultFrame(String id, Object? result) =>
      ViewHostResultFrame(
        session: _sessionId,
        nonce: _activeNonce!,
        id: id,
        result: result,
      );

  @override
  ViewProtocolFrame _inboundErrorFrame(
    String id,
    ViewProtocolException error,
  ) => ViewHostErrorFrame(
    session: _sessionId,
    nonce: _activeNonce!,
    id: id,
    error: error,
  );

  @override
  Future<void> _handleResponseDeliveryFailure() => _terminate();

  /// Host-pushed events for [stream], in delivery order.
  Stream<Object?> events(String stream) {
    _requireNonEmptyProtocolIdentifier(stream, 'stream');
    return _eventStreams
        .putIfAbsent(stream, StreamController<Object?>.broadcast)
        .stream;
  }

  /// This session's structural call seam; see [ViewOperationCaller]
  /// for why it is a plain function type.
  ViewOperationCaller get operationCaller =>
      (operation, arguments) => _call(operation, arguments: arguments);

  /// Calls one operation explicitly allowlisted by Host Dart.
  Future<Object?> _call(String operation, {Object? arguments}) async {
    if (_closed) {
      return Future.error(
        ViewProtocolException(
          ViewProtocolErrorCode.sessionClosed,
          'The Flutter View session is closed.',
        ),
      );
    }
    if (!_isProtocolValue(arguments)) {
      return Future.error(
        _invalidMessage(
          'Call arguments must contain only protocol-safe snapshot data.',
        ),
      );
    }
    final id = 'request-${++_nextRequestId}';
    final completer = Completer<Object?>();
    _observeOptionalError(completer.future);
    _pendingResponses[id] = completer;
    try {
      await _sendFrame(
        ViewCallFrame(
          session: _sessionId,
          nonce: _activeNonce!,
          id: id,
          operation: operation,
          arguments: arguments,
        ),
      );
    } on Object catch (error, stackTrace) {
      _pendingResponses.remove(id);
      try {
        await _terminate();
      } on Object {
        // Preserve the first failure: call delivery was rejected.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return completer.future;
  }

  /// Reports the protocol-safe value currently rendered by this Flutter View.
  Future<void> reportRendered(Object? value) async {
    if (_closed) {
      throw ViewProtocolException(
        ViewProtocolErrorCode.sessionClosed,
        'The Flutter View session is closed.',
      );
    }
    if (!_isProtocolValue(value)) {
      throw _invalidMessage(
        'A rendered value must contain only protocol-safe snapshot data.',
      );
    }
    try {
      await _sendFrame(
        ViewRenderedFrame(
          session: _sessionId,
          nonce: _activeNonce!,
          value: value,
        ),
      );
    } on Object catch (error, stackTrace) {
      try {
        await _terminate();
      } on Object {
        // Preserve the first failure: render delivery was rejected.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  @override
  Future<void> _runClose() async {
    _closed = true;
    _releaseRequestState(null);
    final subscription = _subscription;
    Object? deliveryError;
    StackTrace? deliveryStackTrace;
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    try {
      await subscription?.cancel();
    } on Object catch (error, stackTrace) {
      cancellationError = error;
      cancellationStackTrace = stackTrace;
    } finally {
      _subscription = null;
      _failConnectIfPending();
    }
    final transportLifecycle = _transportLifecycle;
    try {
      await transportLifecycle?.closeReceiving();
    } on Object catch (error, stackTrace) {
      cancellationError ??= error;
      cancellationStackTrace ??= stackTrace;
    }
    final report = _measureCloseReport(transportLifecycle);
    try {
      await _sendFrame(
        ViewClosingFrame(
          session: _sessionId,
          nonce: _activeNonce ?? _bootstrapNonce,
          report: report,
        ),
      );
    } on Object catch (error, stackTrace) {
      deliveryError = error;
      deliveryStackTrace = stackTrace;
    } finally {
      _completeClosed(report);
    }
    if (deliveryError != null) {
      Error.throwWithStackTrace(deliveryError, deliveryStackTrace!);
    }
    if (cancellationError != null) {
      Error.throwWithStackTrace(
        cancellationError,
        cancellationStackTrace!,
      );
    }
  }

  @override
  void _releaseRequestState(ViewProtocolException? terminalError) {
    for (final completer in _pendingResponses.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          terminalError ??
              ViewProtocolException(
                ViewProtocolErrorCode.sessionClosed,
                'The Flutter View session closed before the call completed.',
              ),
        );
      }
    }
    _pendingResponses.clear();
  }

  @override
  void _resolveTerminalFutures(
    ViewProtocolException? terminalError,
    ViewCloseReport report,
  ) {
    _failConnectIfPending(terminalError);
    _completeClosed(report);
  }

  void _failConnectIfPending([ViewProtocolException? terminalError]) {
    if (!_connected.isCompleted) {
      _connected.completeError(
        terminalError ??
            ViewProtocolException(
              ViewProtocolErrorCode.sessionClosed,
              'The Flutter View session closed before the handshake completed.',
            ),
      );
    }
  }

  void _completeClosed(ViewCloseReport report) {
    if (!_closedSignal.isCompleted) {
      _closedSignal.complete(report);
    }
  }

  Future<void> _rejectConnection(ViewProtocolException error) async {
    if (!_connected.isCompleted) {
      _connected.completeError(error);
    }
    await _terminate();
  }
}

final class _InMemoryViewTransport implements ViewTransport {
  const _InMemoryViewTransport(this.messages, this._send);

  @override
  final Stream<Object?> messages;

  final void Function(Object?) _send;

  @override
  Future<void> send(Object? message) {
    _send(jsonDecode(jsonEncode(message)));
    return Future.value();
  }
}

String _createNonce() {
  final random = Random.secure();
  return List.generate(
    16,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

void _requireNonEmptyProtocolIdentifier(String value, String name) {
  if (value.isEmpty) {
    throw ViewProtocolException(
      ViewProtocolErrorCode.invalidMessage,
      '$name must be a non-empty protocol identifier.',
    );
  }
}

bool _isProtocolValue(Object? value, [Set<Object>? ancestors]) {
  if (value == null || value is String || value is bool) {
    return true;
  }
  if (value is num) {
    return value.isFinite;
  }
  if (value is List<Object?>) {
    final active = ancestors ?? Set<Object>.identity();
    if (!active.add(value)) {
      return false;
    }
    final valid = value.every((item) => _isProtocolValue(item, active));
    active.remove(value);
    return valid;
  }
  if (value is Map<Object?, Object?>) {
    final active = ancestors ?? Set<Object>.identity();
    if (!active.add(value)) {
      return false;
    }
    final valid = value.entries.every(
      (entry) => entry.key is String && _isProtocolValue(entry.value, active),
    );
    active.remove(value);
    return valid;
  }
  return false;
}

Object? _protocolSnapshot(Object? value) {
  if (value is List<Object?>) {
    return List<Object?>.unmodifiable(value.map(_protocolSnapshot));
  }
  if (value is Map<Object?, Object?>) {
    return Map<String, Object?>.unmodifiable({
      for (final entry in value.entries)
        entry.key! as String: _protocolSnapshot(entry.value),
    });
  }
  return value;
}

ViewProtocolException _invalidMessage(String message) =>
    ViewProtocolException(ViewProtocolErrorCode.invalidMessage, message);

void _observeOptionalError<T>(Future<T> future) {
  // These lifecycle futures are optional signals. This listener prevents an
  // ignored signal from becoming an unhandled zone error; callers awaiting the
  // original future still receive its terminal failure.
  unawaited(
    future.then<void>(
      (_) {},
      onError: (Object error, StackTrace stackTrace) {},
    ),
  );
}
