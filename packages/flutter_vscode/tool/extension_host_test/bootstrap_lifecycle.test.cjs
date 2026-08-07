const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const fs = require('node:fs');
const Module = require('node:module');
const path = require('node:path');
const test = require('node:test');

const packageRoot = path.resolve(__dirname, '../..');
const fixtureRoot = path.join(
  packageRoot,
  'test',
  'fixtures',
  'host_extension',
);
const bootstrapPath = path.join(fixtureRoot, 'out', 'bootstrap.cjs');
const dartBundlePath = path.join(fixtureRoot, 'out', 'extension.dart.js');
const extensionId = 'flutter-vscode-test.host-extension-fixture';
const extensionKey = `e_${crypto
  .createHash('sha256')
  .update(extensionId)
  .digest('hex')}`;

test('failed activation rolls back each new registration once', async () => {
  const bootstrapSource = fs.readFileSync(bootstrapPath, 'utf8');
  assert.doesNotMatch(
    bootstrapSource,
    /FLUTTER_VSCODE_HOST_TEST_FAIL_ACTIVATION|failActivation/,
  );

  const contextDisposals = new Map();
  let eventDisposals = 0;
  let preexistingDisposals = 0;
  const disposable = (label) => {
    contextDisposals.set(label, 0);
    return {
      dispose() {
        contextDisposals.set(label, contextDisposals.get(label) + 1);
      },
    };
  };
  const fakeVscode = {
    commands: {
      registerCommand(command) {
        if (command === 'flutter-vscode.host-test.openEventCount') {
          throw new Error('injected activation failure');
        }
        return disposable(command);
      },
    },
    languages: {
      registerHoverProvider(selector) {
        return disposable(`${selector} hover provider`);
      },
    },
    workspace: {
      onDidOpenTextDocument() {
        return {
          dispose() {
            eventDisposals += 1;
          },
        };
      },
    },
  };
  const preexisting = {
    dispose() {
      preexistingDisposals += 1;
    },
  };
  const context = {subscriptions: [preexisting]};

  const originalLoad = Module._load;
  const hadSelf = Object.hasOwn(globalThis, 'self');
  const originalSelf = globalThis.self;
  const originalNamespace = globalThis.__flutterVscode;

  Module._load = function load(request, parent, isMain) {
    if (request === 'vscode') {
      return fakeVscode;
    }
    return originalLoad.call(this, request, parent, isMain);
  };

  delete require.cache[bootstrapPath];
  delete require.cache[dartBundlePath];
  delete globalThis.__flutterVscode;

  try {
    const lifecycle = require(bootstrapPath);
    assert.notEqual(
      globalThis.__flutterVscode.hosts[extensionKey],
      undefined,
    );
    assert.notEqual(
      globalThis.__flutterVscode.apis[extensionKey],
      undefined,
    );
    assert.equal(
      globalThis.__flutterVscode.hosts.e_host_extension_fixture,
      undefined,
    );
    await assert.rejects(lifecycle.activate(context), (error) => {
      assert.match(error.message, /injected activation failure/);
      assert.match(error.stack, /extension\.dart/);
      return true;
    });
    assert.equal(eventDisposals, 1);
    assert.deepEqual(
      [...contextDisposals.values()],
      [1, 1, 1, 1, 1, 1, 1, 1, 1],
    );
    assert.equal(preexistingDisposals, 0);
    assert.deepEqual(context.subscriptions, [preexisting]);

    await lifecycle.deactivate();
    await lifecycle.deactivate();
    assert.equal(eventDisposals, 1);
    assert.deepEqual(
      [...contextDisposals.values()],
      [1, 1, 1, 1, 1, 1, 1, 1, 1],
    );
    assert.equal(preexistingDisposals, 0);
    assert.deepEqual(context.subscriptions, [preexisting]);
  } finally {
    Module._load = originalLoad;
    delete require.cache[bootstrapPath];
    delete require.cache[dartBundlePath];
    if (originalNamespace === undefined) {
      delete globalThis.__flutterVscode;
    } else {
      globalThis.__flutterVscode = originalNamespace;
    }
    if (hadSelf) {
      globalThis.self = originalSelf;
    } else {
      delete globalThis.self;
    }
  }
});

test('development mode reloads the window when the host bundle changes',
    async () => {
  const os = require('node:os');
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'flutter-vscode-reload-'));
  fs.mkdirSync(path.join(temp, 'out'), {recursive: true});
  const tempBootstrap = path.join(temp, 'out', 'bootstrap.cjs');
  const tempBundle = path.join(temp, 'out', 'extension.dart.js');
  fs.copyFileSync(bootstrapPath, tempBootstrap);
  fs.copyFileSync(dartBundlePath, tempBundle);
  fs.copyFileSync(`${dartBundlePath}.map`, `${tempBundle}.map`);
  fs.copyFileSync(
    path.join(fixtureRoot, 'package.json'),
    path.join(temp, 'package.json'),
  );

  const executed = [];
  const fakeVscode = {
    ExtensionMode: {Production: 1, Development: 2, Test: 3},
    commands: {
      executeCommand(id) {
        executed.push(id);
        return Promise.resolve();
      },
      registerCommand(command) {
        if (command === 'flutter-vscode.host-test.openEventCount') {
          throw new Error('injected activation failure');
        }
        return {dispose() {}};
      },
    },
    languages: {registerHoverProvider: () => ({dispose() {}})},
    workspace: {onDidOpenTextDocument: () => ({dispose() {}})},
  };
  const context = {subscriptions: [], extensionMode: 2};

  const originalLoad = Module._load;
  const originalNamespace = globalThis.__flutterVscode;
  Module._load = function load(request, parent, isMain) {
    if (request === 'vscode') {
      return fakeVscode;
    }
    return originalLoad.call(this, request, parent, isMain);
  };
  delete require.cache[tempBootstrap];
  delete require.cache[tempBundle];
  delete globalThis.__flutterVscode;

  try {
    const lifecycle = require(tempBootstrap);
    await assert.rejects(lifecycle.activate(context), /injected activation/);
    await new Promise((resolve) => setTimeout(resolve, 100));
    fs.appendFileSync(tempBundle, '\n// rebuilt\n');
    const deadline = Date.now() + 5000;
    while (!executed.includes('workbench.action.reloadWindow')) {
      if (Date.now() > deadline) {
        assert.fail(
          'The development host never requested a window reload after ' +
            'the bundle changed.',
        );
      }
      await new Promise((resolve) => setTimeout(resolve, 50));
    }
  } finally {
    Module._load = originalLoad;
    globalThis.__flutterVscode = originalNamespace;
    for (const subscription of context.subscriptions) {
      try {
        subscription.dispose();
      } catch {
        // Cleanup only.
      }
    }
    fs.rmSync(temp, {recursive: true, force: true});
  }
});
