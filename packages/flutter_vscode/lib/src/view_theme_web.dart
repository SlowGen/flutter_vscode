/// Reads and watches the VS Code webview theme from the live document.
library;

import 'dart:async';
import 'dart:js_interop';

import 'package:flutter/material.dart';
import 'package:flutter_vscode/src/view_theme_parser.dart';
import 'package:web/web.dart' as web;

/// The `--vscode-*` variables captured into every theme snapshot.
const _themeVariableNames = [
  'editor-background',
  'editor-foreground',
  'button-background',
  'button-foreground',
  'list-hoverBackground',
  'panel-border',
  'focusBorder',
  'editorWidget-background',
  'input-background',
  'input-foreground',
  'badge-background',
  'badge-foreground',
];

/// Captures the active VS Code webview theme from the document.
///
/// Reads the theme kind from the body class VS Code maintains
/// (`vscode-dark`, `vscode-light`, `vscode-high-contrast`) and each
/// captured `--vscode-*` variable from the computed style of the root
/// element. Variables that are missing or not parseable as colors are
/// simply absent from the snapshot.
VSCodeThemeSnapshot readVSCodeTheme() {
  final colors = <String, int>{};
  final root = web.document.documentElement;
  if (root != null) {
    final styles = web.window.getComputedStyle(root);
    for (final name in _themeVariableNames) {
      final color = parseCssColor(styles.getPropertyValue('--vscode-$name'));
      if (color != null) {
        colors[name] = color;
      }
    }
  }
  return VSCodeThemeSnapshot(
    kind: VSCodeThemeKind.fromBodyClass(web.document.body?.className ?? ''),
    colors: colors,
  );
}

Stream<VSCodeThemeSnapshot>? _themeChanges;

/// A broadcast stream of theme snapshots for live theme switches.
///
/// VS Code rewrites the webview body's `class` and `style` attributes
/// when the user changes color themes; a `MutationObserver` on those
/// attributes emits one fresh [readVSCodeTheme] snapshot per mutation
/// batch, deduped by snapshot equality. The single shared observer
/// starts with the first listener and disconnects with the last.
Stream<VSCodeThemeSnapshot> watchVSCodeTheme() =>
    _themeChanges ??= _watchThemeChanges();

Stream<VSCodeThemeSnapshot> _watchThemeChanges() {
  late final StreamController<VSCodeThemeSnapshot> controller;
  VSCodeThemeSnapshot? lastEmitted;
  final observer = web.MutationObserver(
    ((JSArray<web.MutationRecord> records, web.MutationObserver observer) {
      final snapshot = readVSCodeTheme();
      if (snapshot == lastEmitted) {
        return;
      }
      lastEmitted = snapshot;
      controller.add(snapshot);
    }).toJS,
  );
  controller = StreamController<VSCodeThemeSnapshot>.broadcast(
    onListen: () {
      final body = web.document.body;
      if (body == null) {
        return;
      }
      observer.observe(
        body,
        web.MutationObserverInit(
          attributes: true,
          attributeFilter: ['class'.toJS, 'style'.toJS].toJS,
        ),
      );
    },
    onCancel: () {
      lastEmitted = null;
      observer.disconnect();
    },
  );
  return controller.stream;
}

/// Builds a Material theme from a VS Code theme [snapshot].
///
/// Brightness follows the snapshot kind (high contrast renders dark),
/// the scaffold takes the editor background, and the color scheme is
/// seeded from the VS Code button accent with the editor and widget
/// surfaces layered over it. Missing variables fall back to VS Code's
/// default dark palette so a view outside a themed webview still
/// renders sensibly.
ThemeData vsCodeThemeData(VSCodeThemeSnapshot snapshot) {
  final brightness = snapshot.kind == VSCodeThemeKind.light
      ? Brightness.light
      : Brightness.dark;
  final editorBackground = Color(snapshot.editorBackground ?? 0xFF1E1E1E);
  final editorForeground = Color(snapshot.editorForeground ?? 0xFFD4D4D4);
  final buttonBackground = Color(snapshot.buttonBackground ?? 0xFF0E639C);
  final buttonForeground = Color(snapshot.buttonForeground ?? 0xFFFFFFFF);
  final widgetBackground = Color(
    snapshot.color('editorWidget-background') ?? 0xFF252526,
  );
  final panelBorder = Color(snapshot.panelBorder ?? 0xFF454545);
  final focusBorder = Color(snapshot.focusBorder ?? 0xFF007FD4);
  final listHoverBackground = Color(snapshot.listHoverBackground ?? 0xFF2A2D2E);
  final colorScheme =
      ColorScheme.fromSeed(
        seedColor: buttonBackground,
        brightness: brightness,
      ).copyWith(
        primary: buttonBackground,
        onPrimary: buttonForeground,
        surface: editorBackground,
        onSurface: editorForeground,
        surfaceContainer: widgetBackground,
        outline: panelBorder,
      );
  return ThemeData(
    colorScheme: colorScheme,
    scaffoldBackgroundColor: editorBackground,
    canvasColor: editorBackground,
    dividerColor: panelBorder,
    focusColor: focusBorder,
    hoverColor: listHoverBackground,
  );
}
