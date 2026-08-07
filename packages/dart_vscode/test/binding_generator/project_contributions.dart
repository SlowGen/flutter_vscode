part of '../binding_generator_test.dart';

/// The contribution-schema projections pinned in the inventory. The
/// author-data admission behavior these schemas mirror lives in
/// `package:dart_vscode/contributions.dart` and is tested in
/// `contribution_projection_test.dart`.
void registerProjectContributionsTests() {
  test('rejects missing command validator semantics in the inventory', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final schemas = (inventory['contributionSchemas']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    (schemas['commands']! as Map<Object?, Object?>)
        .cast<String, Object?>()
        .remove('validation');

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('Commands'), contains('unprojected change')),
      ),
    );
  });
  test('rejects unprojected changes in each new contribution schema', () {
    // Double entry, same as commands: the importer derives each projection
    // from the pinned source and the generator carries an independently
    // reviewed copy. A drifted IR node must fail with the differing path,
    // never be absorbed.
    for (final schema in ['viewsContainers', 'views', 'configuration']) {
      final inventory = _inventory(['interface:vscode.Known']);
      final schemas =
          (inventory['contributionSchemas']! as Map<Object?, Object?>)
              .cast<String, Object?>();
      (schemas[schema]! as Map<Object?, Object?>)
          .cast<String, Object?>()
          .remove('validation');

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _overrides({'interface:vscode.Known': 'opaqueJsObject'}),
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          allOf(contains(schema), contains('unprojected change')),
        ),
        reason: schema,
      );
    }
  });

  test('reports the first command schema drift path and remediation', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final schemas = (inventory['contributionSchemas']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final commands = (schemas['commands']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final validation = (commands['validation']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final icon = (validation['icon']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    (icon['objectRequiredStringProperties']! as List<Object?>).removeLast();

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(
          contains(
            'First differing path: '
            'inventory.contributionSchemas.commands.validation.icon.'
            'objectRequiredStringProperties[1]',
          ),
          contains('Regenerate the IR'),
          contains('update the generator projection'),
        ),
      ),
    );
  });
  test('rejects execute-command return types detached from its generic', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final overrides = _readJson(
      'tool/bindings/overrides/vscode-1.129.1.json',
    );
    final entries = (overrides['entries']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    final declarationId = _entryIdForStrategy(entries, 'commandExecution');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations
        .singleWhere((candidate) => candidate['id'] == declarationId)
        .cast<String, Object?>();
    final returnType = (declaration['returnType']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    returnType['typeArguments'] = <Object?>[
      <String, Object?>{'kind': 'primitive', 'name': 'string'},
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
      _throwsGeneration('WALKING_SLICE_PROFILE_MISMATCH', contains(mutatedId)),
    );
  });
}
