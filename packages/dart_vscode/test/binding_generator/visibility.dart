part of '../binding_generator_test.dart';

/// Generation and visibility inherited across owners, references, and binding targets.
void registerVisibilityTests() {
  test('rejects a private declaration as a binding target', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final privateDeclaration = declarations.firstWhere(
      (declaration) => declaration['visibility'] == 'private',
    );
    final privateId = privateDeclaration['id']! as String;
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    (overrides['targets']! as List<Object?>).add(privateId);
    (overrides['entries']! as Map<Object?, Object?>)[privateId] = {
      'strategy': 'reviewedExcluded',
      'declarationSha256': computeDeclarationFingerprint(
        privateDeclaration.cast<String, Object?>(),
      ),
      'reason': 'A private declaration cannot be selected.',
    };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration('UNKNOWN_TARGET_ID', contains('public')),
    );
  });
  test('rejects inherited shape on constructed interface projections', () {
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
      declaration['extends'] = <Object?>[
        <String, Object?>{
          'kind': 'reference',
          'name': 'ExtensionContext',
          'typeArguments': <Object?>[],
        },
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
        reason: strategy,
      );
    }
  });
  test('rejects Thenable inheritance detached from its generic', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(
      entries,
      'thenableFutureBridge',
    );
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final heritage = (declaration['extends']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    heritage.single['typeArguments'] = <Object?>[
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
  test('rejects excluded producer coverage on a public declaration', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final declaration =
        (inventory['declarations']! as List<Object?>).single!
            as Map<String, Object?>;
    declaration['coverage'] = {
      'discovery': 'discovered',
      'semantics': 'excluded',
      'binding': 'excluded',
      'host': 'notApplicable',
    };
    final overrides = _schemaOverrideFor(declaration);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('.coverage')),
    );
  });
  test('rejects pending producer coverage on a non-public declaration', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations.firstWhere(
      (candidate) => candidate['visibility'] != 'public',
    );
    declaration['coverage'] = _pendingCoverage();

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('.coverage')),
    );
  });
  test('rejects non-public top-level producer declarations', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    _unselectedDeclarationOfKind(inventory, 'interface')
      ..['visibility'] = 'private'
      ..['coverage'] = {
        'discovery': 'discovered',
        'semantics': 'excluded',
        'binding': 'excluded',
        'host': 'notApplicable',
      };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('visibility')),
    );
  });
  test('rejects interface members that do not inherit visibility', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    declarations.firstWhere(
        (candidate) =>
            candidate['kind'] == 'method' &&
            declarations.any(
              (parent) =>
                  parent['id'] == candidate['parentId'] &&
                  parent['kind'] == 'interface',
            ),
      )
      ..['visibility'] = 'private'
      ..['coverage'] = {
        'discovery': 'discovered',
        'semantics': 'excluded',
        'binding': 'excluded',
        'host': 'notApplicable',
      };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('visibility')),
    );
  });
  test(
    'rejects registered type literals that do not inherit owner visibility',
    () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final declarations = (inventory['declarations']! as List<Object?>)
          .cast<Map<Object?, Object?>>();
      declarations.firstWhere(
          (candidate) => candidate['kind'] == 'typeLiteral',
        )
        ..['visibility'] = 'private'
        ..['coverage'] = {
          'discovery': 'discovered',
          'semantics': 'excluded',
          'binding': 'excluded',
          'host': 'notApplicable',
        };

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration('INVALID_GENERATOR_INPUT', contains('visibility')),
      );
    },
  );
  test(
    'rejects registered type-literal references rebound to other owners',
    () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final pair = _sameShapeTypeLiteralReferencePair(inventory);
      pair.first['id'] = pair.second['id'];

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          allOf(contains('typeLiteral'), contains('owner')),
        ),
      );
    },
  );
}
