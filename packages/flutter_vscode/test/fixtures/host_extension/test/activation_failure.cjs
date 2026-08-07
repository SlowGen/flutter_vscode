const assert = require('node:assert/strict');
const vscode = require('vscode');

const extensionId = 'flutter-vscode-test.host-extension-fixture';
const eventCountCommandId = 'flutter-vscode.host-test.openEventCount';

async function run() {
  console.log('[host-test] RED/GREEN: real-host activation failure');

  const extension = vscode.extensions.getExtension(extensionId);
  assert.ok(extension, `Expected VS Code to discover ${extensionId}`);
  assert.equal(extension.isActive, false, 'Fixture activated before the test');

  await assert.rejects(extension.activate(), (error) => {
    assert.match(error.message, /Dart host activation failed intentionally/);
    assert.match(error.stack, /host\/lib\/extension\.dart:\d+:\d+/);
    assert.doesNotMatch(error.stack, /extension\.dart\.js:\d+:\d+/);
    return true;
  });

  await assert.rejects(
    vscode.commands.executeCommand(eventCountCommandId),
    /command .* not found/i,
  );
  const document = await vscode.workspace.openTextDocument({
    language: 'plaintext',
    content: 'event after failed activation',
  });
  const hovers = await vscode.commands.executeCommand(
    'vscode.executeHoverProvider',
    document.uri,
    new vscode.Position(0, 1),
  );
  assert.deepEqual(
    hovers,
    [],
    'The hover provider registered before activation failure leaked',
  );
  await assert.rejects(
    vscode.commands.executeCommand(eventCountCommandId),
    /command .* not found/i,
  );
}

module.exports = {run};
