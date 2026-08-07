/// Returns whether [value] is falsy or contains only ECMAScript trim code
/// points.
///
/// This is the Dart lowering of the pinned VS Code helper's
/// `!str || str.trim().length === 0` predicate. It intentionally does not use
/// Dart's `String.trim`, whose Unicode whitespace set includes U+0085.
bool isEcmaScriptFalsyOrWhitespace(String value) {
  if (value.isEmpty) {
    return true;
  }
  return value.runes.every(isEcmaScriptTrimWhitespaceCodePoint);
}

/// Returns whether [codePoint] is removed by ECMAScript `String.prototype.trim`.
bool isEcmaScriptTrimWhitespaceCodePoint(int codePoint) {
  return switch (codePoint) {
    >= 0x0009 && <= 0x000D => true,
    0x0020 ||
    0x00A0 ||
    0x1680 ||
    >= 0x2000 && <= 0x200A ||
    0x2028 ||
    0x2029 ||
    0x202F ||
    0x205F ||
    0x3000 ||
    0xFEFF => true,
    _ => false,
  };
}
