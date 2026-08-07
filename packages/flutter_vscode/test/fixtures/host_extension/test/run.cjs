const assert = require('node:assert/strict');
const vscode = require('vscode');

const extensionId = 'flutter-vscode-test.host-extension-fixture';
const commandId = 'flutter-vscode.host-test.ping';
const eventCountCommandId = 'flutter-vscode.host-test.openEventCount';
const unsubscribeCommandId = 'flutter-vscode.host-test.unsubscribeOpenEvent';
const identityCommandId = 'flutter-vscode.host-test.hoverDocumentMatchedEvent';
const failAsyncCommandId = 'flutter-vscode.host-test.failAsync';
const failSyncCommandId = 'flutter-vscode.host-test.failSync';
const jsPromiseSourceCommandId = 'flutter-vscode.host-test.jsPromiseSource';
const jsPromiseRoundTripCommandId =
  'flutter-vscode.host-test.jsPromiseRoundTrip';
const hoverReceivedCancellationTokenCommandId =
  'flutter-vscode.host-test.hoverReceivedCancellationToken';
const openFlutterViewCommandId =
  'flutter-vscode.host-test.openFlutterView';
const probeFlutterViewProtocolCommandId =
  'flutter-vscode.host-test.probeFlutterViewProtocol';

async function run() {
  console.log('[host-test] RED/GREEN: activation and Dart command');

  const extension = vscode.extensions.getExtension(extensionId);
  assert.ok(extension, `Expected VS Code to discover ${extensionId}`);
  assert.equal(extension.isActive, false, 'Fixture activated before the test');

  await extension.activate();

  assert.equal(extension.isActive, true, 'Fixture did not activate');
  const result = await vscode.commands.executeCommand(commandId);
  assert.equal(result, 'pong from Dart');

  console.log('[host-test] RED/GREEN: JavaScript promise to Dart future');
  const jsPromiseSource = vscode.commands.registerCommand(
    jsPromiseSourceCommandId,
    async () => 'value from JavaScript Promise',
  );
  try {
    const roundTrip = await vscode.commands.executeCommand(
      jsPromiseRoundTripCommandId,
    );
    assert.equal(
      roundTrip,
      'Dart received: value from JavaScript Promise',
    );
  } finally {
    jsPromiseSource.dispose();
  }

  console.log('[host-test] RED/GREEN: Dart async error');
  await assert.rejects(
    vscode.commands.executeCommand(failAsyncCommandId),
    (error) => {
      assert.match(error.message, /Dart command failed intentionally/);
      assert.match(error.stack, /host\/lib\/extension\.dart:\d+:\d+/);
      assert.doesNotMatch(error.stack, /extension\.dart\.js:\d+:\d+/);
      return true;
    },
  );

  console.log('[host-test] RED/GREEN: Dart synchronous error');
  await assert.rejects(
    vscode.commands.executeCommand(failSyncCommandId),
    (error) => {
      assert.match(error.message, /Dart synchronous failure/);
      assert.match(error.stack, /host\/lib\/extension\.dart:\d+:\d+/);
      assert.doesNotMatch(error.stack, /extension\.dart\.js:\d+:\d+/);
      return true;
    },
  );

  console.log('[host-test] RED/GREEN: Dart hover provider');
  const document = await vscode.workspace.openTextDocument({
    language: 'plaintext',
    content: 'hover target',
  });
  const position = new vscode.Position(0, 2);
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
  assert.equal(
    await vscode.commands.executeCommand(
      hoverReceivedCancellationTokenCommandId,
    ),
    true,
  );

  console.log('[host-test] RED/GREEN: native document identity');
  assert.equal(
    await vscode.commands.executeCommand(identityCommandId),
    true,
  );

  console.log('[host-test] RED/GREEN: Dart event unsubscribe');
  assert.equal(
    await vscode.commands.executeCommand(eventCountCommandId),
    1,
  );
  await vscode.commands.executeCommand(unsubscribeCommandId);
  await vscode.workspace.openTextDocument({
    language: 'plaintext',
    content: 'event after unsubscribe',
  });
  assert.equal(
    await vscode.commands.executeCommand(eventCountCommandId),
    1,
  );

  console.log('[host-test] RED/GREEN: parity layer against the live host');
  const paritySmoke = await vscode.commands.executeCommand(
    'flutter-vscode.host-test.paritySmoke',
  );
  assert.ok(paritySmoke, 'parity smoke command returned nothing');
  assert.equal(paritySmoke.version, vscode.version);
  assert.equal(paritySmoke.viewColumnActive, -1);
  assert.equal(paritySmoke.fileTypeFile, 1);
  assert.equal(paritySmoke.translatedLine, 4);
  assert.equal(paritySmoke.uriFsPath, '/parity/smoke.json');
  assert.equal(paritySmoke.uriToString, 'file:///parity/smoke.json');
  assert.ok(paritySmoke.commandCount > 10, 'getCommands round-trip empty');
  assert.equal(paritySmoke.eventSubscribed, true);
  const families = paritySmoke.families;
  assert.ok(families, 'per-family live report missing');
  for (const family of [
    'authentication', 'chat', 'commands', 'comments', 'debug', 'env',
    'extensions', 'l10n', 'languages', 'lm', 'notebooks', 'scm', 'tasks',
    'tests', 'window', 'workspace',
  ]) {
    assert.equal(
      families[family],
      true,
      `API family not exercised live: ${family}`,
    );
  }
  // cc:default-constructor cc:call-signature
  assert.equal(paritySmoke.eventEmitterRoundTrip, 'parity-event');
  assert.equal(paritySmoke.cancellationFlipped, true);
  // cc:declared-constructor (WorkspaceEdit/Position) cc:optional-member
  assert.equal(paritySmoke.workspaceEditApplied, true);
  // cc:promise-thenable
  assert.equal(paritySmoke.clipboardRoundTrip, 'parity-clip');
  assert.equal(paritySmoke.narrowedPosition, true);
  // cc:stable-typedef cc:type-literal cc:reserved-name cc:overload-set
  assert.equal(paritySmoke.stableLiteralWith, 9);
  // cc:numeric-enum asserted above; cc:rest-parameter via l10n;
  // cc:array via getLanguages; cc:object-literal-factory via providers.
  // cc:tuple — real directory entries from workspace.fs.readDirectory
  assert.equal(paritySmoke.tupleEntryIsFile, true);
  assert.ok(paritySmoke.tupleEntryName.length > 0);
  // cc:intersection — Memento & setKeysForSync through globalState
  assert.equal(paritySmoke.intersectionRoundTrip, 'parity-state');
  // cc:external-setter — QuickPick.value written and read back
  assert.equal(paritySmoke.setterRoundTrip, 'parity-value');
  // cc:index-signature — real WorkspaceConfiguration operator []
  assert.equal(paritySmoke.indexSignatureRead, true);
  // cc:narrowing cc:mixed-union — a real union value VS Code chose
  assert.equal(paritySmoke.tabInputNarrowed, true);
  // cc:function-type — VS Code-invoked callback args + lit$ report
  assert.equal(paritySmoke.progressResult, 'parity-progress');
  const parityDocument = await vscode.workspace.openTextDocument({
    language: 'json',
    content: '{"parity": true}',
  });
  const parityHovers = await vscode.commands.executeCommand(
    'vscode.executeHoverProvider',
    parityDocument.uri,
    new vscode.Position(0, 3),
  );
  // The fixture also registers a json hover provider through the single
  // layer, so both providers answer; the parity-smoke one is identified
  // by its content.
  assert.equal(parityHovers.length, 2, 'parity-registered provider missing');
  assert.equal(
    parityHovers.filter(
      (hover) => hover.contents[0].value === 'Hover from the parity layer',
    ).length,
    1,
    'parity hover content missing',
  );
  await vscode.commands.executeCommand(
    'flutter-vscode.host-test.disposeParityProvider',
  );
  const afterDispose = await vscode.commands.executeCommand(
    'vscode.executeHoverProvider',
    parityDocument.uri,
    new vscode.Position(0, 3),
  );
  assert.equal(
    afterDispose.length,
    1,
    'parity-registered provider survived disposal',
  );
  assert.equal(
    afterDispose.filter(
      (hover) => hover.contents[0].value === 'Hover from the parity layer',
    ).length,
    0,
    'disposal removed the wrong provider',
  );

  console.log('[host-test] RED/GREEN: optional Flutter View protocol v1');
  const viewReport = await vscode.commands.executeCommand(
    openFlutterViewCommandId,
  );
  assert.equal(viewReport.renderedValue, 'hello from Host Dart');
  assert.equal(viewReport.closed, true);
  assert.equal(viewReport.viewPendingRequests, 0);
  assert.equal(viewReport.viewSubscriptions, 0);
  assert.equal(viewReport.hostPendingRequests, 0);
  assert.equal(viewReport.hostSubscriptions, 0);
  assert.equal(viewReport.hostPendingSends, 0);
  assert.equal(viewReport.hostReceivingSubscriptions, 0);
  assert.equal(viewReport.hostObservedRenderCount, 1);

  // The Content Security Policy the framework serves is the only thing
  // standing between injected script in a webview and an extension host that
  // runs the author's Dart. Byte-asserting the emitted template proves the
  // string we meant to send; this asserts the policy the live webview
  // actually received.
  const csp = viewReport.contentSecurityPolicy;
  assert.ok(
    typeof csp === 'string' && csp.length > 0,
    'the Flutter View must report the policy present in its own document',
  );
  assert.match(csp, /default-src 'none'/);
  assert.match(
    csp,
    /script-src [^;]*'nonce-[A-Za-z0-9+/=_-]+'/,
    `script-src must carry a nonce: ${csp}`,
  );
  assert.doesNotMatch(
    csp,
    /script-src [^;]*'unsafe-inline'/,
    `script-src must never allow inline script: ${csp}`,
  );
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
  assert.equal(
    viewReport.hostObservedRenderedContent,
    'hello from Host Dart',
  );

  console.log('[host-test] RED/GREEN: real-webview protocol failures');
  const adversityReport = await vscode.commands.executeCommand(
    probeFlutterViewProtocolCommandId,
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
  assert.equal(adversityReport.hostReceivingSubscriptions, 0);
  assert.equal(adversityReport.hostObservedRenderCount, 1);
  assert.equal(
    adversityReport.hostObservedRenderedContent,
    'Protocol probe completed',
  );

  console.log('[host-test] RED/GREEN: host behavior after view cleanup');
  assert.equal(
    await vscode.commands.executeCommand(commandId),
    'pong from Dart',
  );
  const hoversAfterView = await vscode.commands.executeCommand(
    'vscode.executeHoverProvider',
    document.uri,
    position,
  );
  assert.equal(hoversAfterView.length, 1);
  assert.ok(hoversAfterView[0] instanceof vscode.Hover);
}

module.exports = {run};
