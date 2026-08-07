part of '../binding_generator_test.dart';

/// Generation and canonical identity: signature bytes, shape hashes, and
/// the declaration IDs derived from them.
void registerCanonicalIdentityTests() {
  test('rejects noncanonical canonicalSignature bytes', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declaration = _unselectedCallable(inventory);
    declaration['canonicalSignature'] =
        ' ${declaration['canonicalSignature']! as String}';

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        contains('canonicalSignature'),
      ),
    );
  });

  test('rejects callable IDs detached from canonicalSignature hashes', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declaration = _unselectedCallable(inventory);
    final signature =
        (jsonDecode(declaration['canonicalSignature']! as String)
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    signature['returnType'] = {'kind': 'primitive', 'name': 'undefined'};
    declaration['canonicalSignature'] = jsonEncode(signature);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('.id'), contains('canonicalSignature')),
      ),
    );
  });

  test('rejects inline shapes detached from their shapeHash', () {
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
          'type': {'kind': 'primitive', 'name': 'string'},
        },
      ],
    };
    declaration['typeParameters'] = [
      {
        'name': 'T',
        'constraint': {
          'kind': 'typeLiteral',
          'shape': shape,
          'shapeHash': '0' * 64,
        },
      },
    ];
    final overrides = _schemaOverrideFor(declaration);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('shapeHash')),
    );
  });

  test('rejects type-literal declaration IDs detached from shapeHash', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<Object?, Object?>>();
    final declaration = declarations.firstWhere(
      (candidate) => candidate['kind'] == 'typeLiteral',
    );
    declaration['shapeHash'] = '0' * 64;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration('INVALID_GENERATOR_INPUT', contains('qualifiedName')),
    );
  });

  final rawCanonicalCases =
      <({String name, Map<String, Object?> Function() declaration})>[
        (
          name: 'parameter types',
          declaration: () => _syntheticMethod(
            rawParameters: [
              _rawParameter('value', {'kind': 'primitive', 'name': 'string'}),
            ],
            canonicalParameters: [
              _canonicalParameter({'kind': 'primitive', 'name': 'number'}),
            ],
          ),
        ),
        (
          name: 'return types',
          declaration: () => _syntheticMethod(
            rawReturnType: {'kind': 'primitive', 'name': 'string'},
            canonicalReturnType: {'kind': 'primitive', 'name': 'number'},
          ),
        ),
        (
          name: 'type-parameter constraints',
          declaration: () => _syntheticMethod(
            rawTypeParameters: [
              {
                'name': 'T',
                'constraint': {'kind': 'primitive', 'name': 'string'},
              },
            ],
            canonicalTypeParameters: [
              {
                'constraint': {'kind': 'primitive', 'name': 'number'},
              },
            ],
          ),
        ),
        (
          name: 'method flags',
          declaration: () => _syntheticMethod(
            canonicalStatic: true,
            canonicalOptional: true,
          ),
        ),
      ];

  for (final testCase in rawCanonicalCases) {
    test('rejects divergent raw and canonical ${testCase.name}', () {
      final inventory = _inventory(['interface:vscode.Known']);
      (inventory['declarations']! as List<Object?>).add(
        testCase.declaration(),
      );

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _overrides({
            'interface:vscode.Known': 'opaqueJsObject',
          }),
        ),
        _throwsGeneration(
          'INVALID_GENERATOR_INPUT',
          contains('canonicalSignature'),
        ),
      );
    });
  }

  test('rejects divergent raw and canonical nested function types', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final declarations = inventory['declarations']! as List<Object?>;
    final functionType = <String, Object?>{
      'kind': 'function',
      'typeParameters': <Object?>[],
      'parameters': [
        _rawParameter('value', {'kind': 'primitive', 'name': 'string'}),
      ],
      'returnType': {'kind': 'primitive', 'name': 'void'},
    };
    functionType['canonicalSignature'] = jsonEncode({
      'typeParameters': <Object?>[],
      'parameters': [
        _canonicalParameter({'kind': 'primitive', 'name': 'number'}),
      ],
      'returnType': {'kind': 'primitive', 'name': 'void'},
    });
    declarations.add({
      'id': r'property:interface:vscode.Known/$instance/callback',
      'kind': 'property',
      'name': 'callback',
      'qualifiedName': 'vscode.Known.callback',
      'parentId': 'interface:vscode.Known',
      'deprecated': false,
      'visibility': 'public',
      'optional': false,
      'readonly': false,
      'static': false,
      'abstract': false,
      'type': functionType,
      'coverage': _pendingCoverage(),
    });

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        contains('canonicalSignature'),
      ),
    );
  });

  test('rejects canonical type-parameter indexes outside their scope', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final signature = jsonEncode({
      'typeParameters': <Object?>[<String, Object?>{}],
      'parameters': <Object?>[],
      'returnType': {'kind': 'typeParameter', 'index': 1},
      'static': false,
      'optional': false,
    });
    (inventory['declarations']! as List<Object?>).add({
      'id': 'method:vscode.Known.synthetic@${_sha256String(signature)}',
      'kind': 'method',
      'name': 'synthetic',
      'qualifiedName': 'vscode.Known.synthetic',
      'parentId': 'interface:vscode.Known',
      'deprecated': false,
      'visibility': 'public',
      'overloadOrdinal': 0,
      'canonicalSignature': signature,
      'typeParameters': [
        <String, Object?>{'name': 'T'},
      ],
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

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('typeParameter'), contains('index')),
      ),
    );
  });

  test('rejects canonical outer type-parameter depths outside their scope', () {
    final inventory = _inventory(['interface:vscode.Box']);
    final declarations = inventory['declarations']! as List<Object?>;
    final parent = declarations.single! as Map<String, Object?>;
    parent['typeParameters'] = [
      <String, Object?>{'name': 'T'},
    ];
    final signature = jsonEncode({
      'typeParameters': <Object?>[],
      'parameters': <Object?>[],
      'returnType': {
        'kind': 'outerTypeParameter',
        'depth': 2,
        'index': 0,
      },
      'static': false,
      'optional': false,
    });
    declarations.add({
      'id': 'method:vscode.Box.synthetic@${_sha256String(signature)}',
      'kind': 'method',
      'name': 'synthetic',
      'qualifiedName': 'vscode.Box.synthetic',
      'parentId': 'interface:vscode.Box',
      'deprecated': false,
      'visibility': 'public',
      'overloadOrdinal': 0,
      'canonicalSignature': signature,
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
        allOf(contains('outerTypeParameter'), contains('depth')),
      ),
    );
  });

  test('rejects registered type-literal references without declarations', () {
    final inventory = _inventory(['interface:vscode.Known']);
    (inventory['declarations']! as List<Object?>).add({
      'id': r'property:interface:vscode.Known/$instance/options',
      'kind': 'property',
      'name': 'options',
      'qualifiedName': 'vscode.Known.options',
      'parentId': 'interface:vscode.Known',
      'deprecated': false,
      'visibility': 'public',
      'optional': false,
      'readonly': false,
      'static': false,
      'abstract': false,
      'type': {
        'kind': 'typeLiteral',
        'id': 'typeLiteral:missing',
        'shapeHash': '0' * 64,
      },
      'coverage': _pendingCoverage(),
    });

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('typeLiteral:missing'), contains('declaration')),
      ),
    );
  });

  test('rejects registered type-literal declarations without inbound refs', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final orphanShape = <String, Object?>{'members': <Object?>[]};
    final hash = _shapeHash(orphanShape);
    (inventory['declarations']! as List<Object?>)
      ..add({
        'id': 'typeAlias:vscode.OrphanOwner',
        'kind': 'typeAlias',
        'name': 'OrphanOwner',
        'qualifiedName': 'vscode.OrphanOwner',
        'parentId': 'module:vscode',
        'deprecated': false,
        'visibility': 'public',
        'typeParameters': <Object?>[],
        'type': {'kind': 'primitive', 'name': 'string'},
        'coverage': _pendingCoverage(),
      })
      ..add({
        'id': 'typeLiteral:typeAlias:vscode.OrphanOwner/\$shape@$hash',
        'kind': 'typeLiteral',
        'name': r'$type',
        'qualifiedName': 'typeAlias:vscode.OrphanOwner.\$shape@$hash',
        'parentId': 'typeAlias:vscode.OrphanOwner',
        'deprecated': false,
        'visibility': 'public',
        'shapeHash': hash,
        'shape': orphanShape,
        'coverage': _pendingCoverage(),
      });
    _sortDeclarationsLikeProducer(inventory);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('typeLiteral'), contains('inbound')),
      ),
    );
  });

  test('rejects type-literal child shapes detached from parent shapeHash', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final pair = _singlePropertyTypeLiteral(inventory);
    pair.child['readonly'] = !(pair.child['readonly']! as bool);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('shapeHash'), contains('children')),
      ),
    );
  });

  test(
    'requires registered type-literal declarations to carry their shape',
    () {
      final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
      final pair = _singlePropertyTypeLiteral(inventory);
      pair.parent.remove('shape');

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: inventory,
          overrides: _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          ),
        ),
        _throwsGeneration('INVALID_GENERATOR_INPUT', contains('shape')),
      );
    },
  );

  test('recomputes multi-member type-literal shape hashes from children', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final child = _multiPropertyTypeLiteralChild(inventory);
    child['readonly'] = !(child['readonly']! as bool);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('shapeHash'), contains('children')),
      ),
    );
  });

  test('recomputes type-literal shape hashes over signature children', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    _tamperSignatureChildOfTypeLiteral(inventory);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('shapeHash'), contains('children')),
      ),
    );
  });

  test('rejects detached properties typed by registered literals', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final child = _registeredLiteralTypedPropertyChild(inventory);
    child['optional'] = !(child['optional']! as bool);

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: _readJson(
          'tool/bindings/overrides/vscode-1.129.1.json',
        ),
      ),
      _throwsGeneration(
        'INVALID_GENERATOR_INPUT',
        allOf(contains('shapeHash'), contains('children')),
      ),
    );
  });

  test('accepts raw types in unscoped inline type-literal shapes', () {
    final inventory = _inventory(['interface:vscode.Known']);
    final declaration =
        (inventory['declarations']! as List<Object?>).single!
            as Map<String, Object?>;
    final optionsShape = <String, Object?>{
      'members': [
        {
          'kind': 'property',
          'name': 'enabled',
          'optional': false,
          'readonly': false,
          'type': {'kind': 'primitive', 'name': 'boolean'},
        },
      ],
    };
    final outerShape = <String, Object?>{
      'members': [
        {
          'kind': 'property',
          'name': 'value',
          'optional': false,
          'readonly': false,
          'type': {
            'kind': 'tuple',
            'elements': [
              {
                'name': 'callback',
                'optional': false,
                'rest': false,
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
              {
                'name': 'options',
                'optional': false,
                'rest': false,
                'type': {
                  'kind': 'typeLiteral',
                  'shapeHash': _shapeHash(optionsShape),
                  'shape': optionsShape,
                },
              },
            ],
          },
        },
      ],
    };
    declaration['extends'] = [
      {
        'kind': 'reference',
        'name': 'Base',
        'typeArguments': [
          {
            'kind': 'typeLiteral',
            'shapeHash': _shapeHash(outerShape),
            'shape': outerShape,
          },
        ],
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
