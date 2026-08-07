part of '../binding_generator_test.dart';

/// Generation and generics: arity, constraints, and the type arguments an
/// emitted binding carries or must not carry.
void registerGenericsTests() {
  test('rejects generic arity drift in emitted generic bindings', () {
    for (final strategy in const [
      'commandExecution',
      'eventType',
      'providerResultProjection',
      'thenableFutureBridge',
    ]) {
      for (final typeParameterCount in const [0, 2]) {
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
        declaration['typeParameters'] = <Object?>[
          for (var index = 0; index < typeParameterCount; index += 1)
            <String, Object?>{'name': 'T$index'},
        ];
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
          reason: '$strategy with $typeParameterCount type parameters',
        );
      }
    }
  });

  test('rejects constraints and defaults on emitted generic bindings', () {
    for (final strategy in const [
      'commandExecution',
      'eventType',
      'providerResultProjection',
      'thenableFutureBridge',
    ]) {
      for (final field in const ['constraint', 'default']) {
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
        final typeParameters = (declaration['typeParameters']! as List<Object?>)
            .cast<Map<Object?, Object?>>();
        typeParameters.single[field] = <String, Object?>{
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
          reason: '$strategy type parameter $field',
        );
      }
    }
  });

  test('rejects generics on emitted non-generic callables', () {
    const strategies = <String>{
      'commandRegistration',
      'disposeMethod',
      'eventSubscription',
      'hoverProviderRegistration',
      'markdownHoverConstructor',
      'markdownStringConstructor',
      'numericRangeConstructor',
      'providerCallback',
      'thenableBoolMethod',
      'unaryUriMethod',
      'uriJoinPath',
      'uriToString',
      'webviewPanelCreation',
    };
    final baseOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final baseEntries = (baseOverrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final cases = <({String id, String strategy})>[
      for (final entry in baseEntries.entries)
        if (strategies.contains(
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
      declaration['typeParameters'] = <Object?>[
        <String, Object?>{'name': 'T'},
      ];
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

  test('rejects generics on emitted non-generic interface bindings', () {
    for (final strategy in const ['jsObjectLiteral', 'providerObject']) {
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
      declaration['typeParameters'] = <Object?>[
        <String, Object?>{'name': 'T'},
      ];
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
  });

  test('rejects generics on emitted non-generic native host types', () {
    const strategies = {'nativeJsClass', 'opaqueHostObject'};
    final baseOverrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final baseEntries = (baseOverrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final cases = <String>[
      for (final entry in baseEntries.entries)
        if (strategies.contains(
          (entry.value! as Map<Object?, Object?>)['strategy'],
        ))
          entry.key,
    ];

    for (final declarationId in cases) {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final overrides = _readJson(
        'tool/bindings/overrides/vscode-1.129.1.json',
      );
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      final declaration = declarations
          .singleWhere((candidate) => candidate['id'] == declarationId)
          .cast<String, Object?>();
      declaration['typeParameters'] = <Object?>[
        <String, Object?>{'name': 'T'},
      ];
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

  test('rejects Event listeners detached from the Event generic', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(entries, 'eventSubscription');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final parameters = (declaration['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final listener = (parameters.first['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final listenerParameters = (listener['parameters']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    listenerParameters.single['type'] = <String, Object?>{
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

  test('rejects ProviderResult unions detached from their generic', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(
      entries,
      'providerResultProjection',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final union = (declaration['type']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final types = (union['types']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    types.first
      ..clear()
      ..addAll(<String, Object?>{
        'kind': 'primitive',
        'name': 'string',
      });
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

  test('rejects raw member types in generic-scoped inline shapes', () {
    final inventory = _inventory(['interface:vscode.Box']);
    final declaration =
        (inventory['declarations']! as List<Object?>).single!
            as Map<String, Object?>;
    final shape = <String, Object?>{
      'members': [
        {
          'kind': 'property',
          'name': 'callback',
          'optional': false,
          'readonly': false,
          'type': {
            'kind': 'function',
            'typeParameters': <Object?>[],
            'parameters': <Object?>[],
            'returnType': {'kind': 'primitive', 'name': 'void'},
            'canonicalSignature': jsonEncode({
              'typeParameters': <Object?>[],
              'parameters': <Object?>[],
              'returnType': {'kind': 'primitive', 'name': 'void'},
            }),
          },
        },
      ],
    };
    declaration['typeParameters'] = [
      {
        'name': 'T',
        'constraint': {
          'kind': 'typeLiteral',
          'shape': shape,
          'shapeHash': _shapeHash(shape),
        },
      },
    ];
    final overrides = _schemaOverrideFor(declaration);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        contains('.shape.members[0].type'),
      ),
    );
  });

  test('rejects raw generic references in parent-scoped signatures', () {
    final inventory = _inventory(['interface:vscode.Box']);
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final parent = declarations.single;
    parent['typeParameters'] = [
      <String, Object?>{'name': 'T'},
    ];
    final canonicalSignature = jsonEncode({
      'typeParameters': <Object?>[],
      'parameters': <Object?>[],
      'returnType': {
        'kind': 'reference',
        'name': 'T',
        'typeArguments': <Object?>[],
      },
      'static': false,
      'optional': false,
    });
    final methodId =
        'method:vscode.Box.read@${_sha256String(canonicalSignature)}';
    declarations.add({
      'id': methodId,
      'kind': 'method',
      'name': 'read',
      'qualifiedName': 'vscode.Box.read',
      'parentId': parent['id'],
      'deprecated': false,
      'visibility': 'public',
      'overloadOrdinal': 0,
      'canonicalSignature': canonicalSignature,
      'typeParameters': <Object?>[],
      'parameters': <Object?>[],
      'returnType': {
        'kind': 'reference',
        'name': 'T',
        'typeArguments': <Object?>[],
      },
      'static': false,
      'optional': false,
      'abstract': false,
      'coverage': _pendingCoverage(),
    });
    final overrides = _schemaOverrideFor(parent);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('.canonicalSignature'), contains('T')),
      ),
    );
  });

  test('rejects out-of-scope canonical refs in inline generic shapes', () {
    final inventory = _inventory(['interface:vscode.Box']);
    final declaration =
        (inventory['declarations']! as List<Object?>).single!
            as Map<String, Object?>;
    final shape = <String, Object?>{
      'members': [
        {
          'kind': 'property',
          'name': 'value',
          'optional': false,
          'readonly': false,
          'type': {'kind': 'typeParameter', 'index': 1},
        },
      ],
    };
    declaration['typeParameters'] = [
      {
        'name': 'T',
        'constraint': {
          'kind': 'typeLiteral',
          'shape': shape,
          'shapeHash': _shapeHash(shape),
        },
      },
    ];
    final overrides = _schemaOverrideFor(declaration);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('typeParameter'), contains('index')),
      ),
    );
  });

  test('accepts canonical type parameters in scoped inline shapes', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final declaration =
        (inventory['declarations']! as List<Object?>).single!
            as Map<String, Object?>;
    final shape = <String, Object?>{
      'members': [
        {
          'kind': 'property',
          'name': 'value',
          'optional': false,
          'readonly': false,
          'type': {'kind': 'typeParameter', 'index': 0},
        },
      ],
    };
    declaration['typeParameters'] = [
      {
        'name': 'T',
        'constraint': {
          'kind': 'typeLiteral',
          'shapeHash': _shapeHash(shape),
          'shape': shape,
        },
      },
    ];
    final overrides = _overrides({
      'interface:vscode.Known': 'opaqueJsObject',
    });
    final entry =
        ((overrides['entries']!
                    as Map<Object?, Object?>)['interface:vscode.Known']!
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    entry['declarationSha256'] = computeDeclarationFingerprint(declaration);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      returnsNormally,
    );
  });
}
