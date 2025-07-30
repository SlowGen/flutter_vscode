import 'dart:js_util' if (dart.library.io) '';

/// A bridge to communicate with the VS Code extension.
class WebViewBridge {
  /// Sends a message to the VS Code extension.
  void postMessage(dynamic message) {
    // Only compile the web-specific code when dart:js_util is available
    // ignore: deprecated_member_use
    // ignore: avoid_web_libraries_in_flutter
    callMethod(globalThis, 'postMessage', [message]);
  }
}

