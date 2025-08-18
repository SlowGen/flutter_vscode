import 'dart:async';
import 'dart:math';
import 'package:flutter_vscode/src/command_message.dart';
import 'package:flutter_vscode/src/webview_bridge.dart';

/// Base class for generated VS Code controllers.
///
/// This class provides the common functionality for sending messages
/// to the VS Code extension and handling responses.
abstract class VSCodeControllerBase {
  VSCodeControllerBase(this._bridge) {
    _bridge.setMessageHandler(handleMessage);
  }

  final WebViewBridge _bridge;
  final Map<String, Completer<dynamic>> _pendingRequests = {};
  final Random _random = Random();

  /// Sends a command to the VS Code extension and optionally waits for a
  /// response.
  Future<T> sendCommand<T>(
    String command,
    List<dynamic> params, {
    bool expectsResponse = false,
  }) async {
    final requestId = _generateRequestId();

    final message = CommandMessage(
      command: command,
      params: params,
      requestId: requestId,
    );

    if (expectsResponse) {
      final completer = Completer<T>();
      _pendingRequests[requestId] = completer;

      _bridge.postMessage(message);

      return completer.future;
    } else {
      _bridge.postMessage(message);
      return Future.value();
    }
  }

  /// Generates a unique request ID for message tracking.
  String _generateRequestId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}_'
        '${_random.nextInt(10000)}';
  }

  /// Handles incoming messages from the VS Code extension.
  /// This should be called by the webview's message handler.
  void handleMessage(CommandMessage message) {
    final requestId = message.requestId;
    if (requestId != null && _pendingRequests.containsKey(requestId)) {
      final completer = _pendingRequests.remove(requestId)!;

      if (message.error != null) {
        completer.completeError(Exception(message.error));
      } else {
        completer.complete(message.result);
      }
    }
  }
}
