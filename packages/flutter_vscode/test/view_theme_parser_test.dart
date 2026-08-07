import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vscode/view.dart';

void main() {
  group('parseCssColor', () {
    test('parses six-digit hex as opaque ARGB', () {
      expect(parseCssColor('#1e1e1e'), 0xFF1E1E1E);
      expect(parseCssColor('#AbCdEf'), 0xFFABCDEF);
    });

    test('expands three-digit hex per nibble', () {
      expect(parseCssColor('#abc'), 0xFFAABBCC);
      expect(parseCssColor('#FFF'), 0xFFFFFFFF);
    });

    test('reads eight-digit hex alpha from the trailing byte', () {
      expect(parseCssColor('#11223344'), 0x44112233);
      expect(parseCssColor('#ffffffff'), 0xFFFFFFFF);
    });

    test('expands four-digit hex including its alpha nibble', () {
      expect(parseCssColor('#1234'), 0x44112233);
    });

    test('parses rgb() functions as opaque ARGB', () {
      expect(parseCssColor('rgb(30, 30, 30)'), 0xFF1E1E1E);
      expect(parseCssColor('rgb(0,127,255)'), 0xFF007FFF);
      expect(parseCssColor('RGB(1, 2, 3)'), 0xFF010203);
    });

    test('parses rgba() alpha as a 0..1 fraction', () {
      expect(parseCssColor('rgba(30, 30, 30, 0.5)'), 0x801E1E1E);
      expect(parseCssColor('rgba(255, 255, 255, 0)'), 0x00FFFFFF);
      expect(parseCssColor('rgba(0, 0, 0, .25)'), 0x40000000);
      expect(parseCssColor('rgba(0, 0, 0, 1)'), 0xFF000000);
    });

    test('clamps out-of-range channels and alpha like CSS', () {
      expect(parseCssColor('rgb(300, -20, 0)'), 0xFFFF0000);
      expect(parseCssColor('rgba(0, 0, 0, 5)'), 0xFF000000);
    });

    test('ignores surrounding whitespace', () {
      expect(parseCssColor(' #fff '), 0xFFFFFFFF);
      expect(parseCssColor('\n rgb(1, 2, 3) '), 0xFF010203);
    });

    test('returns null for anything unparseable', () {
      expect(parseCssColor(''), isNull);
      expect(parseCssColor('transparent'), isNull);
      expect(parseCssColor('#12'), isNull);
      expect(parseCssColor('#12345'), isNull);
      expect(parseCssColor('#GGGGGG'), isNull);
      expect(parseCssColor('rgb(1, 2)'), isNull);
      expect(parseCssColor('rgb(a, b, c)'), isNull);
      expect(parseCssColor('hsl(0, 0%, 0%)'), isNull);
      expect(parseCssColor('var(--vscode-editor-background)'), isNull);
    });
  });

  group('VSCodeThemeKind.fromBodyClass', () {
    test('maps each vscode body class to its kind', () {
      expect(
        VSCodeThemeKind.fromBodyClass('vscode-light'),
        VSCodeThemeKind.light,
      );
      expect(
        VSCodeThemeKind.fromBodyClass('vscode-dark'),
        VSCodeThemeKind.dark,
      );
      expect(
        VSCodeThemeKind.fromBodyClass('vscode-high-contrast'),
        VSCodeThemeKind.highContrast,
      );
    });

    test('high contrast wins when dark is also listed', () {
      expect(
        VSCodeThemeKind.fromBodyClass('vscode-high-contrast vscode-dark'),
        VSCodeThemeKind.highContrast,
      );
    });

    test('high-contrast light variants stay high contrast', () {
      expect(
        VSCodeThemeKind.fromBodyClass('vscode-high-contrast-light'),
        VSCodeThemeKind.highContrast,
      );
    });

    test('falls back to dark for unknown class lists', () {
      expect(VSCodeThemeKind.fromBodyClass(''), VSCodeThemeKind.dark);
      expect(
        VSCodeThemeKind.fromBodyClass('monaco-workbench'),
        VSCodeThemeKind.dark,
      );
    });
  });

  group('VSCodeThemeSnapshot', () {
    final colors = <String, int>{
      'editor-background': 0xFF1E1E1E,
      'editor-foreground': 0xFFD4D4D4,
      'button-background': 0xFF0E639C,
      'button-foreground': 0xFFFFFFFF,
      'list-hoverBackground': 0xFF2A2D2E,
      'panel-border': 0xFF454545,
      'focusBorder': 0xFF007FD4,
      'badge-background': 0xFF4D4D4D,
    };

    test('typed getters resolve their --vscode-* variable names', () {
      final snapshot = VSCodeThemeSnapshot(
        kind: VSCodeThemeKind.dark,
        colors: colors,
      );
      expect(snapshot.editorBackground, 0xFF1E1E1E);
      expect(snapshot.editorForeground, 0xFFD4D4D4);
      expect(snapshot.buttonBackground, 0xFF0E639C);
      expect(snapshot.buttonForeground, 0xFFFFFFFF);
      expect(snapshot.listHoverBackground, 0xFF2A2D2E);
      expect(snapshot.panelBorder, 0xFF454545);
      expect(snapshot.focusBorder, 0xFF007FD4);
      expect(snapshot.color('badge-background'), 0xFF4D4D4D);
    });

    test('missing variables read as null', () {
      final snapshot = VSCodeThemeSnapshot(
        kind: VSCodeThemeKind.light,
        colors: const {},
      );
      expect(snapshot.editorBackground, isNull);
      expect(snapshot.focusBorder, isNull);
      expect(snapshot.color('badge-background'), isNull);
    });

    test('equal kind and colors compare equal for stream dedupe', () {
      final first = VSCodeThemeSnapshot(
        kind: VSCodeThemeKind.dark,
        colors: Map.of(colors),
      );
      final second = VSCodeThemeSnapshot(
        kind: VSCodeThemeKind.dark,
        colors: Map.of(colors),
      );
      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });

    test('a changed kind or color breaks equality', () {
      final base = VSCodeThemeSnapshot(
        kind: VSCodeThemeKind.dark,
        colors: Map.of(colors),
      );
      expect(
        base,
        isNot(
          VSCodeThemeSnapshot(kind: VSCodeThemeKind.light, colors: colors),
        ),
      );
      expect(
        base,
        isNot(
          VSCodeThemeSnapshot(
            kind: VSCodeThemeKind.dark,
            colors: {...colors, 'editor-background': 0xFFFFFFFF},
          ),
        ),
      );
      expect(
        base,
        isNot(
          VSCodeThemeSnapshot(
            kind: VSCodeThemeKind.dark,
            colors: {...colors}..remove('editor-background'),
          ),
        ),
      );
    });

    test('captured colors are an immutable snapshot', () {
      final source = Map.of(colors);
      final snapshot = VSCodeThemeSnapshot(
        kind: VSCodeThemeKind.dark,
        colors: source,
      );
      source['editor-background'] = 0xFF000000;
      expect(snapshot.editorBackground, 0xFF1E1E1E);
      expect(
        () => snapshot.colors['editor-background'] = 0,
        throwsUnsupportedError,
      );
    });
  });
}
