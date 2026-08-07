/// Non-web placeholders for the VS Code webview theme bridge.
library;

import 'package:flutter/material.dart';
import 'package:flutter_vscode/src/view_theme_parser.dart';

/// Captures the active VS Code webview theme from the document.
///
/// Only the compiled web build of a Flutter View has a themed VS Code
/// webview document to read; other platforms throw.
VSCodeThemeSnapshot readVSCodeTheme() {
  throw UnsupportedError(
    'readVSCodeTheme requires a compiled VS Code webview runtime.',
  );
}

/// A broadcast stream of theme snapshots for live theme switches.
///
/// Only the compiled web build of a Flutter View has a themed VS Code
/// webview document to observe; other platforms throw.
Stream<VSCodeThemeSnapshot> watchVSCodeTheme() {
  throw UnsupportedError(
    'watchVSCodeTheme requires a compiled VS Code webview runtime.',
  );
}

/// Builds a Material theme from a VS Code theme [snapshot].
///
/// Only the compiled web build of a Flutter View resolves live VS Code
/// theme colors; other platforms throw.
ThemeData vsCodeThemeData(VSCodeThemeSnapshot snapshot) {
  throw UnsupportedError(
    'vsCodeThemeData requires a compiled VS Code webview runtime.',
  );
}
