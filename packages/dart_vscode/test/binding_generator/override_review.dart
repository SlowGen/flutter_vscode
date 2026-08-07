part of '../binding_generator_test.dart';

/// Generation and Semantic Override entries: reviewed removals, exclusions, and the closure they stay inside.
void registerOverrideReviewTests() {
  test('rejects an unsupported Semantic Override schema version', () {
    final overrides = _overrides({
      'interface:vscode.Known': 'opaqueJsObject',
    })..['schemaVersion'] = 999;

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: overrides,
      ),
      _throwsGeneration(
        'UNSUPPORTED_INPUT_SCHEMA_VERSION',
        contains('overrides.schemaVersion'),
      ),
    );
  });
  test('rejects unknown top-level Semantic Override fields', () {
    final overrides = _overrides({
      'interface:vscode.Known': 'opaqueJsObject',
    })..['unknownPolicy'] = <Object?>[];

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: overrides,
      ),
      _throwsGeneration(
        'INVALID_OVERRIDE',
        allOf(contains('top-level'), contains('unknownPolicy')),
      ),
    );
  });
  test('accepts optional reviewed removal metadata', () {
    final overrides =
        _overrides({
            'interface:vscode.Known': 'opaqueJsObject',
          })
          ..['removals'] = {
            'interface:vscode.Removed': {
              'strategy': 'reviewedRemoval',
              'declarationSha256': '0' * 64,
              'reason': 'The upstream stable API removed this declaration.',
            },
          };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: overrides,
      ),
      returnsNormally,
    );
  });
  test('accepts a reviewed removal when the candidate is private', () {
    final inventory = _readJson('tool/bindings/ir/vscode-1.129.1.json');
    final declarations = (inventory['declarations']! as List<Object?>)
        .cast<Map<String, Object?>>();
    final privateId =
        declarations.firstWhere(
              (declaration) => declaration['visibility'] == 'private',
            )['id']!
            as String;
    final overrides =
        _readJson(
            'tool/bindings/overrides/vscode-1.129.1.json',
          )
          ..['removals'] = {
            privateId: {
              'strategy': 'reviewedRemoval',
              'declarationSha256': '0' * 64,
              'reason': 'The declaration is not part of the public inventory.',
            },
          };

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: inventory,
        overrides: overrides,
      ),
      returnsNormally,
    );
  });
  test('rejects malformed or stale reviewed removal metadata', () {
    final malformedRemovals = <String, Object?>{
      'non-object removals': <Object?>[],
      'extra entry field': {
        'interface:vscode.Removed': {
          'strategy': 'reviewedRemoval',
          'declarationSha256': '0' * 64,
          'reason': 'Removed upstream.',
          'reviewer': 'not pinned',
        },
      },
      'wrong strategy': {
        'interface:vscode.Removed': {
          'strategy': 'reviewedExcluded',
          'declarationSha256': '0' * 64,
          'reason': 'Removed upstream.',
        },
      },
      'malformed fingerprint': {
        'interface:vscode.Removed': {
          'strategy': 'reviewedRemoval',
          'declarationSha256': 'not-a-sha',
          'reason': 'Removed upstream.',
        },
      },
      'empty reason': {
        'interface:vscode.Removed': {
          'strategy': 'reviewedRemoval',
          'declarationSha256': '0' * 64,
          'reason': '   ',
        },
      },
      'declaration still present': {
        'interface:vscode.Known': {
          'strategy': 'reviewedRemoval',
          'declarationSha256': computeDeclarationFingerprint(
            _testDeclaration('interface:vscode.Known'),
          ),
          'reason': 'Not actually removed.',
        },
      },
    };

    for (final malformed in malformedRemovals.entries) {
      final overrides = _overrides({
        'interface:vscode.Known': 'opaqueJsObject',
      })..['removals'] = malformed.value;

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: _inventory(['interface:vscode.Known']),
          overrides: overrides,
        ),
        _throwsGeneration('INVALID_OVERRIDE', contains('removal')),
        reason: malformed.key,
      );
    }
  });
  test('uses ECMAScript trim semantics for reviewed removal reasons', () {
    Map<String, Object?> removalOverrides(String reason) {
      return _overrides({
          'interface:vscode.Known': 'opaqueJsObject',
        })
        ..['removals'] = {
          'interface:vscode.Removed': {
            'strategy': 'reviewedRemoval',
            'declarationSha256': '0' * 64,
            'reason': reason,
          },
        };
    }

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: removalOverrides('\u0085'),
      ),
      returnsNormally,
      reason: 'ECMAScript trim preserves U+0085.',
    );
    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: removalOverrides('\uFEFF'),
      ),
      _throwsGeneration('INVALID_OVERRIDE', contains('non-empty reason')),
      reason: 'ECMAScript trim removes U+FEFF.',
    );
  });
  test('rejects a Semantic Override for an unknown IR entry', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides({
          'interface:vscode.Missing': 'opaqueJsObject',
        }),
      ),
      _throwsGeneration(
        'UNKNOWN_OVERRIDE_ID',
        contains('interface:vscode.Missing'),
      ),
    );
  });
  test('rejects an unrecognized Semantic Override strategy', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides({
          'interface:vscode.Known': 'handwrittenDartSnippet',
        }),
      ),
      _throwsGeneration(
        'UNKNOWN_OVERRIDE_STRATEGY',
        allOf(
          contains('interface:vscode.Known'),
          contains('handwrittenDartSnippet'),
        ),
      ),
    );
  });
  test('rejects extra fields on emitted and excluded override entries', () {
    final malformedEntries = <String, Map<String, Object?>>{
      'emitted': {
        'strategy': 'opaqueJsObject',
        'declarationSha256': computeDeclarationFingerprint(
          _testDeclaration('interface:vscode.Known'),
        ),
        'hostContract': 'testExtensionHost',
        'reason': 'must not coexist with an emitted binding',
      },
      'excluded': {
        'strategy': 'reviewedExcluded',
        'declarationSha256': computeDeclarationFingerprint(
          _testDeclaration('interface:vscode.Known'),
        ),
        'reason': 'outside the supported projection',
        'reviewer': 'extra metadata is not pinned',
      },
    };

    for (final malformed in malformedEntries.entries) {
      final overrides = _overrides({
        'interface:vscode.Known': 'opaqueJsObject',
      });
      final entries = (overrides['entries']! as Map<Object?, Object?>)
          .cast<String, Object?>();
      (entries['interface:vscode.Known']! as Map<Object?, Object?>)
          .cast<String, Object?>()
        ..clear()
        ..addAll(malformed.value);

      expect(
        () => VSCodeBindingGenerator().generateCoverageLedger(
          inventory: _inventory(['interface:vscode.Known']),
          overrides: overrides,
        ),
        _throwsGeneration(
          'INVALID_OVERRIDE',
          allOf(
            contains('interface:vscode.Known'),
            contains('exactly'),
          ),
        ),
        reason: malformed.key,
      );
    }
  });
  test('rejects a whitespace-only reviewed exclusion reason', () {
    final overrides = _overrides({
      'interface:vscode.Known': 'reviewedExcluded',
    });
    final entry =
        ((overrides['entries']!
                    as Map<Object?, Object?>)['interface:vscode.Known']!
                as Map<Object?, Object?>)
            .cast<String, Object?>();
    entry['reason'] = '   ';

    expect(
      () => VSCodeBindingGenerator().generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: overrides,
      ),
      _throwsGeneration('INVALID_OVERRIDE', contains('non-empty reason')),
    );
  });
  test('rejects Semantic Overrides for a different VS Code pin', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides(
          {'interface:vscode.Known': 'opaqueJsObject'},
          vscodeVersion: '1.128.0',
        ),
      ),
      _throwsGeneration(
        'OVERRIDE_VERSION_MISMATCH',
        allOf(contains('1.128.0'), contains('1.129.1')),
      ),
    );
  });
  test('rejects Semantic Overrides for a different manifest schema pin', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides(
          {'interface:vscode.Known': 'opaqueJsObject'},
          manifestSchemaSha256: '0' * 64,
        ),
      ),
      _throwsGeneration(
        'MANIFEST_SCHEMA_PIN_MISMATCH',
        allOf(
          contains('0' * 64),
          contains(
            'feddc98984b755a95644674910aa8c671e3259f137698c581ec7e2837cb058aa',
          ),
        ),
      ),
    );
  });
  test('rejects Semantic Overrides for a different manifest validator pin', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides(
          {'interface:vscode.Known': 'opaqueJsObject'},
          manifestValidatorSha256: '0' * 64,
        ),
      ),
      _throwsGeneration(
        'MANIFEST_VALIDATOR_PIN_MISMATCH',
        allOf(
          contains('0' * 64),
          contains(
            'e8ae92aa491ab138b6f625acbbcbd7c53ff187098066ff13aebb64615202dde1',
          ),
        ),
      ),
    );
  });
  test('rejects a Semantic Override that is outside the selected closure', () {
    final generator = VSCodeBindingGenerator();

    expect(
      () => generator.generateCoverageLedger(
        inventory: _inventory(['interface:vscode.Known']),
        overrides: _overrides(
          {'interface:vscode.Known': 'opaqueJsObject'},
          targets: const [],
        ),
      ),
      _throwsGeneration('UNUSED_OVERRIDE', contains('interface:vscode.Known')),
    );
  });
}
