import 'dart:convert';
import 'dart:io';

import 'package:flutter_vscode/src/cli/check_host_imports.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('rejects a transitive unsupported SDK import', () async {
    final fixture = await Directory.systemTemp.createTemp(
      'flutter_vscode_host_import_guard_',
    );
    addTearDown(() => fixture.delete(recursive: true));

    final libDirectory = Directory(p.join(fixture.path, 'lib'));
    await libDirectory.create(recursive: true);
    final dartToolDirectory = Directory(p.join(fixture.path, '.dart_tool'));
    await dartToolDirectory.create();
    final dependency = Directory(p.join(fixture.path, 'transitive_io'));
    final dependencyLib = Directory(p.join(dependency.path, 'lib'));
    await dependencyLib.create(recursive: true);

    final entrypoint = File(p.join(fixture.path, 'lib', 'extension.dart'));
    await entrypoint.writeAsString(
      "import 'package:transitive_io/transitive_io.dart';\n",
    );
    await File(p.join(dependencyLib.path, 'transitive_io.dart')).writeAsString(
      "import 'dart:io';\n",
    );
    final packageConfig = File(
      p.join(dartToolDirectory.path, 'package_config.json'),
    );
    await packageConfig.writeAsString(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'host_fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.12',
          },
          {
            'name': 'transitive_io',
            'rootUri': dependency.uri.toString(),
            'packageUri': 'lib/',
            'languageVersion': '3.12',
          },
        ],
      }),
    );

    final violations = checkHostImports(
      entrypoint: entrypoint,
      packageConfig: packageConfig,
    );
    final output = formatHostImportViolations(violations);

    expect(violations, isNotEmpty, reason: output);
    expect(output, contains('dart:io'));
    expect(output, contains('transitive_io.dart:1'));
    expect(output, contains('package:transitive_io/transitive_io.dart'));
    expect(output, contains('Node Extension Host'));
  });

  test('rejects an unclassified SDK library', () async {
    final fixture = await Directory.systemTemp.createTemp(
      'flutter_vscode_host_sdk_guard_',
    );
    addTearDown(() => fixture.delete(recursive: true));

    final libDirectory = Directory(p.join(fixture.path, 'lib'));
    await libDirectory.create(recursive: true);
    final dartToolDirectory = Directory(p.join(fixture.path, '.dart_tool'));
    await dartToolDirectory.create();
    final entrypoint = File(p.join(libDirectory.path, 'extension.dart'));
    await entrypoint.writeAsString("import 'dart:ffi';\n");
    final packageConfig = File(
      p.join(dartToolDirectory.path, 'package_config.json'),
    );
    await packageConfig.writeAsString(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'host_fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.12',
          },
        ],
      }),
    );

    final violations = checkHostImports(
      entrypoint: entrypoint,
      packageConfig: packageConfig,
    );
    final output = formatHostImportViolations(violations);

    expect(violations, isNotEmpty, reason: output);
    expect(output, contains('dart:ffi'));
    expect(output, contains('not supported by Host Dart'));
  });

  test('rejects Flutter and browser packages', () async {
    final fixture = await Directory.systemTemp.createTemp(
      'flutter_vscode_host_package_guard_',
    );
    addTearDown(() => fixture.delete(recursive: true));

    final libDirectory = Directory(p.join(fixture.path, 'lib'));
    await libDirectory.create(recursive: true);
    final dartToolDirectory = Directory(p.join(fixture.path, '.dart_tool'));
    await dartToolDirectory.create();
    final entrypoint = File(p.join(libDirectory.path, 'extension.dart'));
    await entrypoint.writeAsString(
      "import 'package:flutter/widgets.dart';\n"
      "import 'package:web/web.dart';\n",
    );
    final packageConfig = File(
      p.join(dartToolDirectory.path, 'package_config.json'),
    );
    await packageConfig.writeAsString(
      jsonEncode({
        'configVersion': 2,
        'packages': [
          {
            'name': 'host_fixture',
            'rootUri': '../',
            'packageUri': 'lib/',
            'languageVersion': '3.12',
          },
        ],
      }),
    );

    final violations = checkHostImports(
      entrypoint: entrypoint,
      packageConfig: packageConfig,
    );
    final output = formatHostImportViolations(violations);

    expect(violations, isNotEmpty, reason: output);
    expect(output, contains('package:flutter/widgets.dart'));
    expect(output, contains('package:web/web.dart'));
    expect(
      RegExp('not supported by Host Dart').allMatches(output),
      hasLength(2),
    );
  });
}
