import 'dart:convert';
import 'dart:io';

import 'contract.dart';
import 'dart_layer.dart';
import 'generator.dart';
import 'parity_report.dart';
import 'sdk_format.dart';

/// The dart_vscode maintainer entry point.
///
/// Extension authors never run this: the generated API layer, its ledgers,
/// and the evidence artifacts it maintains all ship inside the published
/// `dart_vscode` package. The maintainer reruns it when moving the pinned
/// VS Code baseline.
Future<void> main(List<String> arguments) async {
  try {
    if (arguments.length != 2) {
      throw const VSCodeBindingGenerationException(
        'INVALID_ARGUMENTS',
        'Usage: generate.dart <--dart-layer|--parity|--contract> '
            '<repository root>.',
      );
    }
    final root = arguments[1];
    final bindings = '$root/$apiPackagePath/tool/bindings';
    switch (arguments.first) {
      case '--dart-layer':
        final inventory = await _readJson('$root/$pinnedInventoryPath');
        final overrides = await _readJson('$root/$pinnedOverridesPath');
        final artifacts = emitDartLayer(inventory);
        await File(
              '$root/$apiPackagePath/lib/src/generated/'
              'vscode_dart_layer.g.dart',
            )
            .create(recursive: true)
            .then(
              (file) async =>
                  file.writeAsString(await formatWithSdk(artifacts.library)),
            );
        await File(
          '$bindings/dart-layer-ledger.json',
        ).writeAsString(artifacts.ledger);
        await File(
          '$bindings/parity-ledger.json',
        ).writeAsString(artifacts.parityLedger);
        // The coverage ledger is maintainer evidence for the shipped slice,
        // regenerated with the layer so the two can never drift apart.
        await File('$bindings/coverage-ledger.json').writeAsString(
          VSCodeBindingGenerator().generateCoverageLedger(
            inventory: inventory,
            overrides: overrides,
          ),
        );
      case '--parity':
        final coverage = await _readJson('$bindings/coverage-ledger.json');
        final inventory = await _readJson('$root/$pinnedInventoryPath');
        await File(
          '$root/docs/reference/parity.md',
        ).writeAsString(buildParityReport(coverage, inventory));
      case '--contract':
        writeHostContractArtifact(Directory(root));
      default:
        throw const VSCodeBindingGenerationException(
          'INVALID_ARGUMENTS',
          'Usage: generate.dart <--dart-layer|--parity|--contract> '
              '<repository root>.',
        );
    }
  } on VSCodeBindingGenerationException catch (error) {
    stderr.writeln(error);
    exitCode = 1;
  } on FormatException catch (error) {
    stderr.writeln('INVALID_JSON: $error');
    exitCode = 1;
  } on FileSystemException catch (error) {
    stderr.writeln('FILE_SYSTEM_ERROR: ${error.message} (${error.path})');
    exitCode = 1;
  }
}

Future<Map<String, Object?>> _readJson(String path) async {
  final decoded = jsonDecode(await File(path).readAsString());
  if (decoded is! Map<Object?, Object?>) {
    throw VSCodeBindingGenerationException(
      'INVALID_JSON',
      '$path must contain a JSON object.',
    );
  }
  return decoded.cast<String, Object?>();
}
