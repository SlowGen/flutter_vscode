const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const test = require('node:test');

const {
  validateBaselineUpdate,
} = require('../src/baseline.cjs');

test('baseline update rejects a newly discovered unclassified public symbol', () => {
  const previous = inventory([
    declaration('interface:vscode.Existing'),
  ]);
  const candidate = inventory([
    declaration('interface:vscode.Existing'),
    declaration('interface:vscode.NewApi'),
  ]);

  assert.throws(
    () => validateBaselineUpdate(previous, candidate, overrides({})),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /interface:vscode\.NewApi/);
      assert.match(error.message, /new public symbol/);
      return true;
    },
  );
});

test('baseline update rejects an unclassified shape change at a stable ID', () => {
  const previous = inventory([
    declaration('property:interface:vscode.Options/$instance/value', {
      type: {kind: 'primitive', name: 'string'},
    }),
  ]);
  const candidate = inventory([
    declaration('property:interface:vscode.Options/$instance/value', {
      type: {kind: 'primitive', name: 'number'},
    }),
  ]);

  assert.throws(
    () => validateBaselineUpdate(previous, candidate, overrides({})),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /Options\/\$instance\/value/);
      assert.match(error.message, /changed public symbol/);
      return true;
    },
  );
});

test('baseline update rejects an unclassified removed public symbol', () => {
  const removed = declaration('interface:vscode.RemovedApi');

  assert.throws(
    () => validateBaselineUpdate(
      inventory([removed]),
      inventory([]),
      overrides({}),
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /interface:vscode\.RemovedApi/);
      assert.match(error.message, /removed public symbol/);
      return true;
    },
  );
});

test('baseline update treats a public declaration becoming private as removed', () => {
  const id = 'interface:vscode.FormerlyPublic';

  assert.throws(
    () => validateBaselineUpdate(
      inventory([declaration(id)]),
      inventory([declaration(id, {visibility: 'private'})]),
      overrides({}),
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /interface:vscode\.FormerlyPublic/);
      assert.match(error.message, /removed public symbol/);
      return true;
    },
  );
});

test('baseline update accepts an explicitly reviewed public removal', () => {
  const removed = declaration('interface:vscode.RemovedApi');
  const retained = declaration('interface:vscode.RetainedApi');
  const semanticOverrides = overrides({
    [retained.id]: reviewedEntry(retained, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  });
  semanticOverrides.removals = {
    [removed.id]: reviewedEntry(removed, {
      strategy: 'reviewedRemoval',
      reason: 'The upstream stable API removed this declaration.',
    }),
  };

  assert.doesNotThrow(() => validateBaselineUpdate(
    inventory([removed, retained]),
    inventory([retained]),
    semanticOverrides,
  ));
});

test('baseline validation rejects a stale reviewed removal', () => {
  const existing = declaration('interface:vscode.Existing');
  const semanticOverrides = overrides({});
  semanticOverrides.removals = {
    [existing.id]: reviewedEntry(existing, {
      strategy: 'reviewedRemoval',
      reason: 'This declaration was not actually removed.',
    }),
  };

  assert.throws(
    () => validateBaselineUpdate(
      inventory([existing]),
      inventory([existing]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /stale reviewed removal/);
      assert.match(error.message, /interface:vscode\.Existing/);
      return true;
    },
  );
});

test('reviewed removal metadata cannot cite executable evidence', () => {
  const removed = declaration('interface:vscode.RemovedApi');
  const retained = declaration('interface:vscode.RetainedApi');
  const semanticOverrides = overrides({
    [retained.id]: reviewedEntry(retained, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  });
  semanticOverrides.removals = {
    [removed.id]: reviewedEntry(removed, {
      strategy: 'reviewedRemoval',
      reason: 'The upstream stable API removed this declaration.',
      hostContract: 'checkpointExtensionHost',
    }),
  };

  assert.throws(
    () => validateBaselineUpdate(
      inventory([removed, retained]),
      inventory([retained]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /reviewedRemoval fields/);
      return true;
    },
  );
});

test('reviewed removal reasons use ECMAScript trim semantics', () => {
  const removed = declaration('interface:vscode.RemovedApi');
  const retained = declaration('interface:vscode.RetainedApi');

  function semanticOverrides(reason) {
    const result = overrides({
      [retained.id]: reviewedEntry(retained, {
        strategy: 'opaqueHostObject',
        hostContract: 'checkpointExtensionHost',
      }),
    });
    result.removals = {
      [removed.id]: reviewedEntry(removed, {
        strategy: 'reviewedRemoval',
        reason,
      }),
    };
    return result;
  }

  assert.doesNotThrow(() => validateBaselineUpdate(
    inventory([removed, retained]),
    inventory([retained]),
    semanticOverrides('\u0085'),
  ));
  assert.throws(
    () => validateBaselineUpdate(
      inventory([removed, retained]),
      inventory([retained]),
      semanticOverrides('\uFEFF'),
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /non-empty reason/);
      return true;
    },
  );
});

test('baseline update accepts a reviewed classification for each public delta', () => {
  const previous = inventory([
    declaration('interface:vscode.Existing'),
  ]);
  const changed = declaration('interface:vscode.Existing', {
    deprecated: true,
  });
  const added = declaration('interface:vscode.NewApi');
  const candidate = inventory([changed, added]);
  const entries = {
    [changed.id]: reviewedEntry(changed, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
    [added.id]: reviewedEntry(added, {
      strategy: 'reviewedExcluded',
      reason: 'Not in this slice.',
    }),
  };

  assert.doesNotThrow(() =>
    validateBaselineUpdate(
      previous,
      candidate,
      overrides(entries, {
        checkpointExtensionHost: executableContract(),
      }),
    ),
  );
});

test('baseline validation rejects a target without a classification entry', () => {
  const existing = declaration('interface:vscode.Existing');
  const semanticOverrides = overrides({});
  semanticOverrides.targets = [existing.id];

  assert.throws(
    () => validateBaselineUpdate(
      inventory([existing]),
      inventory([existing]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /target .* has no classification entry/i);
      assert.match(error.message, /interface:vscode\.Existing/);
      return true;
    },
  );
});

test('baseline validation rejects duplicate targets', () => {
  const existing = declaration('interface:vscode.Existing');
  const semanticOverrides = overrides({
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  });
  semanticOverrides.targets = [existing.id, existing.id];

  assert.throws(
    () => validateBaselineUpdate(
      inventory([existing]),
      inventory([existing]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /duplicate target/);
      assert.match(error.message, /interface:vscode\.Existing/);
      return true;
    },
  );
});

test('baseline validation rejects an unsupported override schema', () => {
  const existing = declaration('interface:vscode.Existing');
  const semanticOverrides = overrides({
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  });
  semanticOverrides.schemaVersion = 2;

  assert.throws(
    () => validateBaselineUpdate(
      inventory([existing]),
      inventory([existing]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /schemaVersion must be 1/);
      return true;
    },
  );
});

test('baseline validation rejects missing or unknown top-level metadata', () => {
  const existing = declaration('interface:vscode.Existing');
  const entries = {
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  };
  const extra = overrides(entries);
  extra.misleadingEvidence = true;
  const missing = overrides(entries);
  delete missing.manifestSchemaSha256;

  for (const [label, semanticOverrides] of Object.entries({extra, missing})) {
    assert.throws(
      () => validateBaselineUpdate(
        inventory([existing]),
        inventory([existing]),
        semanticOverrides,
      ),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA', label);
        assert.match(error.message, /top-level fields must be exactly/, label);
        return true;
      },
      label,
    );
  }
});

test('baseline validation rejects malformed root evidence hashes', () => {
  const existing = declaration('interface:vscode.Existing');
  const candidate = inventory([existing]);
  const entries = {
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  };
  const invalidValues = {
    manifestSchemaSha256: true,
    manifestValidatorSha256: 'A'.repeat(64),
    commandsContributionSchemaSha256: null,
  };

  for (const [field, value] of Object.entries(invalidValues)) {
    const semanticOverrides = overrides(entries);
    semanticOverrides[field] = value;

    assert.throws(
      () => validateBaselineUpdate(candidate, candidate, semanticOverrides),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA', field);
        assert.match(error.message, new RegExp(`${field}.*lowercase SHA-256`));
        return true;
      },
      field,
    );
  }
});

test('baseline validation rejects stale root evidence hashes', () => {
  const existing = declaration('interface:vscode.Existing');
  const candidate = inventory([existing]);
  const entries = {
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  };
  const semanticOverrides = overrides(entries);
  semanticOverrides.manifestValidatorSha256 = '0'.repeat(64);

  assert.throws(
    () => validateBaselineUpdate(candidate, candidate, semanticOverrides),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /manifestValidatorSha256/);
      assert.match(error.message, /does not match candidate evidence/);
      assert.match(error.message, new RegExp('2'.repeat(64)));
      return true;
    },
  );
});

test('baseline validation rejects malformed candidate root evidence', () => {
  const existing = declaration('interface:vscode.Existing');
  const candidate = inventory([existing]);
  candidate.contributionSchemas.commands.inputSha256 = 'not-a-digest';
  const semanticOverrides = overrides({
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  });

  assert.throws(
    () => validateBaselineUpdate(candidate, candidate, semanticOverrides),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(
        error.message,
        /candidate contributionSchemas\.commands\.inputSha256.*lowercase SHA-256/,
      );
      return true;
    },
  );
});

test('baseline validation rejects a candidate version mismatch', () => {
  const existing = declaration('interface:vscode.Existing');
  const candidate = inventory([existing]);
  const semanticOverrides = overrides({
    [existing.id]: reviewedEntry(existing, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  });
  semanticOverrides.vscodeVersion = '1.1.0';

  assert.throws(
    () => validateBaselineUpdate(candidate, candidate, semanticOverrides),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /vscodeVersion 1\.1\.0/);
      assert.match(error.message, /candidate product version 1\.0\.0/);
      return true;
    },
  );
});

test('baseline validation rejects a classification entry without a target', () => {
  const existing = declaration('interface:vscode.Existing');
  const semanticOverrides = overrides({
    [existing.id]: reviewedEntry(existing, {
      strategy: 'reviewedExcluded',
      reason: 'Not selected by the walking slice.',
    }),
  });
  semanticOverrides.targets = [];

  assert.throws(
    () => validateBaselineUpdate(
      inventory([existing]),
      inventory([existing]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /entry .* has no target/i);
      assert.match(error.message, /interface:vscode\.Existing/);
      return true;
    },
  );
});

test('baseline validation rejects a stale target absent from the candidate', () => {
  const stale = declaration('interface:vscode.RemovedApi');
  const semanticOverrides = overrides({
    [stale.id]: reviewedEntry(stale, {
      strategy: 'reviewedExcluded',
      reason: 'This declaration no longer exists.',
    }),
  });

  assert.throws(
    () => validateBaselineUpdate(
      inventory([]),
      inventory([]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /does not name a candidate public declaration/);
      assert.match(error.message, /interface:vscode\.RemovedApi/);
      return true;
    },
  );
});

test('baseline validation rejects stale metadata for an unchanged target', () => {
  const existing = declaration('interface:vscode.Existing');
  const semanticOverrides = overrides({
    [existing.id]: {
      strategy: 'opaqueHostObject',
      declarationSha256: '0'.repeat(64),
      hostContract: 'checkpointExtensionHost',
    },
  });

  assert.throws(
    () => validateBaselineUpdate(
      inventory([existing]),
      inventory([existing]),
      semanticOverrides,
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /declarationSha256/);
      assert.match(error.message, /interface:vscode\.Existing/);
      return true;
    },
  );
});

test('baseline update rejects an empty override posing as a classification', () => {
  const added = declaration('interface:vscode.NewApi');

  assert.throws(
    () =>
      validateBaselineUpdate(
        inventory([]),
        inventory([added]),
        overrides({[added.id]: {}}),
      ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /strategy/);
      return true;
    },
  );
});

test('baseline validation rejects missing or unrecognized classification metadata', () => {
  const added = declaration('interface:vscode.NewApi');
  const variants = {
    emitted: reviewedEntry(added, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
      hostVerified: true,
    }),
    excluded: reviewedEntry(added, {
      strategy: 'reviewedExcluded',
      reason: 'Not selected by the walking slice.',
      obsoleteRunner: 'deleted.cjs',
    }),
    emittedMissingField: reviewedEntry(added, {
      strategy: 'opaqueHostObject',
    }),
    excludedMissingField: reviewedEntry(added, {
      strategy: 'reviewedExcluded',
    }),
  };

  for (const [label, entry] of Object.entries(variants)) {
    assert.throws(
      () => validateBaselineUpdate(
        inventory([]),
        inventory([added]),
        overrides({[added.id]: entry}),
      ),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA', label);
        assert.match(error.message, /fields must be exactly/, label);
        return true;
      },
      label,
    );
  }
});

test('baseline update rejects a stale reviewed declaration fingerprint', () => {
  const added = declaration('interface:vscode.NewApi');

  assert.throws(
    () =>
      validateBaselineUpdate(
        inventory([]),
        inventory([added]),
        overrides({
          [added.id]: {
            strategy: 'reviewedExcluded',
            declarationSha256: '0'.repeat(64),
            reason: 'Not in this slice.',
          },
        }),
      ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /declarationSha256/);
      return true;
    },
  );
});

test('baseline update rejects obsolete or malformed Host Contracts', () => {
  const added = declaration('interface:vscode.NewApi');
  const entries = {
    [added.id]: reviewedEntry(added, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  };
  const malformedContracts = {
    'obsolete source-path contract': {
      boundary: 'vscodeExtensionHost',
      runner: 'scripts/test_host_extension.sh',
      launcher: 'tool/extension_host_test/run.cjs',
      test: 'test/fixtures/host_extension/test/run.cjs',
    },
    'extra unpinned source path': {
      ...executableContract(),
      runner: 'scripts/test_host_extension.sh',
    },
    'invalid artifact checksum': {
      ...executableContract(),
      artifactSha256: 'A'.repeat(64),
    },
    'artifact outside the durable contract directory': {
      ...executableContract(),
      artifact: 'tool/bindings/checkpoint-extension-host.json',
    },
    'artifact path traversal': {
      ...executableContract(),
      artifact: 'tool/bindings/contracts/../checkpoint-extension-host.json',
    },
    'non-canonical artifact filename': {
      ...executableContract(),
      artifact: 'tool/bindings/contracts/checkpoint extension host.json',
    },
  };

  for (const [label, contract] of Object.entries(malformedContracts)) {
    assert.throws(
      () => validateBaselineUpdate(
        inventory([]),
        inventory([added]),
        overrides(entries, {checkpointExtensionHost: contract}),
      ),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA', label);
        assert.match(error.message, /Host Contract .* is missing or malformed/, label);
        return true;
      },
      label,
    );
  }
});

test('baseline update rejects an unused obsolete Host Contract', () => {
  const added = declaration('interface:vscode.NewApi');
  const entries = {
    [added.id]: reviewedEntry(added, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  };

  assert.throws(
    () => validateBaselineUpdate(
      inventory([]),
      inventory([added]),
      overrides(entries, {
        checkpointExtensionHost: executableContract(),
        obsoleteUnusedContract: {
          boundary: 'vscodeExtensionHost',
          runner: 'scripts/test_host_extension.sh',
          launcher: 'tool/extension_host_test/run.cjs',
          test: 'test/fixtures/host_extension/test/run.cjs',
        },
      }),
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(
        error.message,
        /Host Contract obsoleteUnusedContract is missing or malformed/,
      );
      return true;
    },
  );
});

test('baseline validation rejects a well-formed unused Host Contract', () => {
  const added = declaration('interface:vscode.NewApi');
  const entries = {
    [added.id]: reviewedEntry(added, {
      strategy: 'opaqueHostObject',
      hostContract: 'checkpointExtensionHost',
    }),
  };

  assert.throws(
    () => validateBaselineUpdate(
      inventory([]),
      inventory([added]),
      overrides(entries, {
        checkpointExtensionHost: executableContract(),
        unusedContract: {
          ...executableContract(),
          artifact: 'tool/bindings/contracts/unused-host.json',
        },
      }),
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(error.message, /Host Contract unusedContract is not cited/);
      return true;
    },
  );
});

test('baseline update rejects Host Contract IDs outside lower camel case', () => {
  assert.throws(
    () => validateBaselineUpdate(
      inventory([]),
      inventory([]),
      overrides({}, {BadContract: executableContract()}),
    ),
    (error) => {
      assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA');
      assert.match(
        error.message,
        /Host Contract ID BadContract must be lower camel case/,
      );
      return true;
    },
  );
});

test('baseline update requires a nonempty Host Contract object', () => {
  const invalidOverrides = {
    missing: {
      schemaVersion: 1,
      targets: [],
      entries: {},
    },
    empty: overrides({}, {}),
  };

  for (const [label, value] of Object.entries(invalidOverrides)) {
    assert.throws(
      () => validateBaselineUpdate(inventory([]), inventory([]), value),
      (error) => {
        assert.equal(error.code, 'UNCLASSIFIED_BASELINE_DELTA', label);
        assert.match(
          error.message,
          /at least one executable Host Contract/,
          label,
        );
        return true;
      },
      label,
    );
  }
});

test('baseline update mechanically excludes new non-public inventory', () => {
  const retained = declaration('interface:vscode.RetainedApi');
  const previous = inventory([retained]);
  const candidate = inventory([
    retained,
    declaration('interface:vscode.Internal', {visibility: 'private'}),
  ]);

  assert.doesNotThrow(() =>
    validateBaselineUpdate(previous, candidate, overrides({
      [retained.id]: reviewedEntry(retained, {
        strategy: 'opaqueHostObject',
        hostContract: 'checkpointExtensionHost',
      }),
    })),
  );
});

test('baseline check CLI is an executable fail-closed update gate', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-baseline-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const previousPath = writeJson(
    directory,
    'previous.json',
    inventory([]),
  );
  const candidatePath = writeJson(
    directory,
    'candidate.json',
    inventory([declaration('interface:vscode.NewApi')]),
  );
  const overridesPath = writeJson(
    directory,
    'overrides.json',
    overrides({}),
  );

  const result = spawnSync(
    process.execPath,
    [
      path.resolve(__dirname, '../src/baseline_check.cjs'),
      '--previous',
      previousPath,
      '--candidate',
      candidatePath,
      '--overrides',
      overridesPath,
    ],
    {encoding: 'utf8'},
  );

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^UNCLASSIFIED_BASELINE_DELTA: /);
  assert.match(result.stderr, /interface:vscode\.NewApi/);
});

function inventory(declarations) {
  return {
    schemaVersion: 1,
    source: {product: {version: '1.0.0'}},
    manifestSchema: {inputSha256: '1'.repeat(64)},
    manifestValidator: {inputSha256: '2'.repeat(64)},
    contributionSchemas: {
      commands: {inputSha256: '3'.repeat(64)},
      views: {inputSha256: '5'.repeat(64)},
      viewsContainers: {inputSha256: '5'.repeat(64)},
      configuration: {inputSha256: '6'.repeat(64)},
    },
    declarations,
  };
}

function declaration(id, extra = {}) {
  return {
    id,
    kind: 'interface',
    name: id.split('.').at(-1),
    visibility: 'public',
    ...extra,
  };
}

function overrides(entries, hostContracts) {
  hostContracts ??= {checkpointExtensionHost: executableContract()};
  return {
    schemaVersion: 1,
    vscodeVersion: '1.0.0',
    manifestSchemaSha256: '1'.repeat(64),
    manifestValidatorSha256: '2'.repeat(64),
    commandsContributionSchemaSha256: '3'.repeat(64),
    viewsContributionSchemaSha256: '5'.repeat(64),
    configurationContributionSchemaSha256: '6'.repeat(64),
    hostContracts,
    targets: Object.keys(entries),
    entries,
  };
}

function reviewedEntry(value, classification) {
  return {
    ...classification,
    declarationSha256: crypto
      .createHash('sha256')
      .update(canonicalJson(value))
      .digest('hex'),
  };
}

function canonicalJson(value) {
  if (Array.isArray(value)) {
    return `[${value.map(canonicalJson).join(',')}]`;
  }
  if (value !== null && typeof value === 'object') {
    return `{${Object.keys(value)
      .filter((key) => key !== 'coverage')
      .sort()
      .map((key) => `${JSON.stringify(key)}:${canonicalJson(value[key])}`)
      .join(',')}}`;
  }
  return JSON.stringify(value);
}

function executableContract() {
  return {
    boundary: 'vscodeExtensionHost',
    artifact: 'tool/bindings/contracts/checkpoint-extension-host.json',
    artifactSha256: 'a'.repeat(64),
  };
}

function writeJson(directory, name, value) {
  const filePath = path.join(directory, name);
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
  return filePath;
}
