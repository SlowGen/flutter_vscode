part of '../binding_generator_test.dart';

/// Generation and structural invariants of the imported IR: ordering, scope, heritage, and value ranges.
void registerIrStructureTests() {
  test('rejects an unclassified entry inside the selected closure', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides(
          const {},
          targets: const ['interface:vscode.Known'],
        ),
      ),
      _throwsGeneration('MISSING_OVERRIDE', contains('interface:vscode.Known')),
    );
  });
  test('rejects duplicate targets instead of silently collapsing them', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides(
          {'interface:vscode.Known': 'opaqueJsObject'},
          targets: const [
            'interface:vscode.Known',
            'interface:vscode.Known',
          ],
        ),
      ),
      _throwsGeneration(
        'DUPLICATE_TARGET_ID',
        contains('interface:vscode.Known'),
      ),
    );
  });
  test('rejects a string enum value reviewed as an integer binding', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final enumMemberId = _entryIdForStrategy(entries, 'intEnumMember');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final enumMember = declarations.singleWhere(
      (declaration) => declaration['id'] == enumMemberId,
    );
    final initializer = (enumMember['initializer']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    initializer['value'] = '1';
    final override = (entries[enumMemberId]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    override['declarationSha256'] = computeDeclarationFingerprint(
      enumMember.cast<String, Object?>(),
    );

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'WALKING_SLICE_PROFILE_MISMATCH',
        contains(enumMemberId),
      ),
    );
  });
  test('rejects abstract classes behind emitted native constructors', () {
    for (final constructorStrategy in const [
      'markdownHoverConstructor',
      'markdownStringConstructor',
      'numericRangeConstructor',
    ]) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final entries = (overrides['entries']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final constructorId = _entryIdForStrategy(
        entries,
        constructorStrategy,
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final constructor = declarations.singleWhere(
        (candidate) => candidate['id'] == constructorId,
      );
      final classId = constructor['parentId']! as String;
      final classDeclaration = declarations
          .singleWhere((candidate) => candidate['id'] == classId)
          .cast<String, Object?>();
      classDeclaration['abstract'] = true;
      final classOverride = (entries[classId]! as Map<Object?, Object?>)
          .cast<String, Object?>();
      classOverride['declarationSha256'] = computeDeclarationFingerprint(
        classDeclaration,
      );

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(classId)),
        reason: constructorStrategy,
      );
    }
  });
  test('rejects a string selector projection without string support', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(
      entries,
      'stringSelectorProjection',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final union = (declaration['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    (union['types']! as List<Object?>).removeWhere(
      (candidate) =>
          candidate is Map<Object?, Object?> &&
          candidate['kind'] == 'primitive' &&
          candidate['name'] == 'string',
    );
    final override = (entries[declarationId]! as Map<Object?, Object?>)
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
        'WALKING_SLICE_PROFILE_MISMATCH',
        contains(declarationId),
      ),
    );
  });
  test('rejects an event value that references the wrong host type', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final eventId = entries.entries.singleWhere((entry) {
      final override = (entry.value! as Map<Object?, Object?>)
          .cast<String, Object?>();
      if (override['strategy'] != 'eventValue') {
        return false;
      }
      final declaration = declarations.singleWhere(
        (candidate) => candidate['id'] == entry.key,
      );
      return declaration['kind'] == 'variable';
    }).key;
    final event = declarations.singleWhere(
      (declaration) => declaration['id'] == eventId,
    );
    final type = (event['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    type['name'] = 'Thenable';
    final override = (entries[eventId]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    override['declarationSha256'] = computeDeclarationFingerprint(
      event.cast<String, Object?>(),
    );

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(eventId)),
    );
  });
  test('rejects incompatible relationships between selected strategies', () {
    void expectRejected(
      String strategy,
      void Function(Map<String, Object?> declaration) mutate,
    ) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final entries = (overrides['entries']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final declarationId = _entryIdForStrategy(entries, strategy);
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == declarationId)
          .cast<String, Object?>();
      mutate(declaration);
      final mutatedId = _synchronizeProducerMutation(
        inventory,
        overrides,
        declarationId,
      );

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        _throwsGeneration(
          'WALKING_SLICE_PROFILE_MISMATCH',
          contains(mutatedId),
        ),
        reason: strategy,
      );
    }

    expectRejected('commandExecution', (declaration) {
      final returnType = (declaration['returnType']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      returnType['name'] = 'Event';
    });
    expectRejected('thenableBoolMethod', (declaration) {
      final returnType = (declaration['returnType']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      returnType['name'] = 'Event';
    });
    expectRejected('webviewPanelCreation', (declaration) {
      final returnType = (declaration['returnType']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      returnType['name'] = 'Webview';
    });
    expectRejected('hoverProviderRegistration', (declaration) {
      final parameters = (declaration['parameters']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final providerType = (parameters[1]['type']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      providerType['name'] = 'CancellationToken';
    });
    expectRejected('providerCallback', (declaration) {
      final returnType = (declaration['returnType']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      returnType['name'] = 'Thenable';
    });
    expectRejected('uriArrayObjectField', (declaration) {
      final operator = (declaration['type']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final array = (operator['type']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final elementType = (array['elementType']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      elementType['name'] = 'TextDocument';
    });
  });
  test('rejects a selected declaration whose reviewed shape changed', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final lineProperty = declarations.singleWhere(
      (entry) =>
          entry['id'] == r'property:class:vscode.Position/$instance/line',
    );
    final type = (lineProperty['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    type['name'] = 'string';

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'STALE_SEMANTIC_OVERRIDE',
        contains(r'property:class:vscode.Position/$instance/line'),
      ),
    );
  });
  test('rejects invalid selected declaration scalar values', () {
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
    declaration['deprecated'] = 'future';
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
        allOf(contains('.deprecated'), contains('future')),
      ),
    );
  });
  final sourceReceiptCases =
      <
        ({
          String name,
          void Function(Map<String, Object?>, Map<String, Object?>) mutate,
        })
      >[
        (
          name: 'detached API digest',
          mutate: (inventory, overrides) {
            final source = (inventory['source']! as Map<Object?, Object?>)
                .cast<String, Object?>();
            source['inputSha256'] = '0' * 64;
          },
        ),
        (
          name: 'detached manifest projection digest',
          mutate: (inventory, overrides) {
            (inventory['manifestSchema']!
                    as Map<Object?, Object?>)['inputSha256'] =
                '0' * 64;
            overrides['manifestSchemaSha256'] = '0' * 64;
          },
        ),
        (
          name: 'detached manifest-validator projection digest',
          mutate: (inventory, overrides) {
            (inventory['manifestValidator']!
                    as Map<Object?, Object?>)['inputSha256'] =
                '0' * 64;
            overrides['manifestValidatorSha256'] = '0' * 64;
          },
        ),
        (
          name: 'detached commands projection digest',
          mutate: (inventory, overrides) {
            final schemas =
                (inventory['contributionSchemas']! as Map<Object?, Object?>)
                    .cast<String, Object?>();
            (schemas['commands']! as Map<Object?, Object?>)['inputSha256'] =
                '0' * 64;
            overrides['commandsContributionSchemaSha256'] = '0' * 64;
          },
        ),
        (
          name: 'receipt from another product version',
          mutate: (inventory, overrides) {
            final input = _sourceInput(inventory, 'apiDeclarations');
            input['version'] = '1.128.0';
          },
        ),
        (
          name: 'noncanonical official source URL',
          mutate: (inventory, overrides) {
            final input = _sourceInput(inventory, 'apiDeclarations');
            input['source'] = 'https://example.invalid/vscode.d.ts';
          },
        ),
        (
          name: 'missing validation-helper receipt',
          mutate: (inventory, overrides) {
            final source = (inventory['source']! as Map<Object?, Object?>)
                .cast<String, Object?>();
            (source['inputs']! as List<Object?>).removeWhere(
              (value) =>
                  (value! as Map<Object?, Object?>)['kind'] ==
                  'contributionValidationHelperSource',
            );
          },
        ),
        (
          name: 'duplicate API receipt',
          mutate: (inventory, overrides) {
            final source = (inventory['source']! as Map<Object?, Object?>)
                .cast<String, Object?>();
            (source['inputs']! as List<Object?>).add(
              Map<String, Object?>.of(
                _sourceInput(inventory, 'apiDeclarations'),
              ),
            );
          },
        ),
      ];
  for (final testCase in sourceReceiptCases) {
    test('rejects ${testCase.name}', () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      testCase.mutate(inventory, overrides);

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          contains('inventory.source'),
        ),
      );
    });
  }
  final impossibleOccurrenceCases = <(String, String)>[
    ('class', 'class:vscode.BranchCoverage'),
    ('type alias', 'typeAlias:vscode.AuthenticationForceNewSessionOptions'),
    (
      'enum member',
      'enumMember:enum:vscode.ChatResultFeedbackKind/Helpful',
    ),
    ('const variable', 'variable:vscode.authentication.onDidChangeSessions'),
  ];
  for (final testCase in impossibleOccurrenceCases) {
    test('rejects occurrenceCount on a nonmergeable ${testCase.$1}', () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      declarations.singleWhere(
        (declaration) => declaration['id'] == testCase.$2,
      )['occurrenceCount'] = 2;

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          contains('occurrenceCount'),
        ),
      );
    });
  }
  test('rejects integers outside the JavaScript safe range', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations.firstWhere(
      (candidate) => candidate['kind'] == 'enumMember',
    );
    (declaration['initializer']! as Map<Object?, Object?>)['value'] =
        9007199254740992;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('safe integer')),
    );
  });
  final manifestProjectionCases =
      <({String name, void Function(Map<String, Object?>) mutate})>[
        (
          name: 'unknown manifest projection fields',
          mutate: (inventory) {
            (inventory['manifestSchema']!
                    as Map<Object?, Object?>)['futureSemantics'] =
                true;
          },
        ),
        (
          name: 'unprojected nested manifest schema changes',
          mutate: (inventory) {
            final schema =
                (inventory['manifestSchema']! as Map<Object?, Object?>)
                    .cast<String, Object?>();
            final properties = (schema['properties']! as Map<Object?, Object?>)
                .cast<String, Object?>();
            final engines = (properties['engines']! as Map<Object?, Object?>)
                .cast<String, Object?>();
            final engineProperties =
                (engines['properties']! as Map<Object?, Object?>)
                    .cast<String, Object?>();
            (engineProperties['vscode']! as Map<Object?, Object?>)['type'] =
                'number';
          },
        ),
      ];
  for (final testCase in manifestProjectionCases) {
    test('rejects ${testCase.name}', () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      testCase.mutate(inventory);

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          contains('inventory.manifestSchema'),
        ),
      );
    });
  }
  test('rejects declaration arrays outside producer sort order', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = inventory['declarations']! as List<Object?>;
    final first = declarations[0];
    declarations[0] = declarations[1];
    declarations[1] = first;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('sort order')),
    );
  });
  final incompatibleParentCases = <(String, String, String)>[
    ('constructor', 'constructor', 'interface:vscode.AuthenticationProvider'),
    ('enum member', 'enumMember', 'class:vscode.BranchCoverage'),
    ('property', 'property', 'enum:vscode.ChatResultFeedbackKind'),
    ('method', 'method', 'enum:vscode.ChatResultFeedbackKind'),
  ];
  for (final testCase in incompatibleParentCases) {
    test('rejects ${testCase.$1} declarations under incompatible parents', () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final declaration = _unselectedDeclarationOfKind(
        inventory,
        testCase.$2,
      );
      _reanchorDeclaration(inventory, declaration, testCase.$3);
      _sortDeclarationsLikeProducer(inventory);

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration('INVALID_GENERATOR_INPUT', contains('parentId')),
      );
    });
  }
  test('rejects non-reference heritage nodes', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final targets =
        (_readJson(
                  'tool/bindings/overrides/vscode-1.129.1.json',
                )['targets']!
                as List<Object?>)
            .cast<String>()
            .toSet();
    final declaration = declarations.firstWhere(
      (candidate) =>
          candidate['kind'] == 'interface' &&
          (candidate['extends']! as List<Object?>).isNotEmpty &&
          !targets.contains(candidate['id']),
    );
    (declaration['extends']! as List<Object?>).first = {
      'kind': 'primitive',
      'name': 'string',
    };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('extends'), contains('reference')),
      ),
    );
  });
  test('rejects overload ordinals outside producer group order', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declaration = _soleUnselectedCallable(inventory);
    declaration['overloadOrdinal'] = 99;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('overloadOrdinal')),
    );
  });
  final contextFlagCases = <(String, String)>[
    ('static', 'property'),
    ('abstract', 'method'),
  ];
  for (final testCase in contextFlagCases) {
    test('rejects ${testCase.$1} ${testCase.$2}s in interface contexts', () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations.firstWhere((candidate) {
        if (candidate['kind'] != testCase.$2) {
          return false;
        }
        return declarations.any(
          (parent) =>
              parent['id'] == candidate['parentId'] &&
              parent['kind'] == 'interface',
        );
      });
      declaration[testCase.$1] = true;

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration('INVALID_GENERATOR_INPUT', contains(testCase.$1)),
      );
    });
  }
}
