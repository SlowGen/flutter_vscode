'use strict';

const assert = require('node:assert/strict');
const childProcess = require('node:child_process');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const vscode = require('vscode');
const {openSourceMap} = require('./source_map.cjs');

const fixtureExtensionId = 'flutter-vscode-test.host-extension-fixture';
const eventCountCommandId = 'flutter-vscode.host-test.openEventCount';

// The breakpoint target is the fixture's openEventCount command callback:
//
//   final eventCount = (() => _openEventCount.toJS).toJS;
//
// in test/fixtures/host_extension/host/lib/extension.dart. The closure body
// (`_openEventCount.toJS`) executes exactly when the driver runs
// flutter-vscode.host-test.openEventCount — after activation has completed —
// so once the breakpoint is armed, a pause can only come from the command the
// driver itself triggers. The line is located by content (the distinctive
// `(() => _openEventCount.toJS)` expression) rather than by a hardcoded line
// number so the gate survives fixture edits.
const dartLineMarker = '(() => _openEventCount.toJS)';
const dartSourceSuffix = 'host/lib/extension.dart';
const generatedScriptSuffix = 'extension.dart.js';

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

async function awaitJsonFile(filePath, timeoutMs, description, child) {
  const deadline = Date.now() + timeoutMs;
  while (!fs.existsSync(filePath)) {
    if (child && child.exitCode !== null && !fs.existsSync(filePath)) {
      assert.fail(
        `The inspector helper exited with code ${child.exitCode} before ` +
          `producing ${description}`,
      );
    }
    assert.ok(Date.now() < deadline, `Timed out waiting for ${description}`);
    await delay(250);
  }
  return JSON.parse(fs.readFileSync(filePath, 'utf8'));
}

function loadSourceMap() {
  const mapPath =
    process.env.FLUTTER_VSCODE_BREAKPOINT_MAP_PATH ??
    '/workspace/test/fixtures/host_extension/out/extension.dart.js.map';
  assert.ok(
    fs.existsSync(mapPath),
    `The fixture source map does not exist: ${mapPath} — ` +
      'run scripts/build_host_fixture.sh first',
  );
  const map = JSON.parse(fs.readFileSync(mapPath, 'utf8'));
  assert.equal(map.version, 3, 'Expected a Source Map v3 document');
  const sourceMap = openSourceMap(map);
  const dartSources = sourceMap.sources.filter((source) =>
    source.endsWith(dartSourceSuffix),
  );
  assert.equal(
    dartSources.length,
    1,
    `Expected exactly one map source ending with ${dartSourceSuffix}`,
  );
  const [dartSource] = dartSources;
  const dartSourcePath = path.resolve(path.dirname(mapPath), dartSource);
  assert.ok(
    fs.existsSync(dartSourcePath),
    `The mapped Dart source does not exist: ${dartSourcePath}`,
  );
  return {mapPath, sourceMap, dartSource, dartSourcePath};
}

function chooseDartLine(dartSourcePath) {
  const dartLines = fs.readFileSync(dartSourcePath, 'utf8').split('\n');
  const matches = dartLines
    .map((line, index) => ({line, index}))
    .filter((entry) => entry.line.includes(dartLineMarker));
  assert.equal(
    matches.length,
    1,
    `Expected exactly one fixture line containing \`${dartLineMarker}\``,
  );
  return {lineIndex: matches[0].index, lineText: matches[0].line.trim()};
}

async function run() {
  const {mapPath, sourceMap, dartSource, dartSourcePath} = loadSourceMap();
  const {lineIndex, lineText} = chooseDartLine(dartSourcePath);
  const expectedDartLine = lineIndex + 1;
  console.log(
    `[breakpoint-test] target Dart line ${expectedDartLine}: ${lineText}`,
  );

  const candidates = sourceMap.generatedPositionsFor(dartSource, lineIndex);
  assert.ok(
    candidates.length > 0,
    `${mapPath} maps no generated code to Dart line ${expectedDartLine}`,
  );
  console.log(
    `[breakpoint-test] ${candidates.length} generated positions map to the ` +
      'Dart line',
  );

  console.log('[breakpoint-test] activating the fixture extension');
  const extension = vscode.extensions.getExtension(fixtureExtensionId);
  assert.ok(extension, `Expected VS Code to discover ${fixtureExtensionId}`);
  await extension.activate();
  assert.equal(extension.isActive, true, 'Fixture did not activate');

  const inspectPort = Number(
    process.env.FLUTTER_VSCODE_BREAKPOINT_INSPECT_PORT ?? '9339',
  );
  const cdpClientPath = process.env.FLUTTER_VSCODE_BREAKPOINT_CDP_CLIENT_PATH;
  assert.ok(
    cdpClientPath,
    'FLUTTER_VSCODE_BREAKPOINT_CDP_CLIENT_PATH is required — run this ' +
      'driver through run_breakpoint.cjs',
  );
  const helperPath = path.join(__dirname, 'inspector_helper.cjs');
  assert.ok(
    fs.existsSync(helperPath),
    'The inspector helper that arms the breakpoint over the Extension Host ' +
      'inspector is not implemented',
  );

  const workDir = fs.mkdtempSync(
    path.join(os.tmpdir(), 'flutter-vscode-breakpoint-'),
  );
  const configPath = path.join(workDir, 'config.json');
  const armedPath = path.join(workDir, 'armed.json');
  const resultPath = path.join(workDir, 'result.json');
  fs.writeFileSync(
    configPath,
    JSON.stringify({
      inspectPort,
      scriptUrlSuffix: generatedScriptSuffix,
      breakpointLocations: candidates,
      armedPath,
      resultPath,
      pauseTimeoutMs: 45000,
      cdpClientPath,
    }),
  );

  // The helper must be a separate process: when the breakpoint pauses the
  // Extension Host, this driver pauses with it — only an outside debugger
  // client can observe the pause and resume execution.
  console.log('[breakpoint-test] spawning the inspector helper');
  const child = childProcess.spawn(
    process.execPath,
    [helperPath, configPath],
    {
      env: {...process.env, ELECTRON_RUN_AS_NODE: '1'},
      stdio: ['ignore', 'pipe', 'pipe'],
    },
  );
  child.stdout.on('data', (chunk) =>
    process.stdout.write(`[inspector-helper] ${chunk}`),
  );
  child.stderr.on('data', (chunk) =>
    process.stderr.write(`[inspector-helper] ${chunk}`),
  );

  try {
    const armed = await awaitJsonFile(
      armedPath,
      30000,
      'the helper to arm the breakpoints',
      child,
    );
    const boundBreakpoints = armed.breakpoints.filter((breakpoint) =>
      breakpoint.resolvedLocations.some((location) => {
        const original = sourceMap.originalFor(
          location.lineNumber,
          location.columnNumber,
        );
        return (
          original !== null &&
          original.source === dartSource &&
          original.lineNumber === lineIndex
        );
      }),
    );
    assert.ok(
      boundBreakpoints.length > 0,
      'No armed breakpoint resolved to a generated location that maps back ' +
        `to Dart line ${expectedDartLine}`,
    );
    console.log(
      `[breakpoint-test] ${boundBreakpoints.length} breakpoints bound to ` +
        `the Dart line; executing ${eventCountCommandId}`,
    );

    const commandResult = await vscode.commands.executeCommand(
      eventCountCommandId,
    );
    assert.equal(
      typeof commandResult,
      'number',
      'The openEventCount command did not run to completion',
    );

    const result = await awaitJsonFile(
      resultPath,
      60000,
      'the helper pause report',
      child,
    );
    assert.equal(
      result.paused,
      true,
      `The Extension Host never paused on the breakpoint: ` +
        `${result.reason ?? 'no reason reported'}`,
    );
    assert.ok(
      result.pausedLocation.url.endsWith(generatedScriptSuffix),
      `Paused in an unexpected script: ${result.pausedLocation.url}`,
    );
    const pausedOriginal = sourceMap.originalFor(
      result.pausedLocation.lineNumber,
      result.pausedLocation.columnNumber,
    );
    assert.ok(
      pausedOriginal !== null,
      'The paused generated location has no source-map entry',
    );
    assert.equal(
      pausedOriginal.source,
      dartSource,
      'The paused location maps to a source other than the fixture host',
    );
    const matchedDartLine = pausedOriginal.lineNumber + 1;
    assert.equal(
      matchedDartLine,
      expectedDartLine,
      'The paused location does not map back to the chosen Dart line',
    );
    console.log(
      '[breakpoint-test] paused at generated ' +
        `${result.pausedLocation.lineNumber}:` +
        `${result.pausedLocation.columnNumber} -> Dart line ` +
        `${matchedDartLine} (${dartSourceSuffix})`,
    );
    console.log('[breakpoint-test] all assertions passed');
  } finally {
    if (child.exitCode === null) {
      child.kill();
    }
    fs.rmSync(workDir, {recursive: true, force: true});
  }
}

module.exports = {run};
