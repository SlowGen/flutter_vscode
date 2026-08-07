const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const test = require('node:test');

const seriesCheckPath = path.resolve(
  __dirname,
  '../src/baseline_series_check.cjs',
);

test('baseline series validates the explicit seed override', (context) => {
  const series = createSeries(context);
  const existing = declaration('interface:vscode.Existing');
  const stale = declaration('interface:vscode.Stale');
  writeBaseline(series, '1.0.0', [existing]);
  writeOverrides(series, '1.0.0', {
    [stale.id]: reviewedExclusion(stale),
  });

  const result = runSeriesCheck(series, '1.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^UNCLASSIFIED_BASELINE_DELTA: /);
  assert.match(result.stderr, /interface:vscode\.Stale/);
  assert.match(result.stderr, /candidate public declaration/);
});

test('baseline series rejects an override for a different VS Code version', (context) => {
  const series = createSeries(context);
  writeBaseline(series, '1.0.0', [declaration('interface:vscode.Existing')]);
  writeOverrides(series, '1.0.0', {}, '9.9.9');

  const result = runSeriesCheck(series, '1.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^INVALID_BASELINE_SERIES: /);
  assert.match(result.stderr, /expected 1\.0\.0, found 9\.9\.9/);
});

test('baseline series rejects stale seed evidence hashes', (context) => {
  const series = createSeries(context);
  writeBaseline(series, '1.0.0', [declaration('interface:vscode.Existing')]);
  writeOverrides(series, '1.0.0', {}, '1.0.0', {
    manifestValidatorSha256: '0'.repeat(64),
  });

  const result = runSeriesCheck(series, '1.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^UNCLASSIFIED_BASELINE_DELTA: /);
  assert.match(result.stderr, /1\.0\.0 seed/);
  assert.match(result.stderr, /manifestValidatorSha256/);
  assert.match(result.stderr, /does not match candidate evidence/);
});

test('baseline series rejects an override without a matching baseline', (context) => {
  const series = createSeries(context);
  writeBaseline(series, '1.0.0', [declaration('interface:vscode.Existing')]);
  writeOverrides(series, '1.0.0', {});
  writeOverrides(series, '1.1.0', {});

  const result = runSeriesCheck(series, '1.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^INVALID_BASELINE_SERIES: /);
  assert.match(result.stderr, /override 1\.1\.0 has no matching baseline/);
});

test('baseline series rejects an unclassified new public API', (context) => {
  const series = createSeries(context);
  writeBaseline(series, '1.0.0', [declaration('interface:vscode.Existing')]);
  writeOverrides(series, '1.0.0', {});
  writeBaseline(series, '1.1.0', [
    declaration('interface:vscode.Existing'),
    declaration('interface:vscode.NewApi'),
  ]);
  writeOverrides(series, '1.1.0', {});

  const result = runSeriesCheck(series, '1.0.0');

  assert.equal(result.status, 1);
  assert.match(result.stderr, /^UNCLASSIFIED_BASELINE_DELTA: /);
  assert.match(result.stderr, /1\.0\.0 -> 1\.1\.0/);
  assert.match(result.stderr, /interface:vscode\.NewApi/);
  assert.match(result.stderr, /new public symbol/);
});

test(
  'baseline series rejects an unclassified public shape change',
  (context) => {
    const series = createSeries(context);
    const id = 'property:interface:vscode.Options/$instance/value';
    writeBaseline(series, '1.0.0', [
      declaration(id, {type: {kind: 'primitive', name: 'string'}}),
    ]);
    writeOverrides(series, '1.0.0', {});
    writeBaseline(series, '1.1.0', [
      declaration(id, {type: {kind: 'primitive', name: 'number'}}),
    ]);
    writeOverrides(series, '1.1.0', {});

    const result = runSeriesCheck(series, '1.0.0');

    assert.equal(result.status, 1);
    assert.match(result.stderr, /^UNCLASSIFIED_BASELINE_DELTA: /);
    assert.match(result.stderr, /1\.0\.0 -> 1\.1\.0/);
    assert.match(result.stderr, /Options\/\$instance\/value/);
    assert.match(result.stderr, /changed public symbol/);
  },
);

test(
  'baseline series accepts valid classifications for adjacent candidates',
  (context) => {
    const series = createSeries(context);
    const existing = declaration('interface:vscode.Existing');
    const first = declaration('interface:vscode.FirstApi');
    const second = declaration('interface:vscode.SecondApi');
    writeBaseline(series, '1.9.0', [existing]);
    writeOverrides(series, '1.9.0', {});
    writeBaseline(series, '1.10.0', [existing, first]);
    writeOverrides(series, '1.10.0', {
      [first.id]: reviewedExclusion(first),
    });
    writeBaseline(series, '1.11.0', [existing, first, second]);
    writeOverrides(series, '1.11.0', {
      [second.id]: reviewedExclusion(second),
    });

    const result = runSeriesCheck(series, '1.9.0');

    assert.equal(result.status, 0, result.stderr);
  },
);

function createSeries(context) {
  const root = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-baseline-series-'),
  );
  context.after(() => fs.rmSync(root, {recursive: true, force: true}));
  const irDirectory = path.join(root, 'ir');
  const overridesDirectory = path.join(root, 'overrides');
  fs.mkdirSync(irDirectory);
  fs.mkdirSync(overridesDirectory);
  return {irDirectory, overridesDirectory};
}

function runSeriesCheck(series, seed) {
  return spawnSync(
    process.execPath,
    [
      seriesCheckPath,
      '--ir-directory',
      series.irDirectory,
      '--overrides-directory',
      series.overridesDirectory,
      '--seed',
      seed,
    ],
    {encoding: 'utf8'},
  );
}

function writeBaseline(series, version, declarations) {
  writeJson(
    path.join(series.irDirectory, `vscode-${version}.json`),
    inventory(version, [...declarations, evidenceAnchor()]),
  );
}

function writeOverrides(
  series,
  version,
  entries,
  declaredVersion = version,
  rootOverrides = {},
) {
  const anchor = evidenceAnchor();
  const completeEntries = {
    [anchor.id]: {
      strategy: 'opaqueHostObject',
      declarationSha256: declarationSha256(anchor),
      hostContract: 'checkpointExtensionHost',
    },
    ...entries,
  };
  writeJson(
    path.join(series.overridesDirectory, `vscode-${version}.json`),
    {
      schemaVersion: 1,
      vscodeVersion: declaredVersion,
      manifestSchemaSha256: '1'.repeat(64),
      manifestValidatorSha256: '2'.repeat(64),
      commandsContributionSchemaSha256: '3'.repeat(64),
      viewsContributionSchemaSha256: '5'.repeat(64),
      configurationContributionSchemaSha256: '6'.repeat(64),
      hostContracts: {
        checkpointExtensionHost: {
          boundary: 'vscodeExtensionHost',
          artifact:
            'tool/bindings/contracts/checkpoint-extension-host.json',
          artifactSha256: 'a'.repeat(64),
        },
      },
      targets: Object.keys(completeEntries),
      entries: completeEntries,
      ...rootOverrides,
    },
  );
}

function inventory(version, declarations) {
  return {
    schemaVersion: 1,
    source: {product: {version}},
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

function reviewedExclusion(value) {
  return {
    strategy: 'reviewedExcluded',
    declarationSha256: declarationSha256(value),
    reason: 'Explicitly outside this simulated binding slice.',
  };
}

function declarationSha256(value) {
  return crypto
    .createHash('sha256')
    .update(canonicalJson(value))
    .digest('hex');
}

function evidenceAnchor() {
  return declaration('interface:vscode.EvidenceAnchor');
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

function writeJson(filePath, value) {
  fs.writeFileSync(filePath, `${JSON.stringify(value, null, 2)}\n`);
}
