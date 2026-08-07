import 'package:flutter/widgets.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

/// Boots a Flutter View safely inside a VS Code webview.
///
/// Disables the web URL strategy before running [app]: a webview
/// document's real origin is `vscode-webview://`, so Flutter's default
/// strategy — exercised by `MaterialApp`'s navigation history
/// integration — throws a cross-origin `SecurityError` during engine
/// startup and the view never renders a frame.
void runFlutterView(Widget app) {
  setUrlStrategy(null);
  runApp(app);
}
