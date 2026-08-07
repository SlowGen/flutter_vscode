/// Hosts a Flutter View from Host Dart: panel lifecycle, the webview shell,
/// and the protocol session that carries operations between the two runtimes.
///
/// This is framework code, not generated code. It used to be emitted into
/// every Extension Project as `flutter_view_host.g.dart`, stored here as a
/// `const` string -- which is why it could not be analyzed or tested where
/// it lived.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:dart_vscode/dart_vscode.dart' as vs;
import 'package:dart_vscode/view_protocol.dart';

/// Observes each parsed native webview message after it is queued for
/// the protocol validator; harnesses use it to inspect traffic without
/// changing delivery.
typedef IncomingViewMessageObserver = void Function(Object? message);

/// Adapts one native VS Code webview to the shared protocol transport.
final class HostWebviewTransport
    implements ViewTransport, ViewTransportLifecycle {
  /// Starts listening to messages from the supplied VS Code webview.
  HostWebviewTransport(this._webview, [this._onIncomingMessage]) {
    _messageRegistration = _webview.onDidReceiveMessage.call(
      ((JSAny? message) {
        if (_closed || _receivingClosed) {
          return;
        }
        try {
          final incoming = message.dartify();
          _messages.add(incoming);
          _onIncomingMessage?.call(incoming);
        } on Object {
          // Feed malformed external input through the protocol validator.
          _messages.add(null);
        }
      }).toJS,
    );
  }

  final vs.Webview _webview;
  final IncomingViewMessageObserver? _onIncomingMessage;
  final StreamController<Object?> _messages =
      StreamController<Object?>.broadcast(sync: true);
  // Unobserved by composed hosts; ignore() keeps a rejected delivery
  // from escaping as an uncaught zone error when nothing listens.
  final Completer<Never> _failure = Completer<Never>()..future.ignore();
  final Set<Future<void>> _pendingSends = {};
  vs.Disposable? _messageRegistration;
  var _receivingClosed = false;
  var _closed = false;
  var _closeCompleted = false;

  @override
  Stream<Object?> get messages => _messages.stream;

  /// Number of native message subscriptions still owned by this adapter.
  int get subscriptionCount => receivingSubscriptionCount;

  @override
  int get receivingSubscriptionCount => _messageRegistration == null ? 0 : 1;

  /// Number of native post-message promises that have not settled.
  int get pendingSendCount => _pendingSends.length;

  /// Completes with the first terminal native delivery failure.
  Future<Never> get failure => _failure.future;

  @override
  Future<void> send(Object? message) {
    if (_closed) {
      throw StateError('The Host webview transport is closed.');
    }
    late final Future<void> delivery;
    try {
      delivery = _webview.postMessage(message.jsify()).toDart.then<void>((
        accepted,
      ) {
        if (!accepted.toDart) {
          throw StateError('VS Code rejected a Host-to-View message.');
        }
      });
    } on Object catch (error, stackTrace) {
      _recordFailure(error, stackTrace);
      return Future.error(error, stackTrace);
    }
    _pendingSends.add(delivery);
    unawaited(
      delivery.then<void>(
        (_) => _pendingSends.remove(delivery),
        onError: (Object error, StackTrace stackTrace) {
          _pendingSends.remove(delivery);
          _recordFailure(error, stackTrace);
        },
      ),
    );
    return delivery;
  }

  void _recordFailure(Object error, StackTrace stackTrace) {
    if (!_failure.isCompleted) {
      _failure.completeError(error, stackTrace);
    }
  }

  /// Waits until every native post-message promise has settled.
  Future<void> drain() async {
    while (_pendingSends.isNotEmpty) {
      final pending = _pendingSends.toList();
      await Future.wait(
        pending.map(
          (send) =>
              send.then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        ),
      );
    }
  }

  /// Removes the native listener and closes the Dart message stream.
  Future<void> close() async {
    if (_closeCompleted) {
      return;
    }
    _closed = true;
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> preserveFirstError(FutureOr<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await preserveFirstError(closeReceiving);
    await preserveFirstError(drain);
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
    _closeCompleted = true;
  }

  @override
  Future<void> closeReceiving() async {
    if (_receivingClosed) {
      return;
    }
    final messageRegistration = _messageRegistration;
    if (messageRegistration != null) {
      messageRegistration.dispose();
      _messageRegistration = null;
    }
    _receivingClosed = true;
    await _messages.close();
  }
}

/// One open Flutter View panel with a connected protocol session.
final class FlutterViewHost {
  /// Opens the built Flutter View named [viewName] (its folder under
  /// `views/`) in a webview panel and connects the protocol session.
  ///
  /// Owns panel creation, resource-root scoping, session identifiers,
  /// CSP-correct HTML, and disposal: when the user closes the panel,
  /// the session and transport close and [onClosed] fires.
  ///
  /// [extraHead] fragments are written verbatim before `</head>`;
  /// callers own their escaping. Inline scripts among them execute
  /// only when they carry [scriptNonce], which also joins the CSP
  /// `script-src` directive and is stamped on the bootstrap script
  /// tag. [onIncomingMessage] observes each parsed native webview
  /// message without changing delivery.
  factory FlutterViewHost.open({
    required vs.ExtensionContext context,
    required vs.VscodeApi vscode,
    required String viewName,
    required String viewType,
    required String title,
    Iterable<ViewOperationBinding> operations = const [],
    List<String> extraHead = const [],
    String? scriptNonce,
    IncomingViewMessageObserver? onIncomingMessage,
    void Function()? onClosed,
  }) {
    var viewRoot = context.extensionUri;
    for (final segment in ['out', 'views', viewName]) {
      viewRoot = vscode.Uri.joinPath(viewRoot, [segment.toJS]);
    }
    final panel = vscode.window.createWebviewPanel(
      viewType,
      title,
      vscode.ViewColumn.One.toJS,
      vs.JSIntersection_9b95285c216c(
        vs.WebviewOptions.lit$(
          enableScripts: true.toJS,
          localResourceRoots: [viewRoot].toJS,
        ),
      ),
    );
    final transport = HostWebviewTransport(
      panel.webview,
      onIncomingMessage,
    );
    final sessionId = _secureToken();
    final bootstrapNonce = _secureToken();
    final session = HostViewSession.connect(
      transport: transport,
      sessionId: sessionId,
      bootstrapNonce: bootstrapNonce,
      operations: operations,
    );
    final host = FlutterViewHost._(
      panel,
      session,
      transport,
      DateTime.now(),
      vscode.Uri,
      viewRoot,
      sessionId,
      bootstrapNonce,
      title,
      List<String>.unmodifiable(extraHead),
      scriptNonce,
    );
    panel.webview.html = host._viewHtml();
    panel.onDidDispose.call(
      ((JSAny? _) {
        unawaited(host.close());
        onClosed?.call();
      }).toJS,
    );
    return host;
  }

  FlutterViewHost._(
    this.panel,
    this.session,
    this.transport,
    this.loadStartedAt,
    this._uri,
    this._viewRoot,
    this._sessionId,
    this._bootstrapNonce,
    this._title,
    this._extraHead,
    this._scriptNonce,
  );

  /// The native webview panel showing the view.
  final vs.WebviewPanel panel;

  /// The connected versioned protocol session.
  final HostViewSession session;

  /// The transport backing [session].
  final HostWebviewTransport transport;

  /// Instant the initial view HTML was handed to the webview; the
  /// start of a cold-start measurement ending at first render.
  final DateTime loadStartedAt;

  final vs.UriCtor _uri;
  final vs.Uri _viewRoot;
  final String _sessionId;
  final String _bootstrapNonce;
  final String _title;
  final List<String> _extraHead;
  final String? _scriptNonce;
  var _reloadGeneration = 0;
  var _closed = false;

  /// Reloads the running view document in place.
  ///
  /// Regenerates the session's view HTML with a bumped reload
  /// generation — each document is distinct, so the webview always
  /// applies it — and hands it to the panel. The protocol session
  /// stays connected and accepts the reloaded view's handshake.
  void reload() {
    _reloadGeneration += 1;
    panel.webview.html = _viewHtml();
  }

  String _viewHtml() => flutterViewHtml(
    webview: panel.webview,
    uri: _uri,
    viewRoot: _viewRoot,
    sessionId: _sessionId,
    bootstrapNonce: _bootstrapNonce,
    title: _title,
    extraHead: _extraHead,
    scriptNonce: _scriptNonce,
    reloadGeneration: _reloadGeneration,
  );

  /// Closes the protocol session and transport.
  ///
  /// Safe to call more than once; panel disposal triggers it
  /// automatically.
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await session.close();
    await transport.close();
  }
}

/// CSP-correct webview HTML that boots the built Flutter View under
/// [viewRoot] and carries the protocol bootstrap metadata.
///
/// [uri] is the native URI constructor object used to join the
/// bootstrap path. [extraHead] fragments are written verbatim before
/// `</head>`. When [scriptNonce] is supplied it joins the `script-src`
/// directive and is stamped on the bootstrap script tag.
/// [reloadGeneration] stamps a document-distinguishing meta so
/// in-place reloads always apply.
String flutterViewHtml({
  required vs.Webview webview,
  required vs.UriCtor uri,
  required vs.Uri viewRoot,
  required String sessionId,
  required String bootstrapNonce,
  required String title,
  List<String> extraHead = const [],
  String? scriptNonce,
  int reloadGeneration = 0,
}) {
  final base = webview.asWebviewUri(viewRoot).toString$();
  final bootstrap = webview
      .asWebviewUri(uri.joinPath(viewRoot, ['flutter_bootstrap.js'.toJS]))
      .toString$();
  final csp = webview.cspSource;
  final scriptSources = scriptNonce == null ? csp : "$csp 'nonce-$scriptNonce'";
  final nonceAttribute = scriptNonce == null ? '' : ' nonce="$scriptNonce"';
  final headExtras = extraHead.map((fragment) => '\n  $fragment').join();
  final safeTitle = title
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;');
  return '''
<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src $csp data:; font-src $csp; style-src $csp 'unsafe-inline'; script-src $scriptSources 'wasm-unsafe-eval'; connect-src $csp; worker-src $csp blob:">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <meta name="flutter-vscode-session" content="$sessionId">
  <meta name="flutter-vscode-bootstrap-nonce" content="$bootstrapNonce">
  <meta name="flutter-vscode-reload-generation" content="$reloadGeneration">
  <base href="$base/">
  <title>$safeTitle</title>$headExtras
</head>
<body>
  <script$nonceAttribute src="$bootstrap"></script>
</body>
</html>
''';
}

String _secureToken() {
  final random = Random.secure();
  return List.generate(32, (_) => random.nextInt(16).toRadixString(16)).join();
}
