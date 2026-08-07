'use strict';

const crypto = require('node:crypto');
const fs = require('node:fs');
const manifest = require('../package.json');
const moduleApi = require('node:module');
const path = require('node:path');
const vscode = require('vscode');

process.setSourceMapsEnabled?.(true);
globalThis.self ??= globalThis;
const namespace = (globalThis.__flutterVscode ??= Object.create(null));
namespace.hosts ??= Object.create(null);
namespace.apis ??= Object.create(null);
namespace.callbackWrappers ??= Object.create(null);
namespace.stackMappers ??= Object.create(null);
const extensionId = `${manifest.publisher}.${manifest.name}`;
const extensionKey = `e_${crypto
  .createHash('sha256')
  .update(extensionId)
  .digest('hex')}`;
const emittedExtensionKey = "e_ded70adb722dcc045c085661384a28efd7439f252df0117d72ecce65644f64f6";
if (extensionKey !== emittedExtensionKey) {
  throw new Error('Generated Dart and manifest extension identities differ.');
}
namespace.apis[extensionKey] = vscode;

const hostBundlePath = path.resolve(__dirname, '../out/extension.dart.js');
const hostSourceMap = new moduleApi.SourceMap(
  JSON.parse(fs.readFileSync(`${hostBundlePath}.map`, 'utf8')),
);
const mapHostStack = (stack) => stack.replace(
  /[^\s()]*extension\.dart\.js:(\d+):(\d+)/g,
  (location, line, column) => {
    const entry = hostSourceMap.findEntry(
      Number(line) - 1,
      Number(column) - 1,
    );
    if (entry.originalSource === undefined) {
      return location;
    }
    const source = entry.originalSource.replace(/^(\.\.\/)+/, '');
    return `${source}:${entry.originalLine + 1}:${entry.originalColumn + 1}`;
  },
);
namespace.stackMappers[extensionKey] = mapHostStack;
namespace.callbackWrappers[extensionKey] = (callback) => function (...args) {
  try {
    return Reflect.apply(callback, this, args);
  } catch (error) {
    if (error && typeof error.stack === 'string') {
      error.stack = mapHostStack(error.stack);
    }
    throw error;
  }
};

require('../out/extension.dart.js');

const host = namespace.hosts[extensionKey];
if (!host) {
  throw new Error('Dart host did not register its lifecycle exports.');
}

let devReloadWatcher;
const startDevReload = (context) => {
  if (devReloadWatcher) {
    return;
  }
  const bundlePath = path.join(__dirname, '..', 'out', 'extension.dart.js');
  let debounce;
  devReloadWatcher = fs.watch(path.dirname(bundlePath), (_event, filename) => {
    if (filename !== path.basename(bundlePath)) {
      return;
    }
    clearTimeout(debounce);
    debounce = setTimeout(() => {
      vscode.commands.executeCommand('workbench.action.reloadWindow');
    }, 150);
  });
  context.subscriptions.push({
    dispose() {
      clearTimeout(debounce);
      try {
        devReloadWatcher.close();
      } catch {
        // The watcher may already be gone during host shutdown.
      }
      devReloadWatcher = undefined;
    },
  });
};

exports.activate = async (context) => {
  if (
    vscode.ExtensionMode &&
    context.extensionMode === vscode.ExtensionMode.Development
  ) {
    startDevReload(context);
  }
  const firstActivationSubscription = context.subscriptions.length;
  try {
    return await host.activate(context, vscode);
  } catch (error) {
    const registrations = context.subscriptions.splice(
      firstActivationSubscription,
    );
    for (const registration of registrations.reverse()) {
      try {
        await registration.dispose();
      } catch {
        // Preserve the activation failure after attempting every rollback.
      }
    }
    throw error;
  }
};
exports.deactivate = () => host.deactivate();
