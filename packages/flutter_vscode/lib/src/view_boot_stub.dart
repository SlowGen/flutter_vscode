import 'package:flutter/widgets.dart';

/// Boots a Flutter View safely inside a VS Code webview.
///
/// Only the compiled web build of a Flutter View can run; other
/// platforms have no VS Code webview runtime.
void runFlutterView(Widget app) {
  throw UnsupportedError(
    'runFlutterView requires a compiled VS Code webview runtime.',
  );
}
