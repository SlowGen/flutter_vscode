import 'dart:io';

import 'package:test/test.dart';

import 'support/repository.dart';

/// V0-1/V0-2: the legacy v0 pipeline is deleted, not carried.
///
/// The v0 annotation/builder pipeline (source_gen builders, the
/// `generate_vscode_extension` scaffolder, the webview bridge runtime,
/// `example/`, and the legacy agent skills) died with the v0-removal
/// round. This gate keeps every deleted surface deleted: files, package
/// configuration, and the aggregate test script may not regrow them.
void main() {
  group('V0-1: the v0 pipeline is gone', () {
    test('the v0 entry points and directories are deleted', () {
      const deleted = [
        'bin/generate_vscode_extension.dart',
        'bin/init.dart',
        'build.yaml',
        'PRD.md',
      ];
      for (final path in deleted) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: '$path belongs to the deleted v0 pipeline',
        );
      }
      const deletedDirectories = [
        'tool/legacy-agent-skills',
      ];
      for (final path in deletedDirectories) {
        expect(
          Directory(path).existsSync(),
          isFalse,
          reason: '$path/ belongs to the deleted v0 pipeline',
        );
      }
      // The v0 example was a buildable legacy project (lib/, launch
      // config, handwritten TypeScript, generated .g.part sources).
      // Today's example/ is the pub-convention doc snippet only; any of
      // the v0 shapes returning is the regression this pin exists for.
      expect(
        Directory('example/lib').existsSync(),
        isFalse,
        reason: 'example/lib belongs to the deleted v0 pipeline',
      );
      expect(
        File('example/pubspec.yaml').existsSync(),
        isFalse,
        reason: 'the example is a doc snippet, not a buildable project',
      );
      final exampleSources = Directory(
        'example',
      ).listSync(recursive: true).whereType<File>().map((file) => file.path);
      for (final source in exampleSources) {
        expect(
          source,
          isNot(anyOf(endsWith('.ts'), endsWith('.g.part'))),
          reason: 'v0 example sources must not return',
        );
      }
    });

    test('lib/ carries no v0 annotation, builder, or bridge sources', () {
      const deleted = [
        'lib/annotations.dart',
        'lib/builder.dart',
        'lib/flutter_vscode.dart',
        'lib/runtime.dart',
        'lib/src/vscode.dart',
        'lib/src/vscode_codegen_helpers.dart',
        'lib/src/vscode_controller_base.dart',
        'lib/src/vscode_generator.dart',
        'lib/src/vscode_ts_generator.dart',
        'lib/src/vscode_validation.dart',
        'lib/src/vscode_webview_helper.dart',
        'lib/src/webview_bridge.dart',
        'lib/src/webview_bridge_stub.dart',
        'lib/src/webview_bridge_web.dart',
      ];
      for (final path in deleted) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: '$path belongs to the deleted v0 pipeline',
        );
      }
    });

    test('the package manifest drops the v0 executable and dependencies', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      expect(
        pubspec,
        isNot(contains('generate_vscode_extension')),
        reason: 'the v0 scaffolder executable retires with its source',
      );
      // Verified before deletion: no v1 source (lib/src/cli, the
      // dart_vscode binding tool, remaining tests) imports any of these.
      for (final dependency in [
        'build',
        'source_gen',
        'build_runner',
        'build_test',
      ]) {
        expect(
          RegExp('^  $dependency:', multiLine: true).hasMatch(pubspec),
          isFalse,
          reason: 'only the v0 pipeline used $dependency',
        );
      }
    });
  });

  group('V0-2: the test and gate surface follows its subject', () {
    test('the v0 test suites and generator checks are deleted', () {
      const deleted = [
        'test/flutter_vscode_test.dart',
        'test/generate_vscode_extension_test.dart',
        'test/vscode_codegen_helpers_test.dart',
        'test/vscode_controller_base_test.dart',
        'test/vscode_test.dart',
        'test/webview_bridge_test.dart',
        'tool/build_test_support.dart',
        'tool/check_dart_generator.dart',
        'tool/check_ts_generator.dart',
      ];
      for (final path in deleted) {
        expect(
          File(path).existsSync(),
          isFalse,
          reason: '$path tested only the deleted v0 pipeline',
        );
      }
    });

    test('CI runs no v0 steps', () {
      final aggregate = File(
        repoPath('.github/workflows/test.yml'),
      ).readAsStringSync();
      for (final retired in [
        'build_runner',
        'check_dart_generator',
        'check_ts_generator',
        'example',
      ]) {
        expect(
          aggregate,
          isNot(contains(retired)),
          reason: 'the workflow must not run the retired v0 step "$retired"',
        );
      }
    });

    test('.pubignore carries no entries for deleted files', () {
      final pubIgnore = File('.pubignore').readAsLinesSync();
      for (final dead in [
        '/tool/build_test_support.dart',
        '/tool/check_dart_generator.dart',
        '/tool/check_ts_generator.dart',
      ]) {
        expect(
          pubIgnore,
          isNot(contains(dead)),
          reason: '$dead ignores a file that no longer exists',
        );
      }
    });
  });
}
