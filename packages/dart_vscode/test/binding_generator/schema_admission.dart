part of '../binding_generator_test.dart';

/// Generation and inputs whose schema version, unknown fields, digests, or pins this generator refuses.
void registerSchemaAdmissionTests() {
  test('rejects an unsupported inventory schema version', () {
    final inventory = _inventory(['interface:vscode.Known'])
      ..['schemaVersion'] = 999;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'UNSUPPORTED_INPUT_SCHEMA_VERSION',
        contains('inventory.schemaVersion'),
      ),
    );
  });
  test('rejects unknown top-level inventory fields', () {
    final inventory = _inventory(['interface:vscode.Known'])
      ..['futureSemantic'] = true;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('inventory'), contains('futureSemantic')),
      ),
    );
  });
  test('rejects unknown source identity fields', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final source = (inventory['source']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    source['futureSemantic'] = true;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('inventory.source'), contains('futureSemantic')),
      ),
    );
  });
  test('rejects malformed matching root evidence digests', () {
    const cases = [
      (
        overrideField: 'manifestSchemaSha256',
        inventoryPath: 'inventory.manifestSchema.inputSha256',
      ),
      (
        overrideField: 'manifestValidatorSha256',
        inventoryPath: 'inventory.manifestValidator.inputSha256',
      ),
      (
        overrideField: 'commandsContributionSchemaSha256',
        inventoryPath: 'inventory.contributionSchemas.commands.inputSha256',
      ),
    ];

    for (final testCase in cases) {
      final inventory = _inventory(['interface:vscode.Known']);
      switch (testCase.overrideField) {
        case 'manifestSchemaSha256':
          (inventory['manifestSchema']!
                  as Map<Object?, Object?>)['inputSha256'] =
              'x';
        case 'manifestValidatorSha256':
          (inventory['manifestValidator']!
                  as Map<Object?, Object?>)['inputSha256'] =
              'x';
        case 'commandsContributionSchemaSha256':
          final contributionSchemas =
              inventory['contributionSchemas']! as Map<Object?, Object?>;
          (contributionSchemas['commands']!
                  as Map<Object?, Object?>)['inputSha256'] =
              'x';
      }
      final overrides = _overrides({
        'interface:vscode.Known': 'opaqueJsObject',
      })..[testCase.overrideField] = 'x';

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          allOf(
            contains(testCase.inventoryPath),
            contains('lowercase SHA-256'),
          ),
        ),
        reason: testCase.overrideField,
      );
    }
  });
  test('rejects malformed override and primary input digests', () {
    final malformedOverride = _overrides({
      'interface:vscode.Known': 'opaqueJsObject',
    })..['manifestSchemaSha256'] = 'x';
    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: malformedOverride,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(
          contains('overrides.manifestSchemaSha256'),
          contains('lowercase SHA-256'),
        ),
      ),
    );

    final malformedInventory = _inventory(['interface:vscode.Known']);
    final source = (malformedInventory['source']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    source['inputSha256'] = 'x';
    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: malformedInventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(
          contains('inventory.source.inputSha256'),
          contains('lowercase SHA-256'),
        ),
      ),
    );
  });
  test(
    'rejects unknown selected declaration fields after fingerprint refresh',
    () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final entries = (overrides['entries']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final id = _entryIdForStrategy(entries, 'commandRegistration');
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == id)
          .cast<String, Object?>();
      declaration['futureSemantic'] = true;
      final override = (entries[id]! as Map<Object?, Object?>)
          .cast<String, Object?>();
      override['declarationSha256'] = computeDeclarationFingerprint(
        declaration,
      );

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          allOf(
            contains('inventory.declarations'),
            contains('futureSemantic'),
          ),
        ),
      );
    },
  );
  test('rejects unknown selected declaration coverage fields', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final id = _entryIdForStrategy(entries, 'commandRegistration');
    final declaration = declarations.singleWhere(
      (candidate) => candidate['id'] == id,
    );
    final coverage = (declaration['coverage']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    coverage['inference'] = 'permitted';

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('.coverage'), contains('inference')),
      ),
    );
  });
  test('rejects unknown fields in recursively nested selected types', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final id = _entryIdForStrategy(entries, 'commandRegistration');
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == id)
        .cast<String, Object?>();
    final parameters = (declaration['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final callback = (parameters[1]['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final callbackParameters = (callback['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final argumentArray =
        (callbackParameters.single['type']! as Map<Object?, Object?>)
            .cast<String, Object?>();
    final elementType = (argumentArray['elementType']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    elementType['futureTypeMeaning'] = true;
    final override = (entries[id]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    override['declarationSha256'] = computeDeclarationFingerprint(
      declaration,
    );

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('.elementType'), contains('futureTypeMeaning')),
      ),
    );
  });
  test('rejects unknown fields in recursively nested selected parameters', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final id = _entryIdForStrategy(entries, 'commandRegistration');
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == id)
        .cast<String, Object?>();
    final parameters = (declaration['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final callback = (parameters[1]['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final callbackParameters = (callback['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    callbackParameters.single['futureParameterMeaning'] = true;
    final override = (entries[id]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    override['declarationSha256'] = computeDeclarationFingerprint(
      declaration,
    );

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(
          contains('.parameters[0]'),
          contains('futureParameterMeaning'),
        ),
      ),
    );
  });
  test(
    'rejects unknown fields in recursively nested selected type parameters',
    () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final entries = (overrides['entries']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final id = _entryIdForStrategy(entries, 'commandRegistration');
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == id)
          .cast<String, Object?>();
      final parameters = (declaration['parameters']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final callback = (parameters[1]['type']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      (callback['typeParameters']! as List<Object?>).add({
        'name': 'T',
        'futureTypeParameterMeaning': true,
      });
      final override = (entries[id]! as Map<Object?, Object?>)
          .cast<String, Object?>();
      override['declarationSha256'] = computeDeclarationFingerprint(
        declaration,
      );

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          allOf(
            contains('.typeParameters[0]'),
            contains('futureTypeParameterMeaning'),
          ),
        ),
      );
    },
  );
  test('rejects unknown fields in selected canonical signatures', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final id = _entryIdForStrategy(entries, 'commandRegistration');
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == id)
        .cast<String, Object?>();
    final signature =
        (jsonDecode(declaration['canonicalSignature']! as String)
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    signature['futureSignatureMeaning'] = true;
    declaration['canonicalSignature'] = jsonEncode(signature);
    _refreshProducerIdentity(inventory, overrides, id);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(
          contains('.canonicalSignature'),
          contains('futureSignatureMeaning'),
        ),
      ),
    );
  });
  test('rejects unknown fields in selected enum initializers', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final id = _entryIdForStrategy(entries, 'intEnumMember');
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == id)
        .cast<String, Object?>();
    final initializer = (declaration['initializer']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    initializer['futureInitializerMeaning'] = true;
    final override = (entries[id]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    override['declarationSha256'] = computeDeclarationFingerprint(
      declaration,
    );

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(
          contains('.initializer'),
          contains('futureInitializerMeaning'),
        ),
      ),
    );
  });
}
