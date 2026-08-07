part of '../binding_generator_test.dart';

/// Generation and the coverage ledger a successful review emits. The
/// Project-Derived Artifacts a build emits live in the flutter_vscode CLI
/// and are pinned by its own suite.
void registerEmissionOutputsTests() {
  test('validates the reviewed slice and emits an honest coverage ledger', () {
    final inventory = _readJson(
      'tool/bindings/ir/vscode-1.129.1.json',
    );
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final generator = VSCodeBindingGenerator();

    final first = generator.generateCoverageLedger(
      inventory: inventory,
      overrides: overrides,
    );
    final second = generator.generateCoverageLedger(
      inventory: inventory,
      overrides: overrides,
    );

    expect(first, second, reason: 'the review walk must be deterministic');
    expect(
      first,
      File('tool/bindings/coverage-ledger.json').readAsStringSync(),
      reason: 'the committed maintainer ledger must match a fresh review',
    );

    final coverage = (jsonDecode(first) as Map<Object?, Object?>)
        .cast<String, Object?>();
    expect(coverage['source'], {
      'vscodeVersion': '1.129.1',
      'inputSha256':
          'ee11e767c8ab76f6c0de8dc88222796147a6f0bc82f3a1ec644e41b39b52f2cd',
      'manifestSchemaSha256':
          'feddc98984b755a95644674910aa8c671e3259f137698c581ec7e2837cb058aa',
      'manifestValidatorSha256':
          'e8ae92aa491ab138b6f625acbbcbd7c53ff187098066ff13aebb64615202dde1',
      'commandsContributionSchemaSha256':
          'a85c943ae42b2cdef0403070f78cfb9dbe7bcdc1fce7c57bf9ca2234d1e36a33',
      'viewsContributionSchemaSha256':
          '17006750e3af4359fa5a518bf8dcb14beb060e98bc401245302a46030172a102',
      'configurationContributionSchemaSha256':
          'e9faa24f3835b807762aa069a8029c3b004b76a3e7f42ceddee598b71b26cb0a',
    });
    final pinnedOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final pinnedContracts =
        (pinnedOverrides['hostContracts']! as Map<Object?, Object?>)
            .cast<String, Object?>();
    expect(coverage['hostContracts'], {
      'checkpoint4ExtensionHost': {
        'boundary': 'vscodeExtensionHost',
        'artifact': 'tool/bindings/contracts/checkpoint4-extension-host.json',
        'artifactSha256':
            ((pinnedContracts['checkpoint4ExtensionHost']!
                    as Map<Object?, Object?>)['artifactSha256']!)
                .toString(),
      },
    });
    expect(coverage['hostEvidence'], {
      'kind': 'mechanicalAttribution',
      'meaning':
          '53 reviewed binding IDs cite one real Extension Host Contract '
          'whose receipted gate passed its surrounding native behavior; '
          'the retired per-member observation mechanism no longer '
          'contributes evidence.',
      'independentBehavioralContracts': false,
    });
    expect(coverage['scope'], {
      'name': 'checkpoint4FlutterViewSlice',
      'fullApiParity': false,
      'selectedTargets': 60,
      'implementedTargets': 53,
      'reviewedExcludedTargets': 7,
    });
    expect(coverage['inventory'], {
      'logicalEntries': 2982,
      'sourceOccurrences': 2982,
      'publicLogicalEntries': 2972,
      'nonPublicLogicalEntries': 10,
    });
    expect(coverage['exclusions'], {
      'reviewedSemanticOverrides': 7,
      'nonPublicVisibility': 10,
    });
    expect(coverage['summary'], {
      'discovered': 2982,
      'semanticsReviewed': 53,
      'semanticsExcluded': 17,
      'semanticsPending': 2912,
      'bindingsEmitted': 53,
      'bindingsExcluded': 17,
      'bindingsPending': 2912,
      'hostVerified': 53,
      'hostNotApplicable': 17,
      'hostPending': 2912,
    });
    final ledgerEntries = (coverage['entries']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    expect(ledgerEntries, hasLength(2982));
    expect(
      ledgerEntries.map((entry) => entry['id']).toList(),
      orderedEquals(
        ledgerEntries.map((entry) => entry['id']).toList()..sort(),
      ),
    );
    expect(
      ledgerEntries.singleWhere(
        (entry) => entry['id'] == 'class:vscode.Hover',
      ),
      containsPair('selected', true),
    );
    expect(
      ledgerEntries.singleWhere(
        (entry) => entry['id'] == 'class:vscode.Hover',
      )['host'],
      {'status': 'verified', 'contract': 'checkpoint4ExtensionHost'},
    );
    const webviewPostMessageId =
        'method:vscode.Webview.postMessage@a2972cc260d088838e09de8dc683393276ed8c03d172023d9a807a9d585d71a1';
    expect(
      ledgerEntries.singleWhere(
        (entry) => entry['id'] == webviewPostMessageId,
      ),
      allOf(
        containsPair('selected', true),
        containsPair('semantics', {
          'status': 'reviewed',
          'basis': 'semanticOverride',
          'strategy': 'thenableBoolMethod',
        }),
        containsPair('binding', {
          'status': 'emitted',
          'artifacts': [
            'packages/dart_vscode/lib/src/generated/vscode_dart_layer.g.dart',
          ],
        }),
        containsPair('host', {
          'status': 'verified',
          'contract': 'checkpoint4ExtensionHost',
        }),
      ),
    );
    expect(
      ledgerEntries.singleWhere(
        (entry) => entry['id'] == 'interface:vscode.WebviewPanelOptions',
      ),
      allOf(
        containsPair('selected', true),
        containsPair(
          'semantics',
          allOf(
            containsPair('status', 'excluded'),
            containsPair('strategy', 'reviewedExcluded'),
            containsPair(
              'reason',
              'The first Flutter View uses no WebviewPanelOptions fields.',
            ),
          ),
        ),
        containsPair('binding', {'status': 'excluded'}),
        containsPair('host', {'status': 'notApplicable'}),
      ),
    );
  });
}
