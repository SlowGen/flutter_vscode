/// A user-facing Author Toolchain failure with a stable machine code.
///
/// The `bin/flutter_vscode.dart` process adapter maps this to a
/// `CODE: message` stderr line and the carried [exitCode].
final class CliException implements Exception {
  /// Creates a CLI failure carrying a stable [code] and process [exitCode].
  const CliException(
    this.message, {
    required this.code,
    this.exitCode = 1,
  });

  /// Stable machine-readable failure code (for example `INVALID_VSIX`).
  final String code;

  /// Actionable human-readable description of the failure.
  final String message;

  /// Process exit code the adapter reports for this failure.
  final int exitCode;
}

/// A Host Dart syntax diagnostic surfaced by the import boundary check.
///
/// The process adapter converts the boundary checker's own exception type
/// into this one so command modules can render `INVALID_HOST_DART` output
/// without depending on `tool/` sources.
final class HostDartSyntaxException implements Exception {
  /// Creates a source diagnostic at an exact location.
  const HostDartSyntaxException({
    required this.path,
    required this.line,
    required this.column,
    required this.message,
  });

  /// Absolute path to the malformed Dart source.
  final String path;

  /// One-based source line.
  final int line;

  /// One-based source column.
  final int column;

  /// Analyzer problem message.
  final String message;
}
