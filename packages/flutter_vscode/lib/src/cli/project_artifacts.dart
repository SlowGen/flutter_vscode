/// Emission of Project-Derived Artifacts.
///
/// A build emits only files derived from the Extension Project itself:
/// the manifest, the CommonJS bootstrap, and the two generated Dart
/// modules that wire this extension's identity into the
/// `package:dart_vscode` runtime. The VS Code API surface is not
/// generated here — it ships inside `package:dart_vscode`, produced by
/// that package's maintainer pipeline.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_vscode/contributions.dart';

/// Emits every Project-Derived Artifact for [project], keyed by
/// project-relative POSIX path.
///
/// Throws a `ContributionException` with a stable diagnostic code when the
/// descriptor would be rejected by the pinned platform.
Map<String, String> emitProjectArtifacts(Map<String, Object?> project) {
  final manifest = ManifestProjection.fromProjectDescriptor(project);
  final extensionId = manifest.extensionId;
  final extensionKey = 'e_${sha256.convert(utf8.encode(extensionId))}';
  const encoder = JsonEncoder.withIndent('  ');
  final manifestJson = manifest.toManifestJson(main: './out/bootstrap.cjs');
  return <String, String>{
    'host/lib/generated/vscode_runtime.g.dart': _runtimeTemplate(extensionKey),
    'host/lib/generated/host_exports.g.dart': _hostExportsTemplate(
      dartExtensionId: jsonEncode(extensionId),
      extensionKey: extensionKey,
    ),
    'host/bootstrap.cjs': _bootstrapTemplate(
      javaScriptExtensionKey: jsonEncode(extensionKey),
    ),
    'package.json': '${encoder.convert(manifestJson)}\n',
  };
}

/// Renders the generated `host_exports.g.dart` module.
String _hostExportsTemplate({
  required String dartExtensionId,
  required String extensionKey,
}) {
  return '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: always_use_package_imports

import 'dart:js_interop';

import 'vscode_runtime.g.dart';

/// Fully qualified extension identifier used by the generated host.
// The JSON encoder deliberately emits a double-quoted, escaped Dart literal.
// ignore: prefer_single_quotes
const generatedExtensionId = $dartExtensionId;

/// Collision-resistant key used for this extension's JavaScript globals.
const generatedExtensionKey =
    '$extensionKey';

@JS(
  '__flutterVscode.hosts.$extensionKey',
)
external set _hostExports(JSObject value);

/// Publishes the Dart lifecycle object for the CommonJS bootstrap.
void registerHostExports(JSObject value) {
  installGeneratedHostRuntime();
  _hostExports = value;
}
''';
}

/// Renders the generated CommonJS bootstrap, `host/bootstrap.cjs`.
String _bootstrapTemplate({
  required String javaScriptExtensionKey,
}) {
  return '''
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
const extensionId = `\${manifest.publisher}.\${manifest.name}`;
const extensionKey = `e_\${crypto
  .createHash('sha256')
  .update(extensionId)
  .digest('hex')}`;
const emittedExtensionKey = $javaScriptExtensionKey;
if (extensionKey !== emittedExtensionKey) {
  throw new Error('Generated Dart and manifest extension identities differ.');
}
namespace.apis[extensionKey] = vscode;

const hostBundlePath = path.resolve(__dirname, '../out/extension.dart.js');
const hostSourceMap = new moduleApi.SourceMap(
  JSON.parse(fs.readFileSync(`\${hostBundlePath}.map`, 'utf8')),
);
const mapHostStack = (stack) => stack.replace(
  /[^\\s()]*extension\\.dart\\.js:(\\d+):(\\d+)/g,
  (location, line, column) => {
    const entry = hostSourceMap.findEntry(
      Number(line) - 1,
      Number(column) - 1,
    );
    if (entry.originalSource === undefined) {
      return location;
    }
    const source = entry.originalSource.replace(/^(\\.\\.\\/)+/, '');
    return `\${source}:\${entry.originalLine + 1}:\${entry.originalColumn + 1}`;
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
''';
}

/// Renders the generated runtime module, `vscode_runtime.g.dart`.
String _runtimeTemplate(String extensionKey) {
  // The body is written in the exact style the pinned SDK's formatter
  // produces, so `dart format` over an Extension Project cannot dirty it
  // and a rebuild reproduces the receipted bytes either way.
  return '''
// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: unnecessary_lambdas

import 'dart:js_interop';

import 'package:dart_vscode/host_runtime.dart';

@JS(
  '__flutterVscode.stackMappers.$extensionKey',
)
external JSString _mapHostStack(JSString stack);

@JS(
  '__flutterVscode.callbackWrappers.$extensionKey',
)
external JSFunction _wrapHostCallback(JSFunction callback);

/// Binds this extension's JavaScript globals into the framework runtime.
///
/// Only the two globals are per-extension; the code that uses them lives in
/// `package:dart_vscode/host_runtime.dart`.
void installGeneratedHostRuntime() => installHostRuntime(
  mapStack: (stack) => _mapHostStack(stack.toJS),
  wrapCallback: (callback) => _wrapHostCallback(callback),
);
''';
}
