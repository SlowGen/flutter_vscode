import 'dart:async';
import 'dart:math';
import 'webview_bridge.dart';

/// Base class for generated VS Code controllers.
/// 
/// This class provides the common functionality for sending messages
/// to the VS Code extension and handling responses.
abstract class VSCodeControllerBase {
  static final WebViewBridge _bridge = WebViewBridge();
  static final Map<String, Completer<dynamic>> _pendingRequests = {};
  static final Random _random = Random();

  /// Sends a command to the VS Code extension and optionally waits for a response.
  static Future<T> sendCommand<T>(
    String command,
    List<dynamic> params, {
    bool expectsResponse = false,
  }) async {
    final requestId = _generateRequestId();
    
    final message = {
      'command': command,
      'params': params,
      'requestId': requestId,
    };

    if (expectsResponse) {
      final completer = Completer<T>();
      _pendingRequests[requestId] = completer;
      
      _bridge.postMessage(message);
      
      return await completer.future;
    } else {
      _bridge.postMessage(message);
      // For void methods, we need to return a completed future
      // This is a bit of a hack, but works for Future<void>
      return (null as dynamic) as T;
    }
  }

  /// Generates a unique request ID for message tracking.
  static String _generateRequestId() {
    return 'req_${DateTime.now().millisecondsSinceEpoch}_${_random.nextInt(10000)}';
  }

  /// Handles incoming messages from the VS Code extension.
  /// This should be called by the webview's message handler.
  static void handleMessage(Map<String, dynamic> message) {
    final requestId = message['requestId'] as String?;
    if (requestId != null && _pendingRequests.containsKey(requestId)) {
      final completer = _pendingRequests.remove(requestId)!;
      
      if (message.containsKey('error')) {
        completer.completeError(Exception(message['error']));
      } else {
        completer.complete(message['result']);
      }
    }
  }
}
