part of '../binding_generator_test.dart';

/// Generation and the durable Host Contract artifact and the bindings obliged to cite it.
void registerHostContractTests() {
  test('rejects an emitted binding without an executable Host Contract', () {
    final overrides = _overrides({
      'interface:vscode.Known': 'opaqueJsObject',
    });
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    (entries['interface:vscode.Known']! as Map<Object?, Object?>)
        .cast<String, Object?>()
        .remove('hostContract');

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_OVERRIDE',
        allOf(
          contains('interface:vscode.Known'),
          contains('Host Contract'),
        ),
      ),
    );
  });
  test('accepts the exact durable Host Contract schema', () {
    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      returnsNormally,
    );
  });
  test('rejects a well-formed Host Contract that no binding cites', () {
    final overrides = _overrides({
      'interface:vscode.Known': 'opaqueJsObject',
    });
    final contracts = (overrides['hostContracts']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    contracts['unusedContract'] = {
      'boundary': 'vscodeExtensionHost',
      'artifact': 'tool/bindings/contracts/unused-contract.json',
      'artifactSha256': '0' * 64,
    };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_OVERRIDE',
        allOf(contains('unusedContract'), contains('not cited')),
      ),
    );
  });
  test('rejects Host Contract IDs that are not lower camel case', () {
    final overrides = _readJson('tool/bindings/overrides/vscode-1.129.1.json');
    final contracts = (overrides['hostContracts']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    contracts['Checkpoint4ExtensionHost'] = contracts.remove(
      'checkpoint4ExtensionHost',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    for (final entry in entries.values) {
      final override = (entry! as Map<Object?, Object?>)
          .cast<String, Object?>();
      if (override['hostContract'] == 'checkpoint4ExtensionHost') {
        override['hostContract'] = 'Checkpoint4ExtensionHost';
      }
    }

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _readJson('tool/bindings/ir/vscode-1.129.1.json'),
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_OVERRIDE',
        contains('must be lower camel case'),
      ),
    );
  });
  test('rejects Semantic Overrides with an emptied Host Contract map', () {
    final overrides = _readJson('tool/bindings/overrides/vscode-1.129.1.json');
    (overrides['hostContracts']! as Map<Object?, Object?>).clear();

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _readJson('tool/bindings/ir/vscode-1.129.1.json'),
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_OVERRIDE',
        contains('at least one executable Host Contract'),
      ),
    );
  });
  test('rejects Host Contracts outside the durable artifact schema', () {
    final malformedContracts = <String, Map<String, Object?>>{
      'artifact outside tool/bindings/contracts': {
        'boundary': 'vscodeExtensionHost',
        'artifact': 'docs/test-extension-host.json',
        'artifactSha256': '0' * 64,
      },
      'non-canonical artifact filename': {
        'boundary': 'vscodeExtensionHost',
        'artifact': 'tool/bindings/contracts/test extension host.json',
        'artifactSha256': '0' * 64,
      },
      'malformed artifact checksum': {
        'boundary': 'vscodeExtensionHost',
        'artifact': 'tool/bindings/contracts/test-extension-host.json',
        'artifactSha256': 'A' * 64,
      },
      'extra unpinned field': {
        'boundary': 'vscodeExtensionHost',
        'artifact': 'tool/bindings/contracts/test-extension-host.json',
        'artifactSha256': '0' * 64,
        'runner': 'scripts/test_host_extension.sh',
      },
    };

    for (final malformed in malformedContracts.entries) {
      final overrides = _overrides({
        'interface:vscode.Known': 'opaqueJsObject',
      });
      final contracts = (overrides['hostContracts']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      (contracts['testExtensionHost']! as Map<Object?, Object?>)
          .cast<String, Object?>()
        ..clear()
        ..addAll(malformed.value);

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: _inventory(['interface:vscode.Known']),
          overrides: overrides,
        ),
        _throwsGeneration('INVALID_OVERRIDE', contains('Host Contract')),
        reason: malformed.key,
      );
    }
  });
}
