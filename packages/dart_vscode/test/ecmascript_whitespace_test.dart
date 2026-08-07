import 'package:dart_vscode/src/contributions/ecmascript_whitespace.dart';
import 'package:test/test.dart';

void main() {
  test(
    'ECMAScript trim whitespace uses the exact projected code-point set',
    () {
      const expected = <int>{
        0x0009,
        0x000A,
        0x000B,
        0x000C,
        0x000D,
        0x0020,
        0x00A0,
        0x1680,
        0x2000,
        0x2001,
        0x2002,
        0x2003,
        0x2004,
        0x2005,
        0x2006,
        0x2007,
        0x2008,
        0x2009,
        0x200A,
        0x2028,
        0x2029,
        0x202F,
        0x205F,
        0x3000,
        0xFEFF,
      };

      for (var codePoint = 0; codePoint <= 0xFFFF; codePoint += 1) {
        expect(
          isEcmaScriptTrimWhitespaceCodePoint(codePoint),
          expected.contains(codePoint),
          reason: 'U+${codePoint.toRadixString(16).padLeft(4, '0')}',
        );
      }
    },
  );

  test(
    'ECMAScript falsy-or-whitespace preserves non-ECMAScript whitespace',
    () {
      expect(isEcmaScriptFalsyOrWhitespace(''), isTrue);
      expect(isEcmaScriptFalsyOrWhitespace(' \t\n'), isTrue);
      expect(isEcmaScriptFalsyOrWhitespace('\uFEFF'), isTrue);
      expect(isEcmaScriptFalsyOrWhitespace('\u0085'), isFalse);
      expect(isEcmaScriptFalsyOrWhitespace(' x '), isFalse);
    },
  );
}
