/// Helper class to initialize VS Code webview message handling.
class VSCodeWebViewHelper {
  static bool _initialized = false;

  /// Initializes the message handler for VS Code webview communication.
  /// This should be called early in your Flutter app (e.g., in main()).
  static void initialize() {
    if (_initialized) return;
    _initialized = true;
  }
}
