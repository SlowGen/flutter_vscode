import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Repository-relative location of the one receipt-path definition.
///
/// The contract writer, the Dart evidence suite, and the in-container
/// verifier all read this file. Transcribing the list into any of them
/// again is a defect: a duplicated constant only ever catches someone
/// forgetting to update a copy, which is a hazard the duplication itself
/// creates.
const hostContractSourcesPath =
    '$apiPackagePath/tool/bindings/host-contract-sources.json';

/// The one VS Code baseline the pinned inputs on disk carry.
///
/// File names under `tool/bindings` embed this version; the shipped
/// constant in `lib/src/contributions/vscode_api_version.dart` is the
/// authority, and the importer's baseline validation refuses a tree where
/// the two drift.
const pinnedBaseline = '1.129.1';

/// Repository-relative location of the pinned canonical IR.
const pinnedInventoryPath =
    '$apiPackagePath/tool/bindings/ir/vscode-$pinnedBaseline.json';

/// Repository-relative location of the pinned Semantic Overrides.
const pinnedOverridesPath =
    '$apiPackagePath/tool/bindings/overrides/vscode-$pinnedBaseline.json';

/// Repository-relative location of the durable checkpoint-4 artifact.
///
/// This module owns the spelling for every Dart reader, the same way
/// `tool/extension_host_test/host_contract.cjs` owns it for every
/// JavaScript reader; hand-joining it anywhere else is a defect.
const contractArtifactPath =
    '$apiPackagePath/tool/bindings/contracts/checkpoint4-extension-host.json';

/// Repository-relative location of the published API package, whose
/// maintainer `tool/` area holds the pinned bindings.
const apiPackagePath = 'packages/dart_vscode';

/// Repository-relative location of the published framework package, which
/// holds the Extension Host fixture and harness.
const frameworkPackagePath = 'packages/flutter_vscode';

/// Reads the repository-relative receipt paths the contract attests.
Map<String, String> hostContractSourcePaths(Directory repositoryRoot) {
  final file = File('${repositoryRoot.path}/$hostContractSourcesPath');
  final decoded = jsonDecode(file.readAsStringSync()) as Map<String, Object?>;
  final sources = (decoded['sources']! as Map<Object?, Object?>)
      .cast<String, Object?>();
  return <String, String>{
    for (final entry in sources.entries) entry.key: entry.value! as String,
  };
}

/// Builds the canonical checkpoint-4 Host Contract artifact from tree state.
///
/// Every field is derived mechanically: source receipts hash the receipted
/// repository files, the attributed bindings are the non-excluded Semantic
/// Override entries, and the API/runtime targets come from the pinned
/// inventory, the fixture manifest, the harness package, and the container
/// definition. Hand-editing the artifact is not a supported workflow.
String buildHostContractArtifact(Directory repositoryRoot) {
  final root = repositoryRoot.path;

  Map<String, Object?> readJson(String relativePath) =>
      (jsonDecode(File('$root/$relativePath').readAsStringSync())
              as Map<Object?, Object?>)
          .cast<String, Object?>();

  final inventory = readJson(pinnedInventoryPath);
  final product =
      ((inventory['source']! as Map<Object?, Object?>)['product']!
              as Map<Object?, Object?>)
          .cast<String, Object?>();

  final fixtureManifest = readJson(
    '$frameworkPackagePath/test/fixtures/host_extension/package.json',
  );
  final fixtureEngines = (fixtureManifest['engines']! as Map<Object?, Object?>)
      .cast<String, Object?>();

  final harnessPackage = readJson(
    '$frameworkPackagePath/tool/extension_host_test/package.json',
  );
  final harnessDependencies =
      (harnessPackage['devDependencies']! as Map<Object?, Object?>)
          .cast<String, Object?>();

  final container = File(
    '$root/$frameworkPackagePath/tool/extension_host_test/Dockerfile',
  ).readAsStringSync();
  final nodeImage = RegExp(
    r'^FROM (\S+)$',
    multiLine: true,
  ).firstMatch(container)!.group(1)!;

  final sourcePaths = hostContractSourcePaths(repositoryRoot);
  final sourceIds = sourcePaths.keys.toList()..sort();
  final sources = <String, Object?>{
    for (final sourceId in sourceIds)
      sourceId: <String, Object?>{
        'path': sourcePaths[sourceId],
        'sha256': sha256
            .convert(
              File('$root/${sourcePaths[sourceId]}').readAsBytesSync(),
            )
            .toString(),
      },
  };

  final overrides = readJson(pinnedOverridesPath);
  final entries = (overrides['entries']! as Map<Object?, Object?>)
      .cast<String, Object?>();
  final attributedBindings = <String>[
    for (final entry in entries.entries)
      if ((entry.value! as Map<Object?, Object?>)['strategy'] !=
          'reviewedExcluded')
        entry.key,
  ]..sort();

  final artifact = <String, Object?>{
    'schemaVersion': 1,
    'id': 'checkpoint4ExtensionHost',
    'boundary': 'vscodeExtensionHost',
    'sourceRepository': 'https://github.com/SlowGen/flutter_vscode',
    'apiTarget': <String, Object?>{
      'version': product['version'],
      'commit': product['commit'],
    },
    'runtimeTarget': <String, Object?>{
      'vscodeVersion': fixtureEngines['vscode'],
      'testElectronVersion': harnessDependencies['@vscode/test-electron'],
      'nodeImage': nodeImage,
      'cachePolicy': 'freshInvocationScoped',
    },
    'trustBoundary': <String, Object?>{
      'dartToolchain':
          'The locally installed Flutter/Dart SDK and packages resolved '
          'from the enforced lockfile are trusted; this contract does '
          'not attest their bytes.',
      'vscodeRuntime':
          'Each gate resolves the exact official VS Code version into a '
          'new invocation-scoped cache; this contract does not attest '
          'a predeclared runtime binary digest.',
    },
    'sources': sources,
    'evidence': <String, Object?>{
      'kind': 'mechanicalAttribution',
      'meaning':
          'Every listed binding ID is attributed to this one real Extension '
          'Host Contract by its reviewed Semantic Override; the gate '
          'passes only after the receipted repository sources and the '
          'surrounding native behavior pass, without per-member '
          'observation.',
      'independentBehavioralContracts': false,
    },
    'attributedBindings': attributedBindings,
  };
  return '${const JsonEncoder.withIndent('  ').convert(artifact)}\n';
}

/// Writes the artifact and repins its hash inside the Semantic Overrides.
///
/// Every checked-in baseline cites the same checkpoint-4 contract, so each
/// `tool/bindings/overrides/vscode-*.json` is edited surgically: reviewed
/// content and formatting stay byte-identical outside the single
/// artifactSha256 value per file.
void writeHostContractArtifact(Directory repositoryRoot) {
  final root = repositoryRoot.path;
  final artifact = buildHostContractArtifact(repositoryRoot);
  File('$root/$contractArtifactPath')
    ..parent.createSync(recursive: true)
    ..writeAsStringSync(artifact);

  final digest = sha256.convert(utf8.encode(artifact)).toString();
  final overridesFiles =
      Directory('$root/$apiPackagePath/tool/bindings/overrides')
          .listSync()
          .whereType<File>()
          .where(
            (file) => RegExp(
              r'vscode-\d+\.\d+\.\d+\.json$',
            ).hasMatch(file.uri.pathSegments.last),
          )
          .toList()
        ..sort((left, right) => left.path.compareTo(right.path));
  if (overridesFiles.isEmpty) {
    throw StateError('Expected at least one Semantic Override file to repin.');
  }
  for (final overridesFile in overridesFiles) {
    final overridesText = overridesFile.readAsStringSync();
    final pinPattern = RegExp('"artifactSha256": "[0-9a-f]{64}"');
    if (pinPattern.allMatches(overridesText).length != 1) {
      throw StateError(
        'Expected exactly one artifactSha256 pin in the Semantic Overrides '
        '(${overridesFile.path}).',
      );
    }
    overridesFile.writeAsStringSync(
      overridesText.replaceFirst(pinPattern, '"artifactSha256": "$digest"'),
    );
  }
}
