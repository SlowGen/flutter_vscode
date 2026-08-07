import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:dart_vscode/view_protocol.dart';
import 'package:web/web.dart' as web;

/// Acquires and owns the transport for one VS Code-hosted Flutter View.
final class VSCodeViewBootstrap {
  VSCodeViewBootstrap._({
    required this._sessionId,
    required this._bootstrapNonce,
    required this._api,
  });

  factory VSCodeViewBootstrap._create() {
    final sessionId = _requiredMetadata(sessionMetaName);
    final bootstrapNonce = _requiredMetadata(bootstrapNonceMetaName);
    late final _VSCodeApi api;
    try {
      api = _acquireVsCodeApi();
    } on Object catch (error) {
      throw StateError(
        'Could not acquire the private VS Code webview API. '
        'This Flutter View must run inside Host-generated VS Code HTML: $error',
      );
    }
    return VSCodeViewBootstrap._(
      sessionId: sessionId,
      bootstrapNonce: bootstrapNonce,
      api: api,
    );
  }

  /// Acquires the private VS Code webview API exactly once.
  ///
  /// The Host-generated HTML must provide non-empty [sessionMetaName] and
  /// [bootstrapNonceMetaName] metadata before this constructor is called.
  factory VSCodeViewBootstrap.acquire() {
    return _instance ??= VSCodeViewBootstrap._create();
  }

  /// Metadata key containing the Host-created session identifier.
  static const sessionMetaName = 'flutter-vscode-session';

  /// Metadata key containing the Host-created bootstrap nonce.
  static const bootstrapNonceMetaName = 'flutter-vscode-bootstrap-nonce';

  static VSCodeViewBootstrap? _instance;

  final String _sessionId;
  final String _bootstrapNonce;
  final _VSCodeApi _api;
  _VSCodeWebviewTransport? _transport;
  Future<FlutterViewSession>? _connection;

  /// Native browser message listeners still owned by this bootstrap.
  int get receivingSubscriptionCount =>
      _transport?.receivingSubscriptionCount ?? 0;

  /// Connects the Flutter View using Host-provided metadata.
  ///
  /// [operations] are the typed operations this view allows Host Dart to
  /// call. A successful connection is created once, so only the first
  /// successful call's operations take effect; a failed attempt clears
  /// the memo so a later call retries with its own operations.
  Future<FlutterViewSession> connect({
    Iterable<ViewOperationBinding> operations = const [],
  }) {
    final existing = _connection;
    if (existing != null) {
      return existing;
    }
    // A failed attempt's session terminates its transport, so each
    // attempt runs over a fresh transport on the once-acquired API.
    final transport = _VSCodeWebviewTransport(_api);
    _transport = transport;
    late final Future<FlutterViewSession> attempt;
    attempt =
        FlutterViewSession.connect(
          transport: transport,
          sessionId: _sessionId,
          bootstrapNonce: _bootstrapNonce,
          operations: operations,
        ).onError<Object>((error, stackTrace) {
          if (identical(_connection, attempt)) {
            _connection = null;
            unawaited(transport.close());
            if (identical(_transport, transport)) {
              _transport = null;
            }
          }
          Error.throwWithStackTrace(error, stackTrace);
        });
    _connection = attempt;
    return attempt;
  }

  /// Removes the owned browser message listener.
  ///
  /// Await [FlutterViewSession.closed] before closing the transport during an
  /// orderly Host-requested shutdown.
  Future<void> close() => _transport?.close() ?? Future.value();
}

final class _VSCodeWebviewTransport
    implements ViewTransport, ViewTransportLifecycle {
  _VSCodeWebviewTransport(this._api) {
    _messageListener = ((web.MessageEvent event) {
      if (_closed || _receivingClosed) {
        return;
      }
      try {
        final encoded = _jsonStringify(event.data);
        _messages.add(jsonDecode(encoded));
      } on Object {
        // Feed malformed external input to the protocol validator. It will
        // fail closed through the same typed invalid-message path.
        _messages.add(null);
      }
    }).toJS;
    web.window.addEventListener('message', _messageListener);
  }

  final _VSCodeApi _api;
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast(sync: true);
  late final web.EventListener _messageListener;
  var _receivingClosed = false;
  var _closed = false;

  @override
  int get receivingSubscriptionCount => _receivingClosed ? 0 : 1;

  @override
  Stream<Object?> get messages => _messages.stream;

  @override
  Future<void> send(Object? message) {
    if (_closed) {
      throw StateError('The VS Code webview transport is closed.');
    }
    // acquireVsCodeApi().postMessage returns void. This confirms synchronous
    // handoff only; VS Code exposes no asynchronous acceptance result here.
    _api.postMessage(_jsonParse(jsonEncode(message)));
    return Future.value();
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await closeReceiving();
  }

  @override
  Future<void> closeReceiving() async {
    if (_receivingClosed) {
      return;
    }
    _receivingClosed = true;
    web.window.removeEventListener('message', _messageListener);
    await _messages.close();
  }
}

@JS()
@staticInterop
class _VSCodeApi {}

extension on _VSCodeApi {
  external void postMessage(JSAny? message);
}

@JS('acquireVsCodeApi')
external _VSCodeApi _acquireVsCodeApi();

@JS('JSON.parse')
external JSAny? _jsonParse(String value);

@JS('JSON.stringify')
external String _jsonStringify(JSAny? value);

String _requiredMetadata(String name) {
  final element = web.document.querySelector('meta[name="$name"]');
  final value = (element as web.HTMLMetaElement?)?.content.trim();
  if (value == null || value.isEmpty) {
    throw StateError(
      'Host-generated VS Code HTML must provide non-empty '
      '<meta name="$name" content="…"> metadata.',
    );
  }
  return value;
}
