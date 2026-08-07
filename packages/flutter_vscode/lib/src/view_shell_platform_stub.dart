/// Non-web placeholders for the [ViewShell] platform seams.
library;

import 'package:flutter_vscode/src/view_shell.dart';

/// Only the compiled web build of a Flutter View can acquire the VS Code
/// webview transport; other platforms must inject a session source.
ViewShellSessionSource defaultViewShellSessionSource() {
  throw UnsupportedError(
    'ViewShell.connect requires a compiled VS Code webview runtime or an '
    'injected ViewShellSessionSource.',
  );
}

/// Only the compiled web build of a Flutter View has a themed VS Code
/// webview document; other platforms must inject a theme source.
ViewShellThemeSource defaultViewShellThemeSource() {
  throw UnsupportedError(
    'ViewShell.connect requires a compiled VS Code webview runtime or an '
    'injected ViewShellThemeSource.',
  );
}
