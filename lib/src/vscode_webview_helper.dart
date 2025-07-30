import 'dart:html' as html;
import 'vscode_controller_base.dart';

/// Helper class to initialize VS Code webview message handling.
class VSCodeWebViewHelper {
  static bool _initialized = false;

  /// Initializes the message handler for VS Code webview communication.
  /// This should be called early in your Flutter app (e.g., in main()).
  static void initialize() {
    if (_initialized) return;
    _initialized = true;

    // Listen for messages from VS Code
    html.window.addEventListener('message', (event) {
      final messageEvent = event as html.MessageEvent;
      if (messageEvent.data is Map) {
        final message = Map<String, dynamic>.from(messageEvent.data as Map);
        VSCodeControllerBase.handleMessage(message);
      }
    });
  }
}
