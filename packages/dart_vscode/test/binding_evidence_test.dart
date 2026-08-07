import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../tool/binding_generator/contract.dart' as contract_writer;
import 'support/json.dart';

/// The repository root: tests run with the package as the working
/// directory, but the contract receipts repository-relative paths.
Directory _repositoryRoot() {
  for (var dir = Directory.current; ; dir = dir.parent) {
    final pubspec = File('${dir.path}/pubspec.yaml');
    if (pubspec.existsSync() &&
        pubspec.readAsStringSync().contains('\nworkspace:')) {
      return dir;
    }
    if (dir.path == dir.parent.path) {
      throw StateError('No workspace root above ${Directory.current.path}');
    }
  }
}

void main() {
  test('the contract writer owns the repo-relative artifact path', () {
    // Same seam discipline as the .cjs verifier: readers cross the
    // writer's exported const instead of hand-joining a ninth spelling.
    expect(
      contract_writer.contractArtifactPath,
      '${contract_writer.apiPackagePath}'
      '/tool/bindings/contracts/checkpoint4-extension-host.json',
    );
    expect(
      File(
        '${_repositoryRoot().path}/${contract_writer.contractArtifactPath}',
      ).existsSync(),
      isTrue,
    );
  });

  test(
    'the durable Host Contract artifact matches mechanical regeneration',
    () {
      final regenerated = contract_writer.buildHostContractArtifact(
        _repositoryRoot(),
      );
      expect(
        File(
          '${_repositoryRoot().path}/'
          '${contract_writer.contractArtifactPath}',
        ).readAsStringSync(),
        regenerated,
        reason:
            'The artifact is written only by the mechanical regenerator. '
            'Refresh it with: '
            'dart tool/binding_generator/generate.dart --contract .',
      );
      final overrides = readJsonObject(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final contract =
          (overrides['hostContracts']!
                  as Map<Object?, Object?>)['checkpoint4ExtensionHost']!
              as Map<Object?, Object?>;
      expect(
        sha256.convert(utf8.encode(regenerated)).toString(),
        contract['artifactSha256'],
        reason: 'The overrides pin must match the regenerated artifact bytes.',
      );
    },
  );

  test('the contract writer regenerates a copied tree byte-identically', () {
    final temporary = Directory.systemTemp.createTempSync(
      'flutter_vscode_contract_writer_',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    const overridesPath =
        'packages/dart_vscode/tool/bindings/overrides/vscode-1.129.1.json';
    const artifactPath = contract_writer.contractArtifactPath;
    for (final relative in [
      ...contract_writer.hostContractSourcePaths(_repositoryRoot()).values,
      overridesPath,
    ]) {
      final destination = File('${temporary.path}/$relative');
      destination.parent.createSync(recursive: true);
      File('${_repositoryRoot().path}/$relative').copySync(destination.path);
    }

    contract_writer.writeHostContractArtifact(temporary);

    final written = File('${temporary.path}/$artifactPath');
    expect(written.existsSync(), isTrue);
    expect(
      written.readAsStringSync(),
      contract_writer.buildHostContractArtifact(temporary),
      reason: 'the written artifact must equal mechanical regeneration',
    );
    final writtenOverrides = File(
      '${temporary.path}/$overridesPath',
    ).readAsStringSync();
    expect(
      writtenOverrides,
      contains(sha256.convert(written.readAsBytesSync()).toString()),
      reason: 'the overrides pin must carry the written artifact digest',
    );
    expect(
      writtenOverrides.replaceFirst(
        RegExp('"artifactSha256": "[0-9a-f]{64}"'),
        '"artifactSha256": "PIN"',
      ),
      File(
        '${_repositoryRoot().path}/$overridesPath',
      ).readAsStringSync().replaceFirst(
        RegExp('"artifactSha256": "[0-9a-f]{64}"'),
        '"artifactSha256": "PIN"',
      ),
      reason: 'the surgical pin update must change nothing else',
    );

    final artifactBytes = written.readAsBytesSync();
    contract_writer.writeHostContractArtifact(temporary);
    expect(
      written.readAsBytesSync(),
      artifactBytes,
      reason: 'a second write on a converged copy must be byte-identical',
    );
    expect(
      File('${temporary.path}/$overridesPath').readAsStringSync(),
      writtenOverrides,
      reason: 'a second write must not move the overrides pin',
    );
  });

  test('the contract writer refuses ambiguous overrides pins', () {
    final temporary = Directory.systemTemp.createTempSync(
      'flutter_vscode_contract_writer_pins_',
    );
    addTearDown(() => temporary.deleteSync(recursive: true));
    const overridesPath =
        'packages/dart_vscode/tool/bindings/overrides/vscode-1.129.1.json';
    for (final relative in [
      ...contract_writer.hostContractSourcePaths(_repositoryRoot()).values,
      overridesPath,
    ]) {
      final destination = File('${temporary.path}/$relative');
      destination.parent.createSync(recursive: true);
      File('${_repositoryRoot().path}/$relative').copySync(destination.path);
    }
    final overridesFile = File('${temporary.path}/$overridesPath');
    final original = overridesFile.readAsStringSync();
    final decoded = (jsonDecode(original) as Map<Object?, Object?>)
        .cast<String, Object?>();
    final contracts = (decoded['hostContracts']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    contracts['secondExtensionHost'] = jsonDecode(
      jsonEncode(contracts['checkpoint4ExtensionHost']),
    );
    overridesFile.writeAsStringSync(
      '${const JsonEncoder.withIndent('  ').convert(decoded)}\n',
    );
    expect(
      () => contract_writer.writeHostContractArtifact(temporary),
      throwsStateError,
      reason: 'more than one pin-shaped value must refuse the surgical edit',
    );

    overridesFile.writeAsStringSync(
      original.replaceFirst(
        RegExp('"artifactSha256": "[0-9a-f]{64}"'),
        '"artifactSha256": "not-a-digest"',
      ),
    );
    expect(
      () => contract_writer.writeHostContractArtifact(temporary),
      throwsStateError,
      reason: 'zero pin-shaped values must refuse the surgical edit',
    );
  });

  test('every emitted binding cites an executable real-host contract', () {
    final overrides = readJsonObject(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final contracts = (overrides['hostContracts']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();

    expect(contracts, isNotEmpty);
    for (final contractEntry in contracts.entries) {
      final contract = (contractEntry.value! as Map<Object?, Object?>)
          .cast<String, Object?>();
      expect(contract['boundary'], 'vscodeExtensionHost');
      expect(
        contract.keys.toSet(),
        {'artifact', 'artifactSha256', 'boundary'},
        reason: contractEntry.key,
      );

      final artifact = File(contract['artifact']! as String);
      expect(artifact.existsSync(), isTrue, reason: contractEntry.key);
      expect(
        sha256.convert(artifact.readAsBytesSync()).toString(),
        contract['artifactSha256'],
        reason: contractEntry.key,
      );
      final artifactJson = readJsonObject(artifact.path);
      expect(artifactJson['schemaVersion'], 1);
      expect(artifactJson['id'], contractEntry.key);
      expect(artifactJson['boundary'], 'vscodeExtensionHost');
      expect(
        artifactJson['sourceRepository'],
        'https://github.com/SlowGen/flutter_vscode',
      );
      final inventory = readJsonObject(
        'tool/bindings/ir/vscode-1.129.1.json',
      );
      final inventoryProduct =
          ((inventory['source']! as Map<Object?, Object?>)['product']!
                  as Map<Object?, Object?>)
              .cast<String, Object?>();
      expect(artifactJson['apiTarget'], {
        'version': inventoryProduct['version'],
        'commit': inventoryProduct['commit'],
      });
      final fixtureManifest = readJsonObject(
        '../flutter_vscode/test/fixtures/host_extension/package.json',
      );
      final fixtureEngines =
          (fixtureManifest['engines']! as Map<Object?, Object?>)
              .cast<String, Object?>();
      final harnessPackage = readJsonObject(
        '../flutter_vscode/tool/extension_host_test/package.json',
      );
      final harnessDependencies =
          (harnessPackage['devDependencies']! as Map<Object?, Object?>)
              .cast<String, Object?>();
      final container = File(
        '../flutter_vscode/tool/extension_host_test/Dockerfile',
      ).readAsStringSync();
      final nodeImage = RegExp(
        r'^FROM (\S+)$',
        multiLine: true,
      ).firstMatch(container)!.group(1)!;
      expect(artifactJson['runtimeTarget'], {
        'vscodeVersion': fixtureEngines['vscode'],
        'testElectronVersion': harnessDependencies['@vscode/test-electron'],
        'nodeImage': nodeImage,
        'cachePolicy': 'freshInvocationScoped',
      });
      expect(artifactJson['trustBoundary'], {
        'dartToolchain':
            'The locally installed Flutter/Dart SDK and packages resolved '
            'from the enforced lockfile are trusted; this contract does '
            'not attest their bytes.',
        'vscodeRuntime':
            'Each gate resolves the exact official VS Code version into a '
            'new invocation-scoped cache; this contract does not attest '
            'a predeclared runtime binary digest.',
      });
      expect(fixtureEngines['vscode'], overrides['vscodeVersion']);
      final sources = (artifactJson['sources']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      expect(
        sources.keys.toSet(),
        contract_writer.hostContractSourcePaths(_repositoryRoot()).keys.toSet(),
      );
      for (final sourceEntry in sources.entries) {
        final source = (sourceEntry.value! as Map<Object?, Object?>)
            .cast<String, Object?>();
        expect(
          source['path'],
          contract_writer.hostContractSourcePaths(
            _repositoryRoot(),
          )[sourceEntry.key],
          reason: sourceEntry.key,
        );
        final sourceFile = File('${_repositoryRoot().path}/${source['path']}');
        expect(sourceFile.existsSync(), isTrue, reason: sourceEntry.key);
        expect(
          sha256.convert(sourceFile.readAsBytesSync()).toString(),
          source['sha256'],
          reason: sourceEntry.key,
        );
      }

      expect(artifactJson['evidence'], {
        'kind': 'mechanicalAttribution',
        'meaning':
            'Every listed binding ID is attributed to this one real '
            'Extension Host Contract by its reviewed Semantic Override; '
            'the gate passes only after the receipted repository sources '
            'and the surrounding native behavior pass, without '
            'per-member observation.',
        'independentBehavioralContracts': false,
      });
      expect(artifactJson, isNot(contains('verifiedBindings')));
      final attributedBindings = (artifactJson['attributedBindings']! as List)
          .cast<String>();
      final expectedBindings = <String>[
        for (final entry in entries.entries)
          if ((entry.value! as Map<Object?, Object?>)['strategy'] !=
              'reviewedExcluded')
            entry.key,
      ]..sort();
      expect(attributedBindings, orderedEquals(expectedBindings));
    }

    for (final entry in entries.entries) {
      final override = (entry.value! as Map<Object?, Object?>)
          .cast<String, Object?>();
      expect(override, isNot(contains('hostVerified')), reason: entry.key);
      if (override['strategy'] == 'reviewedExcluded') {
        expect(override, isNot(contains('hostContract')), reason: entry.key);
      } else {
        final contract = override['hostContract'];
        expect(contract, isA<String>(), reason: entry.key);
        expect(contracts, contains(contract), reason: entry.key);
      }
    }
  });

  test('the retired binding-observation mechanism leaves no residue', () {
    // The walking-slice facade and its per-member observation plumbing
    // retired with SL-2; the receipted gate carries the host evidence.
    final hostTest = File(
      '../flutter_vscode/test/fixtures/host_extension/test/run.cjs',
    ).readAsStringSync();
    expect(hostTest, isNot(contains('observeBindings')));
    expect(hostTest, isNot(contains('observedBindingIds')));
    expect(hostTest, isNot(contains('FLUTTER_VSCODE_HOST_EVIDENCE_PATH')));
    expect(
      hostTest,
      isNot(matches(RegExp('(class|interface|method):vscode'))),
    );

    final runtime = File(
      '../flutter_vscode/test/fixtures/host_extension/host/lib/generated/vscode_runtime.g.dart',
    ).readAsStringSync();
    expect(runtime, isNot(contains('observeHostBindings')));
    expect(runtime, isNot(contains('observeHostCallback')));

    final bootstrap = File(
      '../flutter_vscode/test/fixtures/host_extension/host/bootstrap.cjs',
    ).readAsStringSync();
    expect(bootstrap, isNot(contains('bindingObservers')));
    expect(bootstrap, isNot(contains('observedBindingIds')));
    expect(bootstrap, isNot(contains('FLUTTER_VSCODE_HOST_EVIDENCE_PATH')));
  });
}
