/// Live VS Code webview defaults for the [ViewShell] platform seams.
library;

import 'package:flutter_vscode/src/view_shell.dart';
import 'package:flutter_vscode/src/view_theme_web.dart';
import 'package:flutter_vscode/src/view_transport_web.dart';

/// The default [ViewShell] session source over the acquired VS Code
/// webview transport, releasing that transport on shell disposal.
ViewShellSessionSource defaultViewShellSessionSource() {
  final bootstrap = VSCodeViewBootstrap.acquire();
  return ViewShellSessionSource(
    connect: (operations) => bootstrap.connect(operations: operations),
    release: bootstrap.close,
  );
}

/// The default [ViewShell] theme source over the live webview document.
ViewShellThemeSource defaultViewShellThemeSource() => ViewShellThemeSource(
  read: readVSCodeTheme,
  changes: watchVSCodeTheme(),
);
