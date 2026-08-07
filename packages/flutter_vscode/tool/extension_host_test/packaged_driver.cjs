'use strict';

// Shared machinery for driving a packaged VSIX in a real VS Code: the two
// example-extension gates were byte-identical copies apart from a driver
// name, two env vars, and a workspace probe, and every harness fix had to
// land twice. Each entry file is now a small config over this module.

const childProcess = require('node:child_process');
const fs = require('node:fs');
const path = require('node:path');
const {
  downloadAndUnzipVSCode,
  resolveCliArgsFromVSCodeExecutablePath,
  runTests,
} = require('@vscode/test-electron');

const {renderStabilityFlags} = require('./electron_flags.cjs');
const {makeShortProfileRoot} = require('./short_profile_root.cjs');

const packageRoot = path.resolve(__dirname, '../..');

function installVsix(vsixPath, vscodeExecutablePath, extensionsDir, userDataDir) {
  const [cliPath, ...cliArguments] =
    resolveCliArgsFromVSCodeExecutablePath(vscodeExecutablePath, {
      reuseMachineInstall: true,
    });
  const result = childProcess.spawnSync(
    cliPath,
    [
      ...cliArguments,
      '--install-extension',
      vsixPath,
      '--force',
      `--extensions-dir=${extensionsDir}`,
      `--user-data-dir=${userDataDir}`,
    ],
    {
      encoding: 'utf8',
      stdio: 'pipe',
    },
  );

  if (result.error) {
    throw result.error;
  }
  if (result.status !== 0) {
    throw new Error(
      [
        `VS Code CLI failed to install ${vsixPath}.`,
        result.stdout,
        result.stderr,
      ].join('\n'),
    );
  }
  process.stdout.write(result.stdout);
  process.stderr.write(result.stderr);
}

async function runPackagedDriver({
  logTag,
  driverDirName,
  envPrefix,
  workspaceProbe,
  workspaceProbeDescription,
}) {
  const driverRoot = path.join(packageRoot, 'test', 'fixtures', driverDirName);
  const extensionProject = process.env[`${envPrefix}_PROJECT`];
  if (!extensionProject) {
    throw new Error(`${envPrefix}_PROJECT is required`);
  }
  const workspacePath = process.env[`${envPrefix}_WORKSPACE`];
  if (!workspacePath) {
    throw new Error(`${envPrefix}_WORKSPACE is required`);
  }
  const manifest = require(path.join(extensionProject, 'package.json'));
  const vscodeVersion = manifest.engines.vscode;
  const vsixPath = path.join(
    extensionProject,
    'build',
    `${manifest.name}-${manifest.version}.vsix`,
  );

  if (!fs.existsSync(vsixPath)) {
    throw new Error(`Packaged extension does not exist: ${vsixPath}`);
  }
  if (!fs.existsSync(path.join(workspacePath, ...workspaceProbe))) {
    throw new Error(
      `Workspace has no ${workspaceProbeDescription}: ${workspacePath}`,
    );
  }

  const profileRoot = makeShortProfileRoot(`fv-${logTag}-`);
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
      `[${logTag}-test] resolving VS Code test runtime ${vscodeVersion}`,
    );
    const vscodeExecutablePath = await downloadAndUnzipVSCode({
      version: vscodeVersion,
      cachePath:
        process.env.VSCODE_TEST_CACHE_PATH ??
        path.join(__dirname, '.vscode-test'),
    });

    console.log(`[${logTag}-test] installing ${vsixPath}`);
    installVsix(vsixPath, vscodeExecutablePath, extensionsDir, userDataDir);

    console.log(`[${logTag}-test] launching the test workspace`);
    await runTests({
      vscodeExecutablePath,
      extensionDevelopmentPath: driverRoot,
      extensionTestsPath: path.join(driverRoot, 'test', 'run.cjs'),
      launchArgs: [
        workspacePath,
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

function runPackagedDriverMain(config) {
  runPackagedDriver(config).catch((error) => {
    console.error(`[${config.logTag}-test] failed`);
    console.error(error);
    process.exitCode = 1;
  });
}

module.exports = {
  installVsix,
  runPackagedDriverMain,
};
