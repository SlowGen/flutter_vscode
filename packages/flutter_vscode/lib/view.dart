/// Versioned communication between Host Dart and a Flutter View.
library;

export 'package:dart_vscode/view_protocol.dart';

export 'src/view_boot_stub.dart'
    if (dart.library.html) 'src/view_boot_web.dart';
export 'src/view_shell.dart';
export 'src/view_theme_parser.dart';
export 'src/view_theme_stub.dart'
    if (dart.library.html) 'src/view_theme_web.dart';
export 'src/view_transport_stub.dart'
    if (dart.library.html) 'src/view_transport_web.dart';
