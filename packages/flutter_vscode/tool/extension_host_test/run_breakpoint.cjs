'use strict';

const fs = require('node:fs');
const {renderStabilityFlags} = require('./electron_flags.cjs');
const path = require('node:path');
const {makeShortProfileRoot} = require('./short_profile_root.cjs');
const {runTests} = require('@vscode/test-electron');

const packageRoot = path.resolve(__dirname, '../..');
const fixtureRoot = path.join(
  packageRoot,
  'test',
  'fixtures',
  'host_extension',
);
const driverRoot = path.join(
  packageRoot,
  'test',
  'fixtures',
  'breakpoint_driver',
);
const fixtureManifest = require(path.join(fixtureRoot, 'package.json'));
const vscodeVersion = fixtureManifest.engines.vscode;
const inspectPort = Number(
  process.env.FLUTTER_VSCODE_BREAKPOINT_INSPECT_PORT ?? '9339',
);
const mapPath =
  process.env.FLUTTER_VSCODE_BREAKPOINT_MAP_PATH ??
  path.join(fixtureRoot, 'out', 'extension.dart.js.map');

// The driver runs inside the pinned Extension Host and its inspector helper
// runs outside every node_modules directory, so neither can resolve the
// harness's dependencies by walking up from its own file. Resolve the entry
// points here — where the harness's node_modules (or the container image's
// NODE_PATH) is reachable — and hand the paths over through the test env.
const traceMappingPath = require.resolve('@jridgewell/trace-mapping');
const cdpClientPath = require.resolve('chrome-remote-interface');

async function main() {
  if (!fs.existsSync(mapPath)) {
    throw new Error(
      `Fixture source map does not exist: ${mapPath} — run ` +
        'scripts/build_host_fixture.sh first',
    );
  }
  console.log(
    `[breakpoint-test] launching VS Code ${vscodeVersion} with ` +
      `--inspect-extensions=${inspectPort}`,
  );
  const profileRoot = makeShortProfileRoot('fv-bp-');
  try {
    // The fixture and the driver both load as development extensions: the
    // fixture provides the compiled Dart host under test; the driver arms a
    // breakpoint through the Extension Host inspector and triggers the
    // mapped Dart line.
    await runTests({
      version: vscodeVersion,
      cachePath:
        process.env.VSCODE_TEST_CACHE_PATH ??
        path.join(__dirname, '.vscode-test'),
      extensionDevelopmentPath: [fixtureRoot, driverRoot],
      extensionTestsPath: path.join(driverRoot, 'test', 'run.cjs'),
      extensionTestsEnv: {
        FLUTTER_VSCODE_BREAKPOINT_INSPECT_PORT: String(inspectPort),
        FLUTTER_VSCODE_BREAKPOINT_MAP_PATH: mapPath,
        FLUTTER_VSCODE_BREAKPOINT_TRACE_MAPPING_PATH: traceMappingPath,
        FLUTTER_VSCODE_BREAKPOINT_CDP_CLIENT_PATH: cdpClientPath,
      },
      launchArgs: [
        '--disable-extensions',
        `--user-data-dir=${path.join(profileRoot, 'user-data')}`,
        `--inspect-extensions=${inspectPort}`,
        ...renderStabilityFlags,
      ],
    });
  } finally {
    fs.rmSync(profileRoot, {recursive: true, force: true});
  }
  console.log(
    '[breakpoint-test] breakpoint bound through the source map and paused ' +
      'on the Dart line',
  );
}

main().catch((error) => {
  console.error('[breakpoint-test] failed');
  console.error(error);
  process.exitCode = 1;
});
