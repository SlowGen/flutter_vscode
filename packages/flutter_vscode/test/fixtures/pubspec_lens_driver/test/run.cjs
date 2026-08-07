'use strict';

// Exercises the packaged pubspec-lens extension against a real
// Extension Host and a fake pub registry served from this driver.
//
// The port problem: the workspace settings file cannot name the
// registry URL before launch because the port is unknown until the
// server binds. So this driver starts the server first, then writes
// the URL through the configuration API. The extension declares the
// pubspecLens.registryUrl setting and the pubspecLens.dependencies
// view in its own typed manifest; this driver contributes nothing on
// its behalf.

const assert = require('node:assert/strict');
const http = require('node:http');
const vscode = require('vscode');

const extensionId = 'local.pubspec-lens';

const packages = {
  current_pkg: {
    name: 'current_pkg',
    latest: {
      version: '1.2.3',
      pubspec: {
        name: 'current_pkg',
        description: 'A test package that is already current.',
      },
    },
  },
  behind_pkg: {
    name: 'behind_pkg',
    latest: {
      version: '1.2.3',
      pubspec: {
        name: 'behind_pkg',
        description: 'A test package with a newer patch inside the caret.',
      },
    },
  },
  old_pkg: {
    name: 'old_pkg',
    latest: {
      version: '2.0.0',
      pubspec: {
        name: 'old_pkg',
        description: 'A test package with a newer major.',
      },
    },
  },
};

function lensFor(lenses, packageName) {
  return lenses.find(
    (lens) =>
      lens.command &&
      lens.command.command === 'pubspec-lens.update' &&
      Array.isArray(lens.command.arguments) &&
      lens.command.arguments[1] === packageName,
  );
}

function startFakeRegistry() {
  const server = http.createServer((request, response) => {
    const match = /^\/api\/packages\/([^/]+)$/.exec(request.url ?? '');
    const info = match ? packages[decodeURIComponent(match[1])] : undefined;
    if (!info) {
      response.writeHead(404, {'content-type': 'application/json'});
      response.end(JSON.stringify({error: {message: 'not found'}}));
      return;
    }
    response.writeHead(200, {'content-type': 'application/json'});
    response.end(JSON.stringify(info));
  });
  return new Promise((resolve) => {
    server.listen(0, '127.0.0.1', () => resolve(server));
  });
}

async function run() {
  console.log('[pubspec-lens-test] locating the installed extension');
  const workspaceFolders = vscode.workspace.workspaceFolders;
  assert.ok(
    Array.isArray(workspaceFolders) && workspaceFolders.length === 1,
    'The pubspec workspace folder was not opened',
  );
  const pubspecUri = vscode.Uri.joinPath(
    workspaceFolders[0].uri,
    'pubspec.yaml',
  );

  const extension = vscode.extensions.getExtension(extensionId);
  assert.ok(extension, `Expected VS Code to discover ${extensionId}`);
  await extension.activate();
  assert.equal(extension.isActive, true);

  console.log('[pubspec-lens-test] serving the fake registry');
  const server = await startFakeRegistry();
  try {
    const registryUrl = `http://127.0.0.1:${server.address().port}`;
    console.log(`[pubspec-lens-test] registry at ${registryUrl}`);
    await vscode.workspace
      .getConfiguration('pubspecLens')
      .update(
        'registryUrl',
        registryUrl,
        vscode.ConfigurationTarget.Workspace,
      );

    console.log('[pubspec-lens-test] refreshing against the fake registry');
    await vscode.commands.executeCommand('pubspec-lens.refresh');
    const smokeJson = await vscode.commands.executeCommand(
      'pubspec-lens.smoke',
    );
    assert.equal(typeof smokeJson, 'string');
    const report = JSON.parse(smokeJson);
    assert.equal(
      report.registryUrl,
      registryUrl,
      'The extension must read pubspecLens.registryUrl from configuration',
    );
    assert.equal(report.depsAnalyzed, 4);
    assert.equal(report.hosted, 3);
    assert.equal(report.behind, 1);
    assert.equal(report.outdated, 1);
    assert.equal(report.skipped, 1);
    // The smoke report's treeChildren reads the extension's internal model,
    // which proves the analysis but nothing about the contributed view. The
    // <viewId>.focus command exists only when VS Code accepted the views
    // contribution from the extension's own manifest, so this call is
    // contribution proof the extension cannot fake. (It also reveals the
    // view; what the provider then renders is not asserted here.)
    await vscode.commands.executeCommand('pubspecLens.dependencies.focus');
    console.log('[pubspec-lens-test] contributed view focused and rendered');

    assert.deepEqual(report.treeChildren, [
      'current_pkg — current (latest 1.2.3)',
      'behind_pkg — behind (^1.2.3 available)',
      'old_pkg — outdated (^2.0.0 available)',
      'local_dep — skipped (path)',
    ]);

    console.log('[pubspec-lens-test] asserting the hover on the outdated pin');
    const document = await vscode.workspace.openTextDocument(pubspecUri);
    const lines = document.getText().split('\n');
    const oldPkgLine = lines.findIndex((line) => line.includes('old_pkg'));
    assert.ok(oldPkgLine >= 0, 'The workspace pubspec must pin old_pkg');
    const hovers = await vscode.commands.executeCommand(
      'vscode.executeHoverProvider',
      pubspecUri,
      new vscode.Position(oldPkgLine, 3),
    );
    assert.ok(hovers.length >= 1, 'Expected a pubspec-lens hover');
    const hoverText = hovers
      .flatMap((hover) => hover.contents)
      .map((content) => (typeof content === 'string' ? content : content.value))
      .join('\n');
    assert.match(hoverText, /2\.0\.0/);
    assert.match(hoverText, /newer major/);

    console.log('[pubspec-lens-test] asserting the outdated diagnostic');
    const deadline = Date.now() + 15000;
    let diagnostics = [];
    for (;;) {
      diagnostics = vscode.languages.getDiagnostics(pubspecUri);
      if (diagnostics.length > 0 || Date.now() > deadline) {
        break;
      }
      await new Promise((resolve) => setTimeout(resolve, 250));
    }
    // Exactly one: the blocking pin. A trailing pin (behind_pkg) gets
    // a lens but never a squiggle, so the Problems panel keeps
    // meaning "this constraint blocks the latest release".
    assert.equal(
      diagnostics.length,
      1,
      `Expected exactly one diagnostic, got ${JSON.stringify(diagnostics)}`,
    );
    assert.equal(
      diagnostics[0].message,
      'old_pkg 2.0.0 is available (pinned ^0.9.0)',
    );
    assert.equal(
      diagnostics[0].severity,
      vscode.DiagnosticSeverity.Information,
    );
    assert.equal(diagnostics[0].source, 'pubspec-lens');
    assert.equal(diagnostics[0].range.start.line, oldPkgLine);

    console.log('[pubspec-lens-test] asserting a lens on both trailing pins');
    const lenses = await vscode.commands.executeCommand(
      'vscode.executeCodeLensProvider',
      pubspecUri,
    );
    assert.equal(
      lensFor(lenses, 'current_pkg'),
      undefined,
      'A pin already at the latest version must offer no lens',
    );
    const behindLens = lensFor(lenses, 'behind_pkg');
    assert.ok(behindLens, 'Expected a CodeLens on the trailing pin');
    assert.equal(behindLens.command.title, 'Update to ^1.2.3');
    const updateLens = lensFor(lenses, 'old_pkg');
    assert.ok(updateLens, 'Expected a CodeLens on the outdated pin');
    assert.equal(updateLens.command.title, 'Update to ^2.0.0');
    assert.equal(updateLens.range.start.line, oldPkgLine);

    console.log('[pubspec-lens-test] applying both CodeLens updates');
    for (const lens of [updateLens, behindLens]) {
      const applied = await vscode.commands.executeCommand(
        lens.command.command,
        ...lens.command.arguments,
      );
      assert.equal(applied, true, 'The WorkspaceEdit must apply');
    }
    const updated = await vscode.workspace.openTextDocument(pubspecUri);
    assert.ok(
      updated.getText().includes('old_pkg: ^2.0.0'),
      'The document must carry the rewritten blocking constraint',
    );
    assert.ok(
      updated.getText().includes('behind_pkg: ^1.2.3'),
      'The document must carry the rewritten trailing constraint',
    );

    console.log('[pubspec-lens-test] re-checking the tree after the edits');
    const afterJson = await vscode.commands.executeCommand(
      'pubspec-lens.smoke',
    );
    const after = JSON.parse(afterJson);
    assert.equal(after.behind, 0);
    assert.equal(after.outdated, 0);
    assert.deepEqual(after.treeChildren, [
      'current_pkg — current (latest 1.2.3)',
      'behind_pkg — current (latest 1.2.3)',
      'old_pkg — current (latest 2.0.0)',
      'local_dep — skipped (path)',
    ]);

    console.log('[pubspec-lens-test] all assertions passed');
  } finally {
    server.close();
  }
}

module.exports = {run};
