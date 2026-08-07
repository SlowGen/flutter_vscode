'use strict';

// Out-of-process debugger client for the breakpoint gate. The Extension Host
// pauses wholesale when a breakpoint hits, so the driver inside it cannot
// observe its own pause — this helper connects to the host's inspector port
// from a separate plain-Node process, arms the mapped breakpoints, records
// the pause, and resumes execution. The Chrome DevTools Protocol transport
// is chrome-remote-interface; its entry point arrives in the config file
// because this process runs outside every node_modules directory, so
// run_breakpoint.cjs resolves the path and the driver forwards it here.

const fs = require('node:fs');
const path = require('node:path');

function log(message) {
  console.log(message);
}

function writeJsonAtomically(filePath, value) {
  const temporaryPath = `${filePath}.tmp`;
  fs.writeFileSync(temporaryPath, JSON.stringify(value, null, 2));
  fs.renameSync(temporaryPath, filePath);
}

function delay(milliseconds) {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}

// The inspector port opens while VS Code is still starting up, so the first
// connection attempts can find the port closed or the target list empty.
async function connectWithRetry(cdp, inspectPort) {
  let lastError = null;
  for (let attempt = 0; attempt < 40; attempt += 1) {
    try {
      return await cdp({host: '127.0.0.1', port: inspectPort, local: true});
    } catch (error) {
      lastError = error;
    }
    await delay(500);
  }
  throw new Error(
    `Could not connect to an inspector target on port ${inspectPort}: ` +
      `${lastError}`,
  );
}

async function main() {
  const configPath = process.argv[2];
  if (!configPath) {
    throw new Error('Usage: inspector_helper.cjs <config.json>');
  }
  const config = JSON.parse(fs.readFileSync(configPath, 'utf8'));
  const {
    inspectPort,
    scriptUrlSuffix,
    breakpointLocations,
    armedPath,
    resultPath,
    pauseTimeoutMs,
    cdpClientPath,
  } = config;
  const cdp = require(cdpClientPath);

  const reportFailure = (reason) => {
    if (!fs.existsSync(resultPath)) {
      writeJsonAtomically(resultPath, {paused: false, reason});
    }
  };

  const client = await connectWithRetry(cdp, inspectPort);
  log(`connected to the inspector on port ${inspectPort}`);

  const scriptUrlsById = new Map();
  let resolveScriptFound;
  const scriptFound = new Promise((resolve) => {
    resolveScriptFound = resolve;
  });
  let resolvePaused;
  const paused = new Promise((resolve) => {
    resolvePaused = resolve;
  });
  client.Debugger.scriptParsed((params) => {
    scriptUrlsById.set(params.scriptId, params.url);
    if (
      typeof params.url === 'string' &&
      params.url.endsWith(scriptUrlSuffix)
    ) {
      resolveScriptFound(params.url);
    }
  });
  client.Debugger.paused((params) => {
    resolvePaused(params);
  });

  // Debugger.enable replays scriptParsed for scripts the host already
  // loaded, so the compiled bundle is discoverable even though the fixture
  // activated before this helper connected.
  await client.Debugger.enable();
  const scriptUrl = await Promise.race([
    scriptFound,
    delay(20000).then(() => {
      throw new Error(
        `No parsed script matched *${scriptUrlSuffix} within 20s`,
      );
    }),
  ]);
  log(`found ${scriptUrl}`);

  const breakpoints = [];
  for (const location of breakpointLocations) {
    try {
      const result = await client.Debugger.setBreakpointByUrl({
        url: scriptUrl,
        lineNumber: location.lineNumber,
        columnNumber: location.columnNumber,
      });
      breakpoints.push({
        requested: location,
        breakpointId: result.breakpointId,
        resolvedLocations: result.locations.map((resolved) => ({
          lineNumber: resolved.lineNumber,
          columnNumber: resolved.columnNumber,
        })),
      });
    } catch (error) {
      // V8 rejects a second breakpoint at an already-covered location;
      // one bound breakpoint on the line is all the gate needs.
      log(`setBreakpointByUrl ${location.lineNumber}:` +
        `${location.columnNumber} rejected: ${error.message}`);
    }
  }
  if (breakpoints.length === 0) {
    reportFailure('Every setBreakpointByUrl call was rejected');
    process.exit(1);
  }
  log(`armed ${breakpoints.length} breakpoints`);
  writeJsonAtomically(armedPath, {scriptUrl, breakpoints});

  const pauseEvent = await Promise.race([
    paused,
    delay(pauseTimeoutMs).then(() => null),
  ]);
  if (pauseEvent === null) {
    reportFailure(
      `The Extension Host did not pause within ${pauseTimeoutMs}ms`,
    );
    process.exit(1);
  }

  const topFrame = pauseEvent.callFrames[0];
  const pausedLocation = {
    url:
      scriptUrlsById.get(topFrame.location.scriptId) ?? topFrame.url ?? '',
    lineNumber: topFrame.location.lineNumber,
    columnNumber: topFrame.location.columnNumber,
  };
  log(
    `paused at ${path.basename(pausedLocation.url)}:` +
      `${pausedLocation.lineNumber}:${pausedLocation.columnNumber}`,
  );
  // Resume before reporting: a paused Extension Host freezes the driver
  // that is waiting on the result file.
  await client.Debugger.resume();
  log('resumed the Extension Host');
  writeJsonAtomically(resultPath, {
    paused: true,
    pausedLocation,
    hitBreakpoints: pauseEvent.hitBreakpoints ?? [],
  });
  await client.close();
  process.exit(0);
}

main().catch((error) => {
  console.error(error);
  try {
    const config = JSON.parse(fs.readFileSync(process.argv[2], 'utf8'));
    if (!fs.existsSync(config.resultPath)) {
      writeJsonAtomically(config.resultPath, {
        paused: false,
        reason: `helper crashed: ${error.message}`,
      });
    }
  } catch {
    // The config itself was unreadable; the driver's timeout reports it.
  }
  process.exit(1);
});
