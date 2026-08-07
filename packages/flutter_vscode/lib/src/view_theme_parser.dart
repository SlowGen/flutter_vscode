/// Pure parsing for the VS Code webview theme surface: CSS color
/// strings, the body-class theme kind, and an immutable theme snapshot.
///
/// Everything here is platform-neutral Dart so Host Dart, Flutter View,
/// and VM test code can all share one theme vocabulary.
library;

import 'package:meta/meta.dart';

final _hexDigits = RegExp(r'^[0-9a-fA-F]+$');
final _rgbFunction = RegExp(
  r'^rgba?\(\s*(-?\d+)\s*,\s*(-?\d+)\s*,\s*(-?\d+)\s*'
  r'(?:,\s*(-?\d*\.?\d+)\s*)?\)$',
  caseSensitive: false,
);

/// Parses a CSS color string into a 32-bit ARGB integer.
///
/// Accepts the color forms VS Code webviews actually serve for
/// `--vscode-*` variables: `#RGB`, `#RGBA`, `#RRGGBB`, `#RRGGBBAA`,
/// `rgb(r, g, b)`, and `rgba(r, g, b, a)`. Channels clamp to `0..255`
/// and alpha clamps to `0..1`, mirroring CSS. Every other value —
/// including named colors and modern space-separated syntax — returns
/// null so callers fall back to their own defaults.
int? parseCssColor(String value) {
  final text = value.trim();
  if (text.startsWith('#')) {
    return _parseHexColor(text.substring(1));
  }
  final match = _rgbFunction.firstMatch(text);
  if (match == null) {
    return null;
  }
  final red = _parseChannel(match.group(1)!);
  final green = _parseChannel(match.group(2)!);
  final blue = _parseChannel(match.group(3)!);
  final alphaText = match.group(4);
  final alpha = alphaText == null
      ? 0xFF
      : (double.parse(alphaText).clamp(0, 1) * 0xFF).round();
  return (alpha << 24) | (red << 16) | (green << 8) | blue;
}

int _parseChannel(String text) => int.parse(text).clamp(0, 0xFF);

int? _parseHexColor(String digits) {
  if (!_hexDigits.hasMatch(digits)) {
    return null;
  }
  switch (digits.length) {
    case 3 || 4:
      return _parseHexColor(
        [for (final nibble in digits.split('')) '$nibble$nibble'].join(),
      );
    case 6:
      return 0xFF000000 | int.parse(digits, radix: 16);
    case 8:
      final rgba = int.parse(digits, radix: 16);
      return ((rgba & 0xFF) << 24) | (rgba >>> 8);
    default:
      return null;
  }
}

/// The broad theme family VS Code advertises through its webview body
/// class.
enum VSCodeThemeKind {
  /// A light workbench theme (`vscode-light`).
  light,

  /// A dark workbench theme (`vscode-dark`).
  dark,

  /// A high-contrast workbench theme (`vscode-high-contrast`).
  highContrast;

  /// Derives the kind from a webview body `class` attribute value.
  ///
  /// High contrast is checked before dark because VS Code can list both
  /// classes for one high-contrast theme. Unknown class lists fall back
  /// to [dark], matching the dark-first fallbacks used when theme
  /// variables are missing.
  static VSCodeThemeKind fromBodyClass(String className) {
    if (className.contains('vscode-high-contrast')) {
      return highContrast;
    }
    if (className.contains('vscode-dark')) {
      return dark;
    }
    if (className.contains('vscode-light')) {
      return light;
    }
    return dark;
  }
}

/// One immutable capture of the active VS Code webview theme.
///
/// [colors] is keyed by `--vscode-*` variable name without the
/// `--vscode-` prefix (for example `editor-background`). Value equality
/// over [kind] and [colors] lets watchers dedupe redundant captures.
@immutable
final class VSCodeThemeSnapshot {
  /// Creates a snapshot over a defensive copy of [colors].
  VSCodeThemeSnapshot({
    required this.kind,
    required Map<String, int> colors,
  }) : colors = Map.unmodifiable(colors);

  /// The broad theme family advertised by the webview body class.
  final VSCodeThemeKind kind;

  /// All captured theme colors as 32-bit ARGB integers, keyed by
  /// variable name without the `--vscode-` prefix.
  final Map<String, int> colors;

  /// The captured color for the `--vscode-[name]` variable, or null
  /// when the theme did not provide it as a parseable color.
  int? color(String name) => colors[name];

  /// `--vscode-editor-background`.
  int? get editorBackground => color('editor-background');

  /// `--vscode-editor-foreground`.
  int? get editorForeground => color('editor-foreground');

  /// `--vscode-button-background`.
  int? get buttonBackground => color('button-background');

  /// `--vscode-button-foreground`.
  int? get buttonForeground => color('button-foreground');

  /// `--vscode-list-hoverBackground`.
  int? get listHoverBackground => color('list-hoverBackground');

  /// `--vscode-panel-border`.
  int? get panelBorder => color('panel-border');

  /// `--vscode-focusBorder`.
  int? get focusBorder => color('focusBorder');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    if (other is! VSCodeThemeSnapshot ||
        other.kind != kind ||
        other.colors.length != colors.length) {
      return false;
    }
    for (final entry in colors.entries) {
      if (other.colors[entry.key] != entry.value) {
        return false;
      }
    }
    return true;
  }

  @override
  int get hashCode => Object.hash(
    kind,
    Object.hashAllUnordered([
      for (final entry in colors.entries) Object.hash(entry.key, entry.value),
    ]),
  );
}
