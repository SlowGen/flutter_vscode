import 'dart:async';

import 'package:dart_vscode/view_protocol.dart';
import 'package:test/test.dart';

part 'view_protocol/refusals.dart';
part 'view_protocol/handshake.dart';
part 'view_protocol/dispatch.dart';
part 'view_protocol/teardown.dart';
part 'view_protocol/v2.dart';

void main() {
  registerViewProtocolRefusalsTests();
  registerViewProtocolHandshakeTests();
  registerViewProtocolDispatchTests();
  registerViewProtocolTeardownTests();
  registerViewProtocolV2Tests();
}

ViewOperation<Object?, Object?> _snapshotOperation(String name) {
  return ViewOperation<Object?, Object?>(
    name: name,
    encodeArguments: (value) => value,
    decodeArguments: (value) => value,
    encodeResult: (value) => value,
    decodeResult: (value) => value,
  );
}

final class _SwitchableViewTransport implements ViewTransport {
  _SwitchableViewTransport(this._delegate);

  final ViewTransport _delegate;
  bool failSends = false;

  @override
  Stream<Object?> get messages => _delegate.messages;

  @override
  Future<void> send(Object? message) {
    if (failSends) {
      throw StateError('transport send failed');
    }
    return _delegate.send(message);
  }
}

final class _KindFailingViewTransport implements ViewTransport {
  _KindFailingViewTransport(this._delegate, this._failedKind);

  final ViewTransport _delegate;
  final String _failedKind;

  @override
  Stream<Object?> get messages => _delegate.messages;

  @override
  Future<void> send(Object? message) {
    if (message case <Object?, Object?>{
      'kind': final String kind,
    } when kind == _failedKind) {
      throw StateError('transport send failed for $kind');
    }
    return _delegate.send(message);
  }
}

final class _DeferredFailingViewTransport implements ViewTransport {
  _DeferredFailingViewTransport(this._delegate, this._failedKind);

  final ViewTransport _delegate;
  final String _failedKind;
  final Completer<void> _deliveryStarted = Completer<void>();
  final Completer<void> _delivery = Completer<void>();
  var _matched = false;

  Future<void> get deliveryStarted => _deliveryStarted.future;

  @override
  Stream<Object?> get messages => _delegate.messages;

  @override
  Future<void> send(Object? message) {
    if (!_matched &&
        message is Map<Object?, Object?> &&
        message['kind'] == _failedKind) {
      _matched = true;
      _deliveryStarted.complete();
      return _delivery.future;
    }
    return _delegate.send(message);
  }

  void fail(Object error) {
    _delivery.completeError(error, StackTrace.current);
  }
}

final class _CancelFailingViewTransport implements ViewTransport {
  _CancelFailingViewTransport(this._delegate) {
    _messages = StreamController<Object?>(
      sync: true,
      onListen: () {
        _delegateSubscription = _delegate.messages.listen(
          _messages.add,
          onError: _messages.addError,
          onDone: _messages.close,
        );
      },
      onCancel: () async {
        await _delegateSubscription?.cancel();
        throw StateError('transport cancellation failed');
      },
    );
  }

  final ViewTransport _delegate;
  late final StreamController<Object?> _messages;
  StreamSubscription<Object?>? _delegateSubscription;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> send(Object? message) => _delegate.send(message);
}

final class _DelayedCancelViewTransport implements ViewTransport {
  _DelayedCancelViewTransport(this._delegate) {
    _messages = StreamController<Object?>(
      sync: true,
      onListen: () {
        _delegateSubscription = _delegate.messages.listen(
          _messages.add,
          onError: _messages.addError,
          onDone: _messages.close,
        );
      },
      onCancel: () async {
        if (!_cancellationStarted.isCompleted) {
          _cancellationStarted.complete();
        }
        await _allowCancellation.future;
        await _delegateSubscription?.cancel();
        _cancellationCompleted = true;
      },
    );
  }

  final ViewTransport _delegate;
  final Completer<void> _cancellationStarted = Completer<void>();
  final Completer<void> _allowCancellation = Completer<void>();
  late final StreamController<Object?> _messages;
  StreamSubscription<Object?>? _delegateSubscription;
  bool _cancellationCompleted = false;
  bool sentClosing = false;
  bool sentClosingAfterCancellation = false;

  Future<void> get cancellationStarted => _cancellationStarted.future;

  void allowCancellation() => _allowCancellation.complete();

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> send(Object? message) {
    if (message case <Object?, Object?>{'kind': 'closing'}) {
      sentClosing = true;
      sentClosingAfterCancellation = _cancellationCompleted;
    }
    return _delegate.send(message);
  }
}

final class _ReceivingLifecycleViewTransport
    implements ViewTransport, ViewTransportLifecycle {
  _ReceivingLifecycleViewTransport(this._delegate) {
    _messages = StreamController<Object?>(
      sync: true,
      onListen: () {
        _delegateSubscription = _delegate.messages.listen(
          _messages.add,
          onError: _messages.addError,
          onDone: _messages.close,
        );
      },
    );
  }

  final ViewTransport _delegate;
  late final StreamController<Object?> _messages;
  // The lifecycle seam closes this owned native-style subscription.
  // ignore: cancel_subscriptions
  StreamSubscription<Object?>? _delegateSubscription;
  bool sentClosingAfterReceivingClose = false;

  @override
  int get receivingSubscriptionCount => _delegateSubscription == null ? 0 : 1;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> send(Object? message) {
    if (message case <Object?, Object?>{'kind': 'closing'}) {
      sentClosingAfterReceivingClose = _delegateSubscription == null;
    }
    return _delegate.send(message);
  }

  @override
  Future<void> closeReceiving() async {
    final subscription = _delegateSubscription;
    _delegateSubscription = null;
    await subscription?.cancel();
    await _messages.close();
  }
}

final class _ControllableViewTransport implements ViewTransport {
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast(sync: true);
  final List<Object?> sent = [];

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> send(Object? message) {
    sent.add(message);
    return Future.value();
  }

  void addMessage(Object? message) => _messages.add(message);

  void addReceiveError(Object error) => _messages.addError(error);

  Future<void> closeMessages() => _messages.close();
}

final class _ReadyAckObservingViewTransport implements ViewTransport {
  _ReadyAckObservingViewTransport(this._delegate);

  final ViewTransport _delegate;
  final List<Object?> sent = [];
  void Function()? onReadyAck;

  List<Object?> get sentKinds => [
    for (final rawMessage in sent)
      (rawMessage! as Map<Object?, Object?>)['kind'],
  ];

  @override
  Stream<Object?> get messages => _delegate.messages;

  @override
  Future<void> send(Object? message) {
    sent.add(message);
    if (message case <Object?, Object?>{'kind': 'readyAck'}) {
      onReadyAck?.call();
    }
    return _delegate.send(message);
  }
}
