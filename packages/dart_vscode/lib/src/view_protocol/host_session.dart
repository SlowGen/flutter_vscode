part of '../view_protocol.dart';

// The Host Dart side of a session: shared session machinery, the host's
// view of a live session, and an in-flight call to a Flutter View.

/// The machinery both session roles share: transport subscription and
/// lifecycle, typed-frame send, the pending-response registry, inbound
/// request dedup and cancel bookkeeping, the shared inbound-operation
/// skeleton with structured-error framing, and the idempotent
/// close/terminate scaffolds. The role adapters keep only handshake
/// direction, exposed futures, and allowlist placement.
abstract base class _ViewSessionCore {
  _ViewSessionCore(
    ViewTransport transport,
    String sessionId,
    String bootstrapNonce,
    Map<String, _HostViewOperation> operations,
  ) : _transport = transport,
      _sessionId = sessionId,
      _bootstrapNonce = bootstrapNonce,
      _operations = operations;

  final ViewTransport _transport;
  final String _sessionId;
  final String _bootstrapNonce;
  final Map<String, _HostViewOperation> _operations;

  /// Outbound calls awaiting a peer response, by request ID.
  final Map<String, Completer<Object?>> _pendingResponses = {};

  /// Inbound request IDs already accepted within this session.
  final Set<String> _seenInboundRequestIds = {};

  /// Cancel bookkeeping for inbound requests. The host role stores
  /// response-eligible IDs; the view role stores cancelled IDs.
  final Set<String> _inboundCancellationMarks = {};

  final Completer<ViewCloseReport> _closedSignal = Completer<ViewCloseReport>();

  // The session cancels its owned subscription during every terminal path.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _subscription;
  String? _activeNonce;
  var _closed = false;
  Future<void>? _closeOperation;
  Future<void>? _terminationOperation;

  /// Number of protocol transport subscriptions owned by this session.
  int get subscriptionCount => _subscription == null ? 0 : 1;

  /// Completes after all protocol state and listeners have been released.
  Future<ViewCloseReport> get closed => _closedSignal.future;

  /// Calls this role considers pending, as reported in close reports.
  int get pendingRequestCount;

  /// Dispatches one validated protocol frame for this role.
  void _onFrame(ViewProtocolFrame frame);

  /// Reacts to a frame that failed [ViewProtocolFrame.parse] for this role.
  void _onMalformedFrame(ViewProtocolException error);

  /// The role-specific receive-stream failure explanation.
  String get _receiveFailureMessage;

  /// Releases per-request state when this session becomes terminal.
  void _releaseRequestState(ViewProtocolException? terminalError);

  /// Settles the role-specific lifecycle futures during termination.
  void _resolveTerminalFutures(
    ViewProtocolException? terminalError,
    ViewCloseReport report,
  );

  /// Runs the role-specific close choreography behind [close].
  Future<void> _runClose();

  /// The duplicate-inbound-request explanation for this role.
  String get _duplicateRequestMessage;

  /// The not-allowlisted explanation for this role.
  String _operationNotAllowedMessage(String operation);

  /// The operation-failure explanation for this role.
  String _operationFailedMessage(String operation, Object error);

  /// The non-snapshot-result explanation for this role.
  String _nonSnapshotResultMessage(String operation);

  /// Marks an inbound operation as running; returns its response token.
  Object? _beginInboundOperation(String id);

  /// Marks an inbound operation as no longer running.
  void _endInboundOperation();

  /// Whether the response for [id] may still be delivered.
  bool _mayDeliverInboundResponse(String id, Object? token);

  /// Builds this role's result frame answering an inbound request.
  ViewProtocolFrame _inboundResultFrame(String id, Object? result);

  /// Builds this role's error frame answering an inbound request.
  ViewProtocolFrame _inboundErrorFrame(String id, ViewProtocolException error);

  /// Contains a failed response delivery for this role.
  Future<void> _handleResponseDeliveryFailure();

  ViewTransportLifecycle? get _transportLifecycle => switch (_transport) {
    final ViewTransportLifecycle lifecycle => lifecycle,
    _ => null,
  };

  Future<void> _sendFrame(ViewProtocolFrame frame) =>
      _transport.send(frame.toWire());

  ViewCloseReport _measureCloseReport(ViewTransportLifecycle? lifecycle) =>
      ViewCloseReport(
        pendingRequestCount: pendingRequestCount,
        subscriptionCount:
            subscriptionCount + (lifecycle?.receivingSubscriptionCount ?? 0),
      );

  void _listen() {
    _subscription = _transport.messages.listen(
      _onMessage,
      onError: _onReceiveError,
      onDone: _onReceiveDone,
    );
  }

  void _onReceiveError(Object error, StackTrace stackTrace) {
    if (!_closed) {
      _observeOptionalError(
        _terminate(
          terminalError: ViewProtocolException(
            ViewProtocolErrorCode.sessionClosed,
            _receiveFailureMessage,
            details: '$error',
          ),
        ),
      );
    }
  }

  void _onReceiveDone() {
    if (!_closed) {
      _observeOptionalError(_terminate());
    }
  }

  void _onMessage(Object? value) {
    if (_closed) {
      return;
    }
    final ViewProtocolFrame frame;
    try {
      frame = ViewProtocolFrame.parse(value);
    } on ViewProtocolException catch (error) {
      _onMalformedFrame(error);
      return;
    }
    _onFrame(frame);
  }

  /// Runs one inbound allowlisted operation and frames its response.
  Future<void> _acceptInboundCall(
    String id,
    String operationName,
    Object? arguments,
  ) async {
    if (!_seenInboundRequestIds.add(id)) {
      await _sendStructuredError(
        id,
        ViewProtocolException(
          ViewProtocolErrorCode.duplicateRequest,
          _duplicateRequestMessage,
        ),
      );
      return;
    }
    final operation = _operations[operationName];
    if (operation == null) {
      await _sendStructuredError(
        id,
        ViewProtocolException(
          ViewProtocolErrorCode.operationNotAllowed,
          _operationNotAllowedMessage(operationName),
        ),
      );
      return;
    }
    final token = _beginInboundOperation(id);
    Object? result;
    ViewProtocolException? operationError;
    try {
      try {
        result = await operation(arguments);
      } on ViewProtocolException catch (error) {
        operationError = error;
      } on Object catch (error) {
        operationError = ViewProtocolException(
          ViewProtocolErrorCode.operationFailed,
          _operationFailedMessage(operationName, error),
        );
      }
    } finally {
      _endInboundOperation();
    }
    if (!_mayDeliverInboundResponse(id, token)) {
      // Per-request disposal: a cancelled or superseded request loses
      // response eligibility, so its late result or error is never delivered.
      return;
    }
    if (operationError != null) {
      await _sendStructuredError(id, operationError);
      return;
    }
    if (!_isProtocolValue(result)) {
      await _sendStructuredError(
        id,
        ViewProtocolException(
          ViewProtocolErrorCode.operationFailed,
          _nonSnapshotResultMessage(operationName),
        ),
      );
      return;
    }
    try {
      await _sendFrame(_inboundResultFrame(id, result));
    } on Object {
      await _handleResponseDeliveryFailure();
    }
  }

  Future<void> _sendStructuredError(
    String id,
    ViewProtocolException error,
  ) async {
    try {
      await _sendFrame(_inboundErrorFrame(id, error));
    } on Object {
      await _handleResponseDeliveryFailure();
    }
  }

  /// Closes this session and releases all pending protocol state.
  Future<void> close() {
    final existing = _closeOperation;
    if (existing != null) {
      return existing;
    }
    if (_closed) {
      return _terminationOperation ?? Future.value();
    }
    final completion = Completer<void>();
    _closeOperation = completion.future;
    unawaited(
      _runClose().then(
        (_) => completion.complete(),
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<void> _terminate({ViewProtocolException? terminalError}) {
    final existing = _terminationOperation;
    if (existing != null) {
      return existing;
    }
    if (_closed) {
      return _closeOperation ?? Future.value();
    }
    final completion = Completer<void>();
    _terminationOperation = completion.future;
    unawaited(
      _runTerminate(terminalError).then(
        (_) => completion.complete(),
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<void> _runTerminate(ViewProtocolException? terminalError) async {
    _closed = true;
    _releaseRequestState(terminalError);
    final subscription = _subscription;
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    try {
      await subscription?.cancel();
    } on Object catch (error, stackTrace) {
      cancellationError = error;
      cancellationStackTrace = stackTrace;
    } finally {
      _subscription = null;
    }
    final transportLifecycle = _transportLifecycle;
    try {
      await transportLifecycle?.closeReceiving();
    } on Object catch (error, stackTrace) {
      cancellationError ??= error;
      cancellationStackTrace ??= stackTrace;
    } finally {
      _resolveTerminalFutures(
        terminalError,
        _measureCloseReport(transportLifecycle),
      );
    }
    if (cancellationError != null) {
      Error.throwWithStackTrace(
        cancellationError,
        cancellationStackTrace!,
      );
    }
  }
}

/// The Host Dart side of one version-1 Flutter View session.
final class HostViewSession extends _ViewSessionCore {
  /// Starts accepting a Flutter View on [transport].
  factory HostViewSession.connect({
    required ViewTransport transport,
    required String sessionId,
    required String bootstrapNonce,
    Iterable<ViewOperationBinding> operations = const [],
  }) {
    _requireNonEmptyProtocolIdentifier(sessionId, 'sessionId');
    _requireNonEmptyProtocolIdentifier(bootstrapNonce, 'bootstrapNonce');
    final handlers = <String, _HostViewOperation>{};
    for (final operation in operations) {
      if (handlers.containsKey(operation._name)) {
        throw ArgumentError.value(
          operation._name,
          'operations',
          'Host Dart operation names must be unique; '
              '"${operation._name}" was bound more than once.',
        );
      }
      handlers[operation._name] = operation._handler;
    }
    final session = HostViewSession._(
      transport,
      sessionId,
      bootstrapNonce,
      Map.unmodifiable(handlers),
    );
    return session.._listen();
  }

  HostViewSession._(
    super.transport,
    super.sessionId,
    super.bootstrapNonce,
    super.operations,
  ) {
    _observeOptionalError(_ready.future);
    _observeOptionalError(_rendered.future);
    _observeOptionalError(_closeReport.future);
  }

  final Completer<void> _ready = Completer<void>();
  final Completer<Object?> _rendered = Completer<Object?>();
  final Completer<ViewCloseReport> _closeReport = Completer<ViewCloseReport>();
  var _nextHostCallId = 0;
  var _inFlightOperationCount = 0;
  var _generation = 0;

  /// Completes after the versioned session/nonce handshake succeeds.
  Future<void> get ready => _ready.future;

  /// Completes with the first value the Flutter View reports as rendered.
  Future<Object?> get rendered => _rendered.future;

  /// Number of calls whose Host Dart operations have not completed.
  @override
  int get pendingRequestCount => _inFlightOperationCount;

  /// Number of host-initiated calls waiting for a Flutter View result.
  int get pendingHostCallCount => _pendingResponses.length;

  @override
  String get _receiveFailureMessage => 'The Host receive stream failed.';

  @override
  void _onMalformedFrame(ViewProtocolException error) {
    // The Host is the session authority: frames that do not parse are
    // ignored fail-closed rather than terminating the session.
  }

  @override
  void _onFrame(ViewProtocolFrame frame) {
    switch (frame) {
      case ViewReadyFrame():
        _observeOptionalError(_acceptReady(frame));
      case ViewCallFrame():
        _observeOptionalError(_acceptCall(frame));
      case ViewCancelFrame():
        _acceptCancel(frame);
      case ViewHostResultFrame():
        _acceptHostResult(frame);
      case ViewHostErrorFrame():
        _acceptHostError(frame);
      case ViewRenderedFrame():
        _acceptRendered(frame);
      case ViewClosingFrame():
        _acceptClosing(frame);
      default:
        // Other kinds are not host-bound; ignore them fail-closed.
        break;
    }
  }

  bool _isActiveFrame(ViewProtocolFrame frame) =>
      frame.isActive(session: _sessionId, nonce: _activeNonce);

  void _acceptCancel(ViewCancelFrame frame) {
    if (!_isActiveFrame(frame)) {
      return;
    }
    // Per-request disposal: a cancelled view call loses response
    // eligibility, so its late result or error is never delivered.
    _inboundCancellationMarks.remove(frame.id);
  }

  void _acceptHostResult(ViewHostResultFrame frame) {
    if (!_isActiveFrame(frame)) {
      return;
    }
    _pendingResponses.remove(frame.id)?.complete(frame.result);
  }

  void _acceptHostError(ViewHostErrorFrame frame) {
    if (!_isActiveFrame(frame)) {
      return;
    }
    _pendingResponses.remove(frame.id)?.completeError(frame.error);
  }

  /// Calls a Flutter View-bound [operation] and awaits its result.
  Future<Result> call<Request, Result>(
    ViewOperation<Request, Result> operation,
    Request arguments,
  ) => callWithHandle(operation, arguments).result;

  /// Calls a Flutter View-bound [operation], returning a cancellable
  /// handle for the in-flight request.
  HostViewCall<Result> callWithHandle<Request, Result>(
    ViewOperation<Request, Result> operation,
    Request arguments,
  ) {
    final id = 'host-request-${++_nextHostCallId}';
    final completer = Completer<Object?>();
    _observeOptionalError(completer.future);
    if (_closed || !_ready.isCompleted) {
      completer.completeError(
        ViewProtocolException(
          ViewProtocolErrorCode.sessionClosed,
          'The Host Flutter View session is not connected.',
        ),
      );
      return HostViewCall._(
        completer.future.then(operation._decodeResult),
        () {},
      );
    }
    _pendingResponses[id] = completer;
    Object? encoded;
    try {
      encoded = operation._encodeArguments(arguments);
      if (!_isProtocolValue(encoded)) {
        throw _invalidMessage(
          'Host call arguments must be a protocol-safe snapshot.',
        );
      }
    } on Object catch (error, stackTrace) {
      _pendingResponses.remove(id);
      completer.completeError(error, stackTrace);
      return HostViewCall._(
        completer.future.then(operation._decodeResult),
        () {},
      );
    }
    unawaited(
      _sendFrame(
        ViewHostCallFrame(
          session: _sessionId,
          nonce: _activeNonce!,
          id: id,
          operation: operation._name,
          arguments: encoded,
        ),
      ).catchError((Object error, StackTrace stackTrace) {
        _pendingResponses.remove(id);
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
      }),
    );
    void cancel() {
      final pending = _pendingResponses.remove(id);
      if (pending == null) {
        return;
      }
      pending.completeError(
        ViewProtocolException(
          ViewProtocolErrorCode.cancelled,
          'The host cancelled the "${operation._name}" call.',
        ),
      );
      if (!_closed) {
        unawaited(
          _sendFrame(
            ViewCancelFrame(
              session: _sessionId,
              nonce: _activeNonce!,
              id: id,
            ),
          ).catchError((Object _) {}),
        );
      }
    }

    return HostViewCall._(
      completer.future.then(operation._decodeResult),
      cancel,
    );
  }

  /// Pushes a one-way event [payload] to the Flutter View on [stream].
  Future<void> emitEvent(String stream, Object? payload) async {
    _requireNonEmptyProtocolIdentifier(stream, 'stream');
    if (_closed || !_ready.isCompleted) {
      throw ViewProtocolException(
        ViewProtocolErrorCode.sessionClosed,
        'The Host Flutter View session is not connected.',
      );
    }
    if (!_isProtocolValue(payload)) {
      throw _invalidMessage(
        'An event payload must be a protocol-safe snapshot.',
      );
    }
    await _sendFrame(
      ViewEventFrame(
        session: _sessionId,
        nonce: _activeNonce!,
        stream: stream,
        payload: _protocolSnapshot(payload),
      ),
    );
  }

  void _acceptRendered(ViewRenderedFrame frame) {
    if (!_isActiveFrame(frame) || _rendered.isCompleted) {
      return;
    }
    _rendered.complete(frame.value);
  }

  void _acceptClosing(ViewClosingFrame frame) {
    if (!_isActiveFrame(frame)) {
      return;
    }
    if (!_closeReport.isCompleted) {
      _closeReport.complete(frame.report);
    }
    _observeOptionalError(_terminate());
  }

  Future<void> _acceptReady(ViewReadyFrame frame) async {
    if (!frame.isActive(session: _sessionId, nonce: _bootstrapNonce)) {
      return;
    }
    final previouslyAdvertisedNonce = _activeNonce;
    if (previouslyAdvertisedNonce != null) {
      _generation += 1;
      _inboundCancellationMarks.clear();
      _seenInboundRequestIds.clear();
    }
    final activeNonce = _createNonce();
    _activeNonce = activeNonce;
    try {
      await _sendFrame(
        ViewReadyAckFrame(
          session: _sessionId,
          nonce: _bootstrapNonce,
          activeNonce: activeNonce,
        ),
      );
    } on Object {
      if (_activeNonce == activeNonce) {
        _activeNonce = previouslyAdvertisedNonce;
      }
      await _closeAfterDeliveryFailure();
      return;
    }
    if (!_closed && _activeNonce == activeNonce && !_ready.isCompleted) {
      _ready.complete();
    }
  }

  Future<void> _acceptCall(ViewCallFrame frame) async {
    if (!_isActiveFrame(frame)) {
      return;
    }
    await _acceptInboundCall(frame.id, frame.operation, frame.arguments);
  }

  @override
  String get _duplicateRequestMessage =>
      'A request ID may be used only once in a Flutter View session.';

  @override
  String _operationNotAllowedMessage(String operation) =>
      'Host Dart does not allow the "$operation" operation.';

  @override
  String _operationFailedMessage(String operation, Object error) =>
      'Host Dart operation "$operation" failed: $error';

  @override
  String _nonSnapshotResultMessage(String operation) =>
      'Host Dart operation "$operation" did not return '
      'a protocol-safe snapshot.';

  @override
  Object? _beginInboundOperation(String id) {
    final generation = _generation;
    _inboundCancellationMarks.add(id);
    _inFlightOperationCount += 1;
    return generation;
  }

  @override
  void _endInboundOperation() {
    _inFlightOperationCount -= 1;
  }

  @override
  bool _mayDeliverInboundResponse(String id, Object? token) =>
      !_closed && token == _generation && _inboundCancellationMarks.remove(id);

  @override
  ViewProtocolFrame _inboundResultFrame(String id, Object? result) =>
      ViewResultFrame(
        session: _sessionId,
        nonce: _activeNonce!,
        id: id,
        result: result,
      );

  @override
  ViewProtocolFrame _inboundErrorFrame(
    String id,
    ViewProtocolException error,
  ) => ViewErrorFrame(
    session: _sessionId,
    nonce: _activeNonce!,
    id: id,
    error: error,
  );

  @override
  Future<void> _handleResponseDeliveryFailure() => _closeAfterDeliveryFailure();

  Future<void> _closeAfterDeliveryFailure() async {
    try {
      await close();
    } on Object {
      // close() always runs terminal cleanup, even when closing delivery fails.
    }
  }

  @override
  Future<void> _runClose() async {
    final nonce = _activeNonce ?? _bootstrapNonce;
    Object? cancellationError;
    StackTrace? cancellationStackTrace;
    try {
      await _terminate();
    } on Object catch (error, stackTrace) {
      cancellationError = error;
      cancellationStackTrace = stackTrace;
    }
    final report = _measureCloseReport(_transportLifecycle);
    Object? deliveryError;
    StackTrace? deliveryStackTrace;
    try {
      await _sendFrame(
        ViewClosingFrame(session: _sessionId, nonce: nonce, report: report),
      );
    } on Object catch (error, stackTrace) {
      deliveryError = error;
      deliveryStackTrace = stackTrace;
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

  /// Requests orderly Flutter View shutdown and returns its final counts.
  Future<ViewCloseReport> shutdown() async {
    if (_closed) {
      return _closeReport.future;
    }
    final nonce = _activeNonce;
    if (nonce == null) {
      return Future.error(
        ViewProtocolException(
          ViewProtocolErrorCode.sessionClosed,
          'Cannot shut down a Flutter View before it connects.',
        ),
      );
    }
    try {
      await _sendFrame(ViewShutdownFrame(session: _sessionId, nonce: nonce));
    } on Object catch (error, stackTrace) {
      try {
        await _terminate();
      } on Object {
        // Preserve the first failure: shutdown delivery was rejected.
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
    return _closeReport.future;
  }

  @override
  void _releaseRequestState(ViewProtocolException? terminalError) {
    _generation += 1;
    _inboundCancellationMarks.clear();
    _seenInboundRequestIds.clear();
  }

  @override
  void _resolveTerminalFutures(
    ViewProtocolException? terminalError,
    ViewCloseReport report,
  ) {
    if (!_ready.isCompleted) {
      _ready.completeError(
        terminalError ??
            ViewProtocolException(
              ViewProtocolErrorCode.sessionClosed,
              'The Host Flutter View session closed before the view was '
              'ready.',
            ),
      );
    }
    if (!_rendered.isCompleted) {
      _rendered.completeError(
        terminalError ??
            ViewProtocolException(
              ViewProtocolErrorCode.sessionClosed,
              'The Host Flutter View session closed before the view '
              'rendered.',
            ),
      );
    }
    if (!_closeReport.isCompleted) {
      _closeReport.completeError(
        terminalError ??
            ViewProtocolException(
              ViewProtocolErrorCode.sessionClosed,
              'The Host Flutter View session closed before orderly shutdown '
              'completed.',
            ),
      );
    }
    if (!_closedSignal.isCompleted) {
      _closedSignal.complete(report);
    }
  }
}

/// One cancellable host-initiated call to a Flutter View operation.
final class HostViewCall<Result> {
  HostViewCall._(this.result, this._cancel);

  /// Completes with the operation result, a structured error, or
  /// [ViewProtocolErrorCode.cancelled].
  final Future<Result> result;

  final void Function() _cancel;

  /// Cancels the in-flight call; a late peer response is discarded.
  void cancel() => _cancel();
}
