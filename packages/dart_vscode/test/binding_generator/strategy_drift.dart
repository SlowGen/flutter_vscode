part of '../binding_generator_test.dart';

/// Generation and emitted strategies drifting from the declarations and members they were selected for.
void registerStrategyDriftTests() {
  test('rejects a walking-slice strategy assigned to the wrong IR entry', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final commandExecutionId = _entryIdForStrategy(
      entries,
      'commandExecution',
    );
    final commandRegistrationId = _entryIdForStrategy(
      entries,
      'commandRegistration',
    );
    final commandExecution =
        (entries[commandExecutionId]! as Map<Object?, Object?>)
            .cast<String, Object?>();
    final commandRegistration =
        (entries[commandRegistrationId]! as Map<Object?, Object?>)
            .cast<String, Object?>();
    commandExecution['strategy'] = 'commandRegistration';
    commandRegistration['strategy'] = 'commandExecution';

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'WALKING_SLICE_PROFILE_MISMATCH',
        contains(commandExecutionId),
      ),
    );
  });
  test('rejects a Flutter View strategy assigned to the wrong IR entry', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    const htmlId = r'property:interface:vscode.Webview/$instance/html';
    final html = (entries[htmlId]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    html['strategy'] = 'stringGetterProjection';

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(htmlId)),
    );
  });
  test('rejects an optional member reviewed as a required projection', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final propertyId = entries.entries.firstWhere((entry) {
      final override = (entry.value! as Map<Object?, Object?>)
          .cast<String, Object?>();
      return override['strategy'] == 'intGetterProjection';
    }).key;
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final property = declarations.singleWhere(
      (declaration) => declaration['id'] == propertyId,
    );
    property['optional'] = true;
    final override = (entries[propertyId]! as Map<Object?, Object?>)
        .cast<String, Object?>();
    override['declarationSha256'] = computeDeclarationFingerprint(
      property.cast<String, Object?>(),
    );

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(propertyId)),
    );
  });
  test('rejects static drift for every emitted method strategy', () {
    const expectedStaticByStrategy = <String, bool>{
      'disposeMethod': false,
      'providerCallback': false,
      'thenableBoolMethod': false,
      'unaryUriMethod': false,
      'uriJoinPath': true,
      'uriToString': false,
    };
    final baseOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final baseEntries = (baseOverrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final cases = <({String id, String strategy, bool expectedStatic})>[
      for (final entry in baseEntries.entries)
        if (expectedStaticByStrategy.containsKey(
          (entry.value! as Map<Object?, Object?>)['strategy'],
        ))
          (
            id: entry.key,
            strategy:
                (entry.value! as Map<Object?, Object?>)['strategy']! as String,
            expectedStatic:
                expectedStaticByStrategy[(entry.value!
                    as Map<Object?, Object?>)['strategy']]!,
          ),
    ];

    for (final mutation in cases) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == mutation.id)
          .cast<String, Object?>();
      final producerCanBeStatic =
          declarations.singleWhere(
            (candidate) => candidate['id'] == declaration['parentId'],
          )['kind'] ==
          'class';
      declaration['static'] = !mutation.expectedStatic;
      final mutatedId = _synchronizeProducerMutation(
        inventory,
        overrides,
        mutation.id,
      );

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: overrides,
        ),
        throwsA(
          isA<VSCodeBindingGenerationException>()
              .having(
                (error) => error.code,
                'code',
                producerCanBeStatic
                    ? 'WALKING_SLICE_PROFILE_MISMATCH'
                    : 'INVALID_GENERATOR_INPUT',
              )
              .having(
                (error) => error.message,
                'message',
                producerCanBeStatic ? contains(mutatedId) : contains('.static'),
              ),
        ),
        reason: '${mutation.strategy}: ${mutation.id}',
      );
    }
  });
  test('rejects optional drift for every emitted method strategy', () {
    const methodStrategies = <String>{
      'disposeMethod',
      'providerCallback',
      'thenableBoolMethod',
      'unaryUriMethod',
      'uriJoinPath',
      'uriToString',
    };
    final baseOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final baseEntries = (baseOverrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final cases = <({String id, String strategy})>[
      for (final entry in baseEntries.entries)
        if (methodStrategies.contains(
          (entry.value! as Map<Object?, Object?>)['strategy'],
        ))
          (
            id: entry.key,
            strategy:
                (entry.value! as Map<Object?, Object?>)['strategy']! as String,
          ),
    ];

    for (final mutation in cases) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == mutation.id)
          .cast<String, Object?>();
      declaration['optional'] = true;
      final mutatedId = _synchronizeProducerMutation(
        inventory,
        overrides,
        mutation.id,
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
        reason: '${mutation.strategy}: ${mutation.id}',
      );
    }
  });
  test('rejects parameter flag drift for every emitted callable strategy', () {
    const requiredParameter = (optional: false, rest: false);
    const optionalParameter = (optional: true, rest: false);
    const restParameter = (optional: false, rest: true);
    const expectedShapes = <String, List<({bool optional, bool rest})>>{
      'commandExecution': [requiredParameter, restParameter],
      'commandRegistration': [
        requiredParameter,
        requiredParameter,
        optionalParameter,
      ],
      'eventSubscription': [
        requiredParameter,
        optionalParameter,
        optionalParameter,
      ],
      'hoverProviderRegistration': [
        requiredParameter,
        requiredParameter,
      ],
      'markdownHoverConstructor': [
        requiredParameter,
        optionalParameter,
      ],
      'markdownStringConstructor': [
        optionalParameter,
        optionalParameter,
      ],
      'numericRangeConstructor': [
        requiredParameter,
        requiredParameter,
        requiredParameter,
        requiredParameter,
      ],
      'providerCallback': [
        requiredParameter,
        requiredParameter,
        requiredParameter,
      ],
      'thenableBoolMethod': [requiredParameter],
      'unaryUriMethod': [requiredParameter],
      'uriJoinPath': [requiredParameter, restParameter],
      'uriToString': [optionalParameter],
      'webviewPanelCreation': [
        requiredParameter,
        requiredParameter,
        requiredParameter,
        optionalParameter,
      ],
    };

    for (final shape in expectedShapes.entries) {
      for (
        var parameterIndex = 0;
        parameterIndex < shape.value.length;
        parameterIndex += 1
      ) {
        for (final field in const ['optional', 'rest']) {
          final inventory = _readJson(
            'tool/bindings/ir/vscode-1.129.1.json',
          );
          final overrides = _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          );
          final entries = (overrides['entries']! as Map<Object?, Object?>)
              .cast<String, Object?>();
          final declarationId = _entryIdForStrategy(entries, shape.key);
          final declarations = (inventory['declarations']! as List<Object?>)
              .cast<Map<Object?, Object?>>();
          final declaration = declarations
              .singleWhere((candidate) => candidate['id'] == declarationId)
              .cast<String, Object?>();
          final parameters = (declaration['parameters']! as List<Object?>)
              .cast<Map<Object?, Object?>>();
          final expected = shape.value[parameterIndex];
          parameters[parameterIndex][field] = switch (field) {
            'optional' => !expected.optional,
            'rest' => !expected.rest,
            _ => throw StateError('Unknown parameter field $field'),
          };
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
            reason: '${shape.key} parameter $parameterIndex $field',
          );
        }
      }
    }
  });
  test('rejects JSAny parameter types detached from emitted JSAny', () {
    const cases = <String, int>{
      'commandRegistration': 2,
      'eventSubscription': 1,
    };
    for (final mutation in cases.entries) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final entries = (overrides['entries']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      final declarationId = _entryIdForStrategy(entries, mutation.key);
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == declarationId)
          .cast<String, Object?>();
      final parameters = (declaration['parameters']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      parameters[mutation.value]['type'] = <String, Object?>{
        'kind': 'primitive',
        'name': 'string',
      };
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
        reason: mutation.key,
      );
    }
  });
  test('rejects Uri.joinPath rest elements detached from emitted JSString', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(entries, 'uriJoinPath');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final parameters = (declaration['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final restType = (parameters[1]['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    restType['elementType'] = <String, Object?>{
      'kind': 'primitive',
      'name': 'number',
    };
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
      _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(mutatedId)),
    );
  });
  test('rejects Webview message events detached from their emitted value', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declarationId = entries.entries.singleWhere((entry) {
      final override = entry.value! as Map<Object?, Object?>;
      if (override['strategy'] != 'eventValue') {
        return false;
      }
      return declarations.singleWhere(
            (candidate) => candidate['id'] == entry.key,
          )['kind'] ==
          'property';
    }).key;
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final type = (declaration['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    type['typeArguments'] = <Object?>[
      <String, Object?>{'kind': 'primitive', 'name': 'string'},
    ];
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
  test('rejects Webview postMessage inputs detached from emitted JSAny', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(entries, 'thenableBoolMethod');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final parameters = (declaration['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    parameters.single['type'] = <String, Object?>{
      'kind': 'primitive',
      'name': 'string',
    };
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
      _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(mutatedId)),
    );
  });
  test('rejects inconsistent emitted disposal member names', () {
    final baseOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final baseEntries = (baseOverrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final disposeIds = <String>[
      for (final entry in baseEntries.entries)
        if ((entry.value! as Map<Object?, Object?>)['strategy'] ==
            'disposeMethod')
          entry.key,
    ];
    expect(disposeIds, hasLength(3));

    for (final declarationId in disposeIds) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final mutatedId = _renameProducerDeclaration(
        inventory,
        overrides,
        declarationId,
        'release',
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
        reason: declarationId,
      );
    }
  });
  test('rejects return-type drift for emitted disposal methods', () {
    final baseOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final baseEntries = (baseOverrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final disposeIds = <String>[
      for (final entry in baseEntries.entries)
        if ((entry.value! as Map<Object?, Object?>)['strategy'] ==
            'disposeMethod')
          entry.key,
    ];

    for (final declarationId in disposeIds) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == declarationId)
          .cast<String, Object?>();
      declaration['returnType'] = <String, Object?>{
        'kind': 'primitive',
        'name': 'void',
      };
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
        reason: declarationId,
      );
    }
  });
  const producerDeclarationKinds = {
    'namespace',
    'interface',
    'class',
    'enum',
    'enumMember',
    'typeAlias',
    'variable',
    'property',
    'function',
    'constructor',
    'callSignature',
    'method',
    'indexSignature',
    'typeLiteral',
  };
  const derivedDeclarationFields = {
    'id',
    'name',
    'qualifiedName',
    'parentId',
  };
  for (final kind in producerDeclarationKinds) {
    for (final field in derivedDeclarationFields) {
      test('rejects $kind declarations with a detached $field', () {
        final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
        final declaration = _unselectedDeclarationOfKind(inventory, kind);
        declaration[field] = switch (field) {
          'id' => '${declaration[field]}-drift',
          'name' => '${declaration[field]}Drift',
          'qualifiedName' => '${declaration[field]}.drift',
          'parentId' => 'namespace:vscode.missing',
          _ => throw StateError('unreachable'),
        };
        _sortDeclarationsLikeProducer(inventory);

        expect(
          () => VSCodeBindingGenerator().generateCoverageLedger(
            inventory: inventory,
            overrides: _readJson(
              'tool/bindings/overrides/vscode-1.129.1.json',
            ),
          ),
          _throwsGeneration('INVALID_GENERATOR_INPUT', contains(field)),
        );
      });
    }
  }
  test('rejects variable constant flags detached from declarationKind', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations.firstWhere(
      (candidate) => candidate['declarationKind'] == 'let',
    );
    declaration['constant'] = true;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('constant'), contains('declarationKind')),
      ),
    );
  });
  test('rejects registered shape members with malformed values', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson('tool/bindings/overrides/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final literal = declarations
        .firstWhere(
          (candidate) =>
              candidate['kind'] == 'typeLiteral' &&
              declarations.any(
                (child) =>
                    child['parentId'] == candidate['id'] &&
                    child['kind'] == 'method',
              ),
        )
        .cast<String, Object?>();
    final shape =
        (jsonDecode(jsonEncode(literal['shape'])) as Map<Object?, Object?>)
            .cast<String, Object?>();
    final members = (shape['members']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    members.firstWhere((member) => member['kind'] == 'method')['name'] = null;
    literal['shape'] = shape;
    final shapeHash = _shapeHash(shape);
    final oldId = literal['id']! as String;
    literal['shapeHash'] = shapeHash;
    _replaceRegisteredTypeLiteralShapeHash(inventory, oldId, shapeHash);
    _reindexProducerSubtree(inventory, overrides, oldId);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        contains('unsupported member schema'),
      ),
    );
  });
}
