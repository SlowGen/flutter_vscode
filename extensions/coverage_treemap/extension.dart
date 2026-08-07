import 'package:flutter_vscode/manifest.dart';

/// Dart-owned extension metadata consumed by `flutter_vscode build`.
const extension = ExtensionManifest(
  name: 'coverage-treemap',
  displayName: 'Coverage Treemap',
  description: 'Line coverage in your editor and a coverage treemap.',
  version: '0.0.1',
  publisher: 'local',
  activationEvents: ['onStartupFinished'],
  commands: [
    ExtensionCommand(
      command: 'coverage-treemap.showTreemap',
      title: 'Coverage: Show Treemap',
    ),
    ExtensionCommand(
      command: 'coverage-treemap.refresh',
      title: 'Coverage: Refresh',
    ),
    ExtensionCommand(
      command: 'coverage-treemap.toggleLineHighlights',
      title: 'Coverage: Toggle Line Highlights',
    ),
    ExtensionCommand(
      command: 'coverage-treemap.runTests',
      title: 'Coverage: Run Tests with Coverage',
    ),
    ExtensionCommand(
      command: 'coverage-treemap.smoke',
      title: 'Coverage: Smoke Snapshot (diagnostics)',
    ),
    ExtensionCommand(
      command: 'coverage-treemap.viewSmoke',
      title: 'Coverage: View Smoke (diagnostics)',
    ),
  ],
);
