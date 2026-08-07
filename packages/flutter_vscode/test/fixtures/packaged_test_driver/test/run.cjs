'use strict';

const assert = require('node:assert/strict');
const path = require('node:path');
const vscode = require('vscode');

function isInside(parent, child) {
  const relative = path.relative(path.resolve(parent), path.resolve(child));
  return relative !== '' && !relative.startsWith(`..${path.sep}`) &&
    relative !== '..' && !path.isAbsolute(relative);
}

async function waitFor(predicate, message) {
  const deadline = Date.now() + 5000;
  while (!predicate()) {
    if (Date.now() >= deadline) {
      assert.fail(message);
    }
    await new Promise((resolve) => setTimeout(resolve, 25));
  }
}

async function run() {
  console.log('[packaged-host-test] checking installed extension auto-activation');

  const extensionsDir =
    process.env.FLUTTER_VSCODE_PACKAGED_EXTENSIONS_DIR;
  assert.ok(extensionsDir, 'The isolated extensions directory was not passed');
  const targetExtensionId = process.env.FLUTTER_VSCODE_PACKAGED_EXTENSION_ID;
  assert.ok(targetExtensionId, 'The scaffolded extension id was not passed');
  const commandId = process.env.FLUTTER_VSCODE_PACKAGED_COMMAND_ID;
  assert.ok(commandId, 'The scaffolded command id was not passed');
  const commandResult = process.env.FLUTTER_VSCODE_PACKAGED_COMMAND_RESULT;
  assert.ok(commandResult, 'The scaffolded command result was not passed');
  const viewCommandId =
    process.env.FLUTTER_VSCODE_PACKAGED_VIEW_COMMAND_ID;

  const extension = vscode.extensions.getExtension(targetExtensionId);
  assert.ok(extension, `Expected VS Code to discover ${targetExtensionId}`);
  assert.equal(
    isInside(extensionsDir, extension.extensionPath),
    true,
    `Expected ${extension.extensionPath} to be installed inside ${extensionsDir}`,
  );
  assert.equal(
    extension.isActive,
    false,
    'The extension activated before its first language document opened',
  );
  const activationLanguage = 'json';
  assert.ok(
    extension.packageJSON.activationEvents.includes(
      `onLanguage:${activationLanguage}`,
    ),
    'The installed extension does not declare its language activation event',
  );

  console.log('[packaged-host-test] checking hover-first auto-activation');
  const document = await vscode.workspace.openTextDocument({
    language: activationLanguage,
    content: 'hover target',
  });
  const position = new vscode.Position(0, 2);
  assert.equal(
    extension.isActive,
    false,
    'The target activated before its supported document was shown',
  );
  await vscode.window.showTextDocument(document);
  await waitFor(
    () => extension.isActive,
    'Opening a supported document did not auto-activate the target',
  );
  const hovers = await vscode.commands.executeCommand(
    'vscode.executeHoverProvider',
    document.uri,
    position,
  );

  assert.equal(hovers.length, 1);
  assert.ok(hovers[0] instanceof vscode.Hover);
  assert.equal(hovers[0].contents.length, 1);
  assert.ok(hovers[0].contents[0] instanceof vscode.MarkdownString);
  assert.equal(hovers[0].contents[0].value, 'Hover from Dart at 0:2');
  assert.deepEqual(hovers[0].range, new vscode.Range(0, 0, 0, 5));

  const result = await vscode.commands.executeCommand(commandId);
  assert.equal(result, commandResult);

  if (viewCommandId) {
    console.log('[packaged-host-test] checking packaged Flutter View v1');
    const viewReport = await vscode.commands.executeCommand(viewCommandId);
    assert.equal(viewReport.renderedValue, 'hello from Host Dart');
    assert.equal(viewReport.closed, true);
    assert.equal(viewReport.viewPendingRequests, 0);
    assert.equal(viewReport.viewSubscriptions, 0);
    assert.equal(viewReport.hostPendingRequests, 0);
    assert.equal(viewReport.hostSubscriptions, 0);
    assert.equal(viewReport.hostPendingSends, 0);
    assert.equal(viewReport.hostObservedRenderCount, 1);
    assert.ok(
      Number.isFinite(viewReport.viewColdStartMs) &&
        viewReport.viewColdStartMs > 0 &&
        viewReport.viewColdStartMs < 60000,
      `viewColdStartMs out of range: ${viewReport.viewColdStartMs}`,
    );
    console.log(
      `[host-test] Flutter View cold start (webview load to first ` +
        `rendered frame): ${viewReport.viewColdStartMs}ms`,
    );

    console.log('[packaged-host-test] checking the host network story');
    const registered = await vscode.commands.getCommands(true);
    if (registered.includes('flutter-vscode.host-test.hostFetchProbe')) {
      const http = require('node:http');
      const server = http.createServer((request, response) => {
        response.writeHead(200, {'content-type': 'text/plain'});
        response.end('pong-from-driver');
      });
      await new Promise((resolve) =>
        server.listen(0, '127.0.0.1', resolve),
      );
      try {
        const fetchReport = await vscode.commands.executeCommand(
          'flutter-vscode.host-test.hostFetchProbe',
          server.address().port,
        );
        assert.equal(fetchReport, '200:pong-from-driver');
      } finally {
        server.close();
      }
    }

    console.log(
      '[packaged-host-test] checking real-webview disallowed operation',
    );
    const adversityReport = await vscode.commands.executeCommand(
      'flutter-vscode.host-test.probeFlutterViewProtocol',
    );
    assert.equal(
      adversityReport.disallowedOperationCode,
      'operation_not_allowed',
    );
    assert.equal(adversityReport.structuredErrorCode, 'operation_failed');
    assert.match(
      adversityReport.structuredErrorMessage,
      /failed intentionally/,
    );
    assert.equal(adversityReport.wrongNonceFramesInjected, 2);
    assert.equal(adversityReport.wrongNonceHandlerInvocations, 0);
    assert.equal(adversityReport.malformedSchemaFramesInjected, 2);
    assert.equal(adversityReport.malformedSchemaHandlerInvocations, 0);
    assert.equal(adversityReport.unsupportedVersionFramesInjected, 2);
    assert.equal(adversityReport.unsupportedVersionHandlerInvocations, 0);
    assert.equal(adversityReport.readyFramesObserved, 2);
    assert.equal(adversityReport.reloadCount, 1);
    assert.equal(adversityReport.pendingRequestsBeforeReload, 1);
    assert.equal(adversityReport.hostPendingRequestsBeforeShutdown, 2);
    assert.equal(adversityReport.hostPendingRequestsAtClose, 2);
    assert.equal(adversityReport.viewPendingRequests, 0);
    assert.equal(adversityReport.viewSubscriptions, 0);
    assert.equal(adversityReport.hostPendingRequests, 0);
    assert.equal(adversityReport.hostSubscriptions, 0);
    assert.equal(adversityReport.hostPendingSends, 0);
    assert.equal(adversityReport.hostObservedRenderCount, 1);

    assert.equal(
      await vscode.commands.executeCommand(commandId),
      commandResult,
      'Host command failed after packaged Flutter View cleanup',
    );
    const hoversAfterView = await vscode.commands.executeCommand(
      'vscode.executeHoverProvider',
      document.uri,
      position,
    );
    assert.equal(hoversAfterView.length, 1);
    assert.ok(hoversAfterView[0] instanceof vscode.Hover);
  }
}

module.exports = {run};
