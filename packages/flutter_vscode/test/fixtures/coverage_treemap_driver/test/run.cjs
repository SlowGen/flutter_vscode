'use strict';

const assert = require('node:assert/strict');
const vscode = require('vscode');

const extensionId = 'local.coverage-treemap';

async function run() {
  console.log('[coverage-treemap-test] locating the installed extension');
  const workspaceFolders = vscode.workspace.workspaceFolders;
  assert.ok(
    Array.isArray(workspaceFolders) && workspaceFolders.length === 1,
    'The coverage workspace folder was not opened',
  );

  const extension = vscode.extensions.getExtension(extensionId);
  assert.ok(extension, `Expected VS Code to discover ${extensionId}`);
  await extension.activate();
  assert.equal(extension.isActive, true);

  console.log('[coverage-treemap-test] asserting the parsed lcov snapshot');
  const smokeJson = await vscode.commands.executeCommand(
    'coverage-treemap.smoke',
  );
  assert.equal(typeof smokeJson, 'string');
  const snapshot = JSON.parse(smokeJson);
  assert.ok(snapshot, 'The smoke command found no coverage data');
  assert.equal(snapshot.lcovPath, 'coverage/lcov.info');
  assert.equal(snapshot.root.linesFound, 6);
  assert.equal(snapshot.root.linesHit, 3);
  const lib = snapshot.root.children.find((node) => node.name === 'lib');
  assert.ok(lib, 'The snapshot tree has no lib directory');
  assert.equal(lib.linesFound, 6);
  const mainFile = lib.children.find((node) => node.name === 'main.dart');
  assert.ok(mainFile, 'The snapshot tree has no lib/main.dart');
  assert.equal(mainFile.isFile, true);
  assert.equal(mainFile.linesFound, 3);
  assert.equal(mainFile.linesHit, 2);

  console.log(
    '[coverage-treemap-test] booting the Flutter View in a real webview',
  );
  const viewJson = await vscode.commands.executeCommand(
    'coverage-treemap.viewSmoke',
  );
  assert.equal(typeof viewJson, 'string');
  const viewReport = JSON.parse(viewJson);
  assert.equal(viewReport.viewConnected, true);
  assert.equal(
    viewReport.firstFramePainted,
    true,
    'the view must confirm a painted first frame, not just a connection',
  );
  assert.equal(viewReport.lcovPath, 'coverage/lcov.info');

  console.log('[coverage-treemap-test] verifying host-to-view snapshot push');
  const fs = require('node:fs');
  const path = require('node:path');
  const lcovPath = path.join(
    workspaceFolders[0].uri.fsPath,
    'coverage',
    'lcov.info',
  );
  fs.writeFileSync(
    lcovPath,
    [
      'SF:lib/main.dart',
      'DA:1,4',
      'DA:2,0',
      'DA:3,1',
      'DA:4,1',
      'DA:5,0',
      'DA:6,1',
      'LF:6',
      'LH:4',
      'end_of_record',
      'SF:lib/src/util.dart',
      'DA:1,0',
      'DA:2,0',
      'DA:3,5',
      'LF:3',
      'LH:1',
      'end_of_record',
      '',
    ].join('\n'),
  );
  const pushDeadline = Date.now() + 60000;
  for (;;) {
    const pushJson = await vscode.commands.executeCommand(
      'coverage-treemap.pushSmoke',
    );
    const push = JSON.parse(pushJson);
    if (push.pushesApplied >= 1 && push.lastAppliedLinesFound === 9) {
      console.log(
        `[coverage-treemap-test] view applied pushed snapshot ` +
          `(${push.pushesApplied} applied, ${push.pushesSent} sent)`,
      );
      break;
    }
    if (Date.now() > pushDeadline) {
      assert.fail(
        `The view never applied the pushed snapshot: ${pushJson}`,
      );
    }
    await new Promise((resolve) => setTimeout(resolve, 250));
  }

  console.log('[coverage-treemap-test] exercising the in-VSC coverage run');
  const terminalsBefore = vscode.window.terminals.length;
  await vscode.commands.executeCommand('coverage-treemap.runTests');
  assert.equal(
    vscode.window.terminals.length,
    terminalsBefore + 1,
    'runTests must create the coverage terminal',
  );
  assert.ok(
    vscode.window.terminals.some(
      (terminal) => terminal.name === 'Coverage Treemap',
    ),
    'The coverage terminal must carry the extension name',
  );

  console.log('[coverage-treemap-test] all assertions passed');
}

module.exports = {run};
