'use strict';

const fs = require('node:fs');
const path = require('node:path');
const {
  downloadAndUnzipVSCode,
  runTests,
} = require('@vscode/test-electron');
const {installVsix} = require('./packaged_driver.cjs');
const {renderStabilityFlags} = require('./electron_flags.cjs');
const {makeShortProfileRoot} = require('./short_profile_root.cjs');

const packageRoot = path.resolve(__dirname, '../..');
const driverRoot = path.join(
  packageRoot,
  'test',
  'fixtures',
  'packaged_test_driver',
);
const packagedProject = process.env.FLUTTER_VSCODE_PACKAGED_PROJECT;
if (!packagedProject) {
  throw new Error('FLUTTER_VSCODE_PACKAGED_PROJECT is required');
}
const manifest = require(path.join(packagedProject, 'package.json'));
const vscodeVersion = manifest.engines.vscode;
const vsixPath = path.join(
  packagedProject,
  'build',
  `${manifest.name}-${manifest.version}.vsix`,
);
const commands = manifest.contributes?.commands;
if (!Array.isArray(commands) || typeof commands[0]?.command !== 'string') {
  throw new Error('Scaffolded package.json has no contributed command');
}
const commandResult = process.env.FLUTTER_VSCODE_PACKAGED_COMMAND_RESULT;
if (!commandResult) {
  throw new Error('FLUTTER_VSCODE_PACKAGED_COMMAND_RESULT is required');
}
const viewCommand = commands.find(
  ({command}) => command.endsWith('.openFlutterView'),
);
if (
  process.env.FLUTTER_VSCODE_PACKAGED_REQUIRE_VIEW === '1' &&
  typeof viewCommand?.command !== 'string'
) {
  throw new Error('Packaged fixture has no contributed Flutter View command');
}


async function main() {
  if (!fs.existsSync(vsixPath)) {
    throw new Error(`Packaged fixture does not exist: ${vsixPath}`);
  }

  const profileRoot = makeShortProfileRoot('fv-pkg-');
  const extensionsDir = path.join(profileRoot, 'extensions');
  const userDataDir = path.join(profileRoot, 'user-data');
  fs.mkdirSync(extensionsDir, {recursive: true});
  fs.mkdirSync(path.join(userDataDir, 'User'), {recursive: true});
  fs.writeFileSync(
    path.join(userDataDir, 'User', 'settings.json'),
    JSON.stringify({'workbench.startupEditor': 'none'}),
  );

  try {
    console.log(
      `[packaged-host-test] resolving fresh VS Code test runtime ${vscodeVersion}`,
    );
    const vscodeExecutablePath = await downloadAndUnzipVSCode({
      version: vscodeVersion,
      cachePath:
        process.env.VSCODE_TEST_CACHE_PATH ??
        path.join(__dirname, '.vscode-test'),
    });

    console.log(`[packaged-host-test] installing ${vsixPath}`);
    installVsix(vsixPath, vscodeExecutablePath, extensionsDir, userDataDir);

    console.log('[packaged-host-test] launching separate development driver');
    await runTests({
      vscodeExecutablePath,
      extensionDevelopmentPath: driverRoot,
      extensionTestsPath: path.join(driverRoot, 'test', 'run.cjs'),
      extensionTestsEnv: {
        FLUTTER_VSCODE_PACKAGED_EXTENSIONS_DIR: extensionsDir,
        FLUTTER_VSCODE_PACKAGED_EXTENSION_ID:
          `${manifest.publisher}.${manifest.name}`,
        FLUTTER_VSCODE_PACKAGED_COMMAND_ID: commands[0].command,
        FLUTTER_VSCODE_PACKAGED_COMMAND_RESULT: commandResult,
        FLUTTER_VSCODE_PACKAGED_VIEW_COMMAND_ID: viewCommand?.command ?? '',
      },
      launchArgs: [
        `--extensions-dir=${extensionsDir}`,
        `--user-data-dir=${userDataDir}`,
        // Surfaces webview renderer console output (CSP violations,
        // resource failures, JS errors) in the harness log.
        '--enable-logging',
        ...renderStabilityFlags,
      ],
    });
  } finally {
    fs.rmSync(profileRoot, {recursive: true, force: true});
  }
}

main().catch((error) => {
  console.error('[packaged-host-test] failed');
  console.error(error);
  process.exitCode = 1;
});
