const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const test = require('node:test');

const {verifyPinnedInputs} = require('../src/pins.cjs');

const testCommit = '1111111111111111111111111111111111111111';
const differentCommit = '2222222222222222222222222222222222222222';
const testApiSource =
  `https://raw.githubusercontent.com/microsoft/vscode/${testCommit}/` +
  'src/vscode-dts/vscode.d.ts';
const officialKinds = [
  'apiDeclarations',
  'contributionSchemaSource',
  'contributionValidationHelperSource',
  'extensionManifestSchemaSource',
  'extensionManifestValidatorSource',
  'license',
];

function createRepositoryPinsFixture(context, prefix) {
  const repositoryManifestPath = path.resolve(
    __dirname,
    '..',
    '..',
    'bindings',
    'inputs',
    'vscode',
    '1.129.1',
    'pins.json',
  );
  const repositoryDirectory = path.dirname(repositoryManifestPath);
  const pins = JSON.parse(fs.readFileSync(repositoryManifestPath, 'utf8'));
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), prefix));
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  for (const input of pins.inputs) {
    fs.copyFileSync(
      path.resolve(repositoryDirectory, input.path),
      path.join(directory, input.path),
    );
  }
  return {
    pins,
    directory,
    write(manifest, name) {
      const manifestPath = path.join(directory, name);
      fs.writeFileSync(
        manifestPath,
        `${JSON.stringify(manifest, null, 2)}\n`,
      );
      return manifestPath;
    },
  };
}

test('checksum mismatch names the input and both hashes', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-pins-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));

  const expected = crypto.createHash('sha256').update('original').digest('hex');
  const actual = crypto.createHash('sha256').update('changed').digest('hex');
  fs.writeFileSync(path.join(directory, 'vscode.d.ts'), 'changed');
  const manifestPath = path.join(directory, 'pins.json');
  fs.writeFileSync(
    manifestPath,
    `${JSON.stringify(
      {
        schemaVersion: 1,
        product: {
          name: 'Visual Studio Code',
          version: '1.129.1',
          commit: testCommit,
        },
        inputs: [
          {
            name: 'VS Code API declarations',
            kind: 'apiDeclarations',
            path: 'vscode.d.ts',
            version: '1.129.1',
            commit: testCommit,
            source: testApiSource,
            sha256: expected,
            license: 'MIT',
          },
        ],
      },
      null,
      2,
    )}\n`,
  );

  assert.throws(
    () => verifyPinnedInputs(manifestPath),
    (error) => {
      assert.equal(error.code, 'PIN_CHECKSUM_MISMATCH');
      assert.match(error.message, /VS Code API declarations/);
      assert.match(error.message, new RegExp(expected));
      assert.match(error.message, new RegExp(actual));
      return true;
    },
  );
});

test('missing pin provenance fails before importing an input', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-pin-metadata-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const contents = 'pinned';
  const sha256 = crypto.createHash('sha256').update(contents).digest('hex');
  fs.writeFileSync(path.join(directory, 'vscode.d.ts'), contents);
  const manifestPath = path.join(directory, 'pins.json');
  fs.writeFileSync(
    manifestPath,
    `${JSON.stringify(
      {
        schemaVersion: 1,
        product: {
          name: 'Visual Studio Code',
          version: '1.129.1',
          commit: testCommit,
        },
        inputs: [
          {
            name: 'VS Code API declarations',
            kind: 'apiDeclarations',
            path: 'vscode.d.ts',
            version: '1.129.1',
            commit: testCommit,
            source: testApiSource,
            sha256,
          },
        ],
      },
      null,
      2,
    )}\n`,
  );

  assert.throws(
    () => verifyPinnedInputs(manifestPath),
    (error) => {
      assert.equal(error.code, 'PIN_METADATA_INVALID');
      assert.match(error.message, /inputs\[0\]\.license/);
      return true;
    },
  );
});

test('unknown pinned input kinds fail closed', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-pin-kind-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const contents = 'pinned';
  const sha256 = crypto.createHash('sha256').update(contents).digest('hex');
  fs.writeFileSync(path.join(directory, 'future.schema.json'), contents);
  const manifestPath = path.join(directory, 'pins.json');
  fs.writeFileSync(
    manifestPath,
    `${JSON.stringify(
      {
        schemaVersion: 1,
        product: {
          name: 'Visual Studio Code',
          version: '1.129.1',
          commit: testCommit,
        },
        inputs: [
          {
            name: 'Future schema',
            kind: 'futureSchemaKind',
            path: 'future.schema.json',
            version: '1.129.1',
            commit: testCommit,
            source: 'https://example.invalid/future.schema.json',
            sha256,
            license: 'MIT',
          },
        ],
      },
      null,
      2,
    )}\n`,
  );

  assert.throws(
    () => verifyPinnedInputs(manifestPath),
    (error) => {
      assert.equal(error.code, 'PIN_METADATA_INVALID');
      assert.match(error.message, /inputs\[0\]\.kind/);
      assert.match(error.message, /futureSchemaKind/);
      return true;
    },
  );
});

test('pin input paths escaping the manifest directory fail closed', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-escape-',
  );
  const input = fixture.pins.inputs.find(
    (candidate) => candidate.kind === 'apiDeclarations',
  );
  const escapedName = `flutter-vscode-pin-escaped-${process.pid}.d.ts`;
  const escapedPath = path.join(fixture.directory, '..', escapedName);
  fs.copyFileSync(path.join(fixture.directory, input.path), escapedPath);
  context.after(() => fs.rmSync(escapedPath, {force: true}));
  input.path = `../${escapedName}`;
  const manifestPath = fixture.write(fixture.pins, 'pins.json');

  assert.throws(
    () => verifyPinnedInputs(manifestPath),
    (error) => {
      assert.equal(error.code, 'PIN_METADATA_INVALID');
      assert.match(error.message, /inside the pin manifest directory/);
      return true;
    },
  );
});

test('pin inputs behind escaping symlinks fail closed', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-symlink-',
  );
  const input = fixture.pins.inputs.find(
    (candidate) => candidate.kind === 'apiDeclarations',
  );
  const escapedName = `flutter-vscode-pin-symlink-target-${process.pid}.d.ts`;
  const escapedPath = path.join(fixture.directory, '..', escapedName);
  fs.copyFileSync(path.join(fixture.directory, input.path), escapedPath);
  context.after(() => fs.rmSync(escapedPath, {force: true}));
  fs.rmSync(path.join(fixture.directory, input.path));
  fs.symlinkSync(escapedPath, path.join(fixture.directory, input.path));
  const manifestPath = fixture.write(fixture.pins, 'pins.json');

  assert.throws(
    () => verifyPinnedInputs(manifestPath),
    (error) => {
      assert.equal(error.code, 'PIN_METADATA_INVALID');
      assert.match(error.message, /inside the pin manifest directory/);
      return true;
    },
  );
});

test('absolute pin input paths fail closed', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-absolute-',
  );
  const input = fixture.pins.inputs.find(
    (candidate) => candidate.kind === 'apiDeclarations',
  );
  input.path = path.join(fixture.directory, input.path);
  const manifestPath = fixture.write(fixture.pins, 'pins.json');

  assert.throws(
    () => verifyPinnedInputs(manifestPath),
    (error) => {
      assert.equal(error.code, 'PIN_METADATA_INVALID');
      assert.match(error.message, /inside the pin manifest directory/);
      return true;
    },
  );
});

test('v1 pins require exactly one receipt of every official kind', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-cardinality-',
  );

  for (const kind of officialKinds) {
    for (const [scenario, mutate, expectedCount] of [
      [
        'missing',
        (manifest) => {
          manifest.inputs = manifest.inputs.filter(
            (input) => input.kind !== kind,
          );
        },
        0,
      ],
      [
        'duplicate',
        (manifest) => {
          const input = manifest.inputs.find(
            (candidate) => candidate.kind === kind,
          );
          manifest.inputs.push({...input});
        },
        2,
      ],
    ]) {
      const manifest = structuredClone(fixture.pins);
      mutate(manifest);
      const manifestPath = fixture.write(
        manifest,
        `${scenario}-${kind}.json`,
      );
      assert.throws(
        () => verifyPinnedInputs(manifestPath),
        (error) => {
          assert.equal(error.code, 'PIN_METADATA_INVALID');
          assert.match(error.message, new RegExp(kind));
          assert.match(error.message, /exactly one/);
          assert.match(error.message, new RegExp(`found ${expectedCount}`));
          return true;
        },
        `${scenario} ${kind}`,
      );
    }
  }
});

test('v1 pins require exactly the pinned contribution schemas', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-contributions-',
  );
  const cases = [
    ['missing', undefined],
    ['empty', []],
    ['duplicate', ['commands', 'commands']],
    ['unknown', ['other']],
    ['extra', ['commands', 'other']],
    ['stale single-schema form', ['commands']],
  ];

  for (const [name, contributionSchemas] of cases) {
    const manifest = structuredClone(fixture.pins);
    if (contributionSchemas === undefined) {
      delete manifest.contributionSchemas;
    } else {
      manifest.contributionSchemas = contributionSchemas;
    }
    const manifestPath = fixture.write(manifest, `${name}.json`);
    assert.throws(
      () => verifyPinnedInputs(manifestPath),
      (error) => {
        assert.equal(error.code, 'PIN_METADATA_INVALID');
        assert.match(error.message, /contributionSchemas/);
        assert.match(
          error.message,
          /exactly \["commands","configuration","views","viewsContainers"\]/,
        );
        return true;
      },
      name,
    );
  }
});

test('v1 pin documents reject missing and unexpected keys', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-shape-',
  );
  const cases = [
    [
      'root missing',
      (manifest) => delete manifest.parser,
      /pin root/,
      /missing parser/,
    ],
    [
      'root unexpected',
      (manifest) => {
        manifest.future = true;
      },
      /pin root/,
      /unexpected future/,
    ],
    [
      'product missing',
      (manifest) => delete manifest.product.name,
      /product/,
      /missing name/,
    ],
    [
      'product unexpected',
      (manifest) => {
        manifest.product.future = true;
      },
      /product/,
      /unexpected future/,
    ],
    [
      'parser missing',
      (manifest) => delete manifest.parser.version,
      /parser/,
      /missing version/,
    ],
    [
      'parser unexpected',
      (manifest) => {
        manifest.parser.future = true;
      },
      /parser/,
      /unexpected future/,
    ],
    [
      'manifest schema missing',
      (manifest) => delete manifest.manifestSchema.composition,
      /manifestSchema/,
      /missing composition/,
    ],
    [
      'manifest schema unexpected',
      (manifest) => {
        manifest.manifestSchema.future = true;
      },
      /manifestSchema/,
      /unexpected future/,
    ],
    [
      'input unexpected',
      (manifest) => {
        manifest.inputs[0].future = true;
      },
      /inputs\[0\]/,
      /unexpected future/,
    ],
  ];

  for (const [name, mutate, subject, detail] of cases) {
    const manifest = structuredClone(fixture.pins);
    mutate(manifest);
    const manifestPath = fixture.write(
      manifest,
      `${name.replaceAll(' ', '-')}.json`,
    );
    assert.throws(
      () => verifyPinnedInputs(manifestPath),
      (error) => {
        assert.equal(error.code, 'PIN_METADATA_INVALID');
        assert.match(error.message, subject);
        assert.match(error.message, detail);
        return true;
      },
      name,
    );
  }
});

test('v1 pin source metadata matches generator-visible value shapes', (context) => {
  const fixture = createRepositoryPinsFixture(
    context,
    'flutter-vscode-pin-values-',
  );
  const cases = [
    [
      'product name',
      (manifest) => {
        manifest.product.name = '';
      },
      /product\.name/,
      /non-empty string/,
    ],
    [
      'parser name',
      (manifest) => {
        manifest.parser.name = 'future';
      },
      /parser\.name/,
      /typescript/,
    ],
    [
      'parser version',
      (manifest) => {
        manifest.parser.version = '';
      },
      /parser\.version/,
      /non-empty string/,
    ],
    [
      'schema URI',
      (manifest) => {
        manifest.manifestSchema.schemaUri = '';
      },
      /manifestSchema\.schemaUri/,
      /non-empty string/,
    ],
    [
      'standalone',
      (manifest) => {
        manifest.manifestSchema.standalone = 'false';
      },
      /manifestSchema\.standalone/,
      /boolean/,
    ],
    [
      'composition',
      (manifest) => {
        manifest.manifestSchema.composition = '';
      },
      /manifestSchema\.composition/,
      /non-empty string/,
    ],
    [
      'license path',
      (manifest) => {
        manifest.inputs[0].licensePath = '';
      },
      /inputs\[0\]\.licensePath/,
      /non-empty string/,
    ],
  ];

  for (const [name, mutate, subject, detail] of cases) {
    const manifest = structuredClone(fixture.pins);
    mutate(manifest);
    const manifestPath = fixture.write(
      manifest,
      `${name.replaceAll(' ', '-')}.json`,
    );
    assert.throws(
      () => verifyPinnedInputs(manifestPath),
      (error) => {
        assert.equal(error.code, 'PIN_METADATA_INVALID');
        assert.match(error.message, subject);
        assert.match(error.message, detail);
        return true;
      },
      name,
    );
  }
});

test('every official input matches the product version and commit', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-pin-product-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const contents = 'pinned';
  const sha256 = crypto.createHash('sha256').update(contents).digest('hex');
  fs.writeFileSync(path.join(directory, 'vscode.d.ts'), contents);

  for (const [label, provenance] of Object.entries({
    version: {version: '1.128.0', commit: testCommit},
    commit: {version: '1.129.1', commit: differentCommit},
  })) {
    const manifestPath = path.join(directory, `${label}-pins.json`);
    fs.writeFileSync(
      manifestPath,
      `${JSON.stringify({
        schemaVersion: 1,
        product: {
          name: 'Visual Studio Code',
          version: '1.129.1',
          commit: testCommit,
        },
        inputs: [
          {
            name: 'VS Code API declarations',
            kind: 'apiDeclarations',
            path: 'vscode.d.ts',
            ...provenance,
            source: testApiSource,
            sha256,
            license: 'MIT',
          },
        ],
      }, null, 2)}\n`,
    );

    assert.throws(
      () => verifyPinnedInputs(manifestPath),
      (error) => {
        assert.equal(error.code, 'PIN_METADATA_INVALID', label);
        assert.match(error.message, /inputs\[0\]/, label);
        assert.match(error.message, /must match product/, label);
        return true;
      },
      label,
    );
  }
});

test('official source URLs pin the canonical repository commit and path', (context) => {
  const directory = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-pin-source-'),
  );
  context.after(() => fs.rmSync(directory, {recursive: true, force: true}));
  const contents = 'pinned';
  const sha256 = crypto.createHash('sha256').update(contents).digest('hex');
  fs.writeFileSync(path.join(directory, 'vscode.d.ts'), contents);

  const cases = {
    origin: 'https://example.com/not-vscode.d.ts',
    commit:
      `https://raw.githubusercontent.com/microsoft/vscode/${differentCommit}/` +
      'src/vscode-dts/vscode.d.ts',
    path:
      `https://raw.githubusercontent.com/microsoft/vscode/${testCommit}/` +
      'README.md',
  };
  for (const [label, source] of Object.entries(cases)) {
    const manifestPath = path.join(directory, `${label}-pins.json`);
    fs.writeFileSync(
      manifestPath,
      `${JSON.stringify({
        schemaVersion: 1,
        product: {
          name: 'Visual Studio Code',
          version: '1.129.1',
          commit: testCommit,
        },
        inputs: [
          {
            name: 'VS Code API declarations',
            kind: 'apiDeclarations',
            path: 'vscode.d.ts',
            version: '1.129.1',
            commit: testCommit,
            source,
            sha256,
            license: 'MIT',
          },
        ],
      }, null, 2)}\n`,
    );

    assert.throws(
      () => verifyPinnedInputs(manifestPath),
      (error) => {
        assert.equal(error.code, 'PIN_METADATA_INVALID', label);
        assert.match(error.message, /inputs\[0\]\.source/, label);
        assert.match(error.message, /canonical microsoft\/vscode/, label);
        return true;
      },
      label,
    );
  }

  const movingCommit = JSON.parse(
    fs.readFileSync(path.join(directory, 'origin-pins.json'), 'utf8'),
  );
  movingCommit.product.commit = 'main';
  movingCommit.inputs[0].commit = 'main';
  movingCommit.inputs[0].source =
    'https://raw.githubusercontent.com/microsoft/vscode/main/' +
    'src/vscode-dts/vscode.d.ts';
  const movingCommitPath = path.join(directory, 'moving-commit-pins.json');
  fs.writeFileSync(
    movingCommitPath,
    `${JSON.stringify(movingCommit, null, 2)}\n`,
  );
  assert.throws(
    () => verifyPinnedInputs(movingCommitPath),
    (error) => {
      assert.equal(error.code, 'PIN_METADATA_INVALID');
      assert.match(error.message, /product commit/);
      assert.match(error.message, /40-character lowercase Git commit/);
      return true;
    },
  );
});

test('repository VS Code inputs match their recorded checksums', () => {
  const manifestPath = path.resolve(
    __dirname,
    '..',
    '..',
    'bindings',
    'inputs',
    'vscode',
    '1.129.1',
    'pins.json',
  );

  assert.doesNotThrow(() => verifyPinnedInputs(manifestPath));

  const pins = JSON.parse(fs.readFileSync(manifestPath, 'utf8'));
  const commands = pins.inputs.find(
    (input) => input.kind === 'contributionSchemaSource',
  );
  assert.deepEqual(commands, {
    name: 'VS Code commands contribution schema source',
    kind: 'contributionSchemaSource',
    path: 'menusExtensionPoint.ts',
    version: '1.129.1',
    commit: '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8',
    source:
      'https://raw.githubusercontent.com/microsoft/vscode/' +
      '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8/src/vs/workbench/' +
      'services/actions/common/menusExtensionPoint.ts',
    sha256:
      'a85c943ae42b2cdef0403070f78cfb9dbe7bcdc1fce7c57bf9ca2234d1e36a33',
    license: 'MIT',
    licensePath: 'LICENSE.txt',
  });
  const whitespaceHelper = pins.inputs.find(
    (input) => input.kind === 'contributionValidationHelperSource',
  );
  assert.deepEqual(whitespaceHelper, {
    name: 'VS Code string validation helper source',
    kind: 'contributionValidationHelperSource',
    path: 'strings.ts',
    version: '1.129.1',
    commit: '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8',
    source:
      'https://raw.githubusercontent.com/microsoft/vscode/' +
      '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8/src/vs/base/common/' +
      'strings.ts',
    sha256:
      'c65ae37d623cf8a1dd0a5083cbb3f09f3433342accdc220c6bb8076aa12a1eec',
    license: 'MIT',
    licensePath: 'LICENSE.txt',
  });
  const views = pins.inputs.find(
    (input) => input.kind === 'viewsContributionSchemaSource',
  );
  assert.deepEqual(views, {
    name: 'Views extension point source',
    kind: 'viewsContributionSchemaSource',
    path: 'viewsExtensionPoint.ts',
    version: '1.129.1',
    commit: '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8',
    source:
      'https://raw.githubusercontent.com/microsoft/vscode/' +
      '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8/src/vs/workbench/api/' +
      'browser/viewsExtensionPoint.ts',
    sha256:
      '17006750e3af4359fa5a518bf8dcb14beb060e98bc401245302a46030172a102',
    license: 'MIT',
    licensePath: 'LICENSE.txt',
  });
  const configuration = pins.inputs.find(
    (input) => input.kind === 'configurationContributionSchemaSource',
  );
  assert.deepEqual(configuration, {
    name: 'Configuration extension point source',
    kind: 'configurationContributionSchemaSource',
    path: 'configurationExtensionPoint.ts',
    version: '1.129.1',
    commit: '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8',
    source:
      'https://raw.githubusercontent.com/microsoft/vscode/' +
      '8a7abeba6e03ea3af87bfbce9a1b7e48fed567b8/src/vs/workbench/api/' +
      'common/configurationExtensionPoint.ts',
    sha256:
      'e9faa24f3835b807762aa069a8029c3b004b76a3e7f42ceddee598b71b26cb0a',
    license: 'MIT',
    licensePath: 'LICENSE.txt',
  });
  assert.deepEqual(pins.contributionSchemas, [
    'commands',
    'configuration',
    'views',
    'viewsContainers',
  ]);
});
