/// Canonicalizes generated Dart through the pinned SDK's own formatter.
///
/// The SDK's `dart format` is not byte-identical to any published
/// `package:dart_style` this workspace can resolve (the vendored
/// formatter joins `) implements` where the published package splits),
/// so canonical-by-construction means shelling out to the one formatter
/// every other check in the repository runs. The formatter-canonical pin
/// in `dart_layer_test` keeps the pairing honest.
library;

import 'dart:io';

/// Formats [source] exactly as the pinned SDK's `dart format` would.
Future<String> formatWithSdk(String source) async {
  final temporary = await Directory.systemTemp.createTemp(
    'dart_vscode_sdk_format_',
  );
  try {
    final file = File('${temporary.path}/source.dart');
    await file.writeAsString(source);
    final result = await Process.run('dart', ['format', file.path]);
    if (result.exitCode != 0) {
      throw ProcessException(
        'dart',
        ['format'],
        'SDK formatting of generated output failed: '
            '${result.stdout}\n${result.stderr}',
        result.exitCode,
      );
    }
    return file.readAsString();
  } finally {
    await temporary.delete(recursive: true);
  }
}
