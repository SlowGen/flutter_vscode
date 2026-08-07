const fs = require('node:fs');
const path = require('node:path');
const {runTests} = require('@vscode/test-electron');
const {
  contractArtifactPath,
  repositoryRoot,
  verifyHostContractSourceFiles,
} = require('./host_contract.cjs');
const {renderStabilityFlags} = require('./electron_flags.cjs');

const packageRoot = path.resolve(__dirname, '../..');
const fixtureRoot = path.join(
  packageRoot,
  'test',
  'fixtures',
  'host_extension',
);
const fixtureManifest = require(path.join(fixtureRoot, 'package.json'));
const vscodeVersion = fixtureManifest.engines.vscode;
const contractId = 'checkpoint4ExtensionHost';
const contractPath = contractArtifactPath;

async function main() {
  const counts = verifyHostContractSourceFiles({
    contractId,
    contract: JSON.parse(fs.readFileSync(contractPath, 'utf8')),
    repositoryRoot,
  });
  console.log(
    `[host-test] verified ${counts.sourceCount} Host Contract source receipts`,
  );
  console.log(
    `[host-test] launching fresh VS Code test runtime ${vscodeVersion}`,
  );
  await runTests({
    version: vscodeVersion,
    cachePath:
      process.env.VSCODE_TEST_CACHE_PATH ??
      path.join(__dirname, '.vscode-test'),
    extensionDevelopmentPath: fixtureRoot,
    extensionTestsPath: path.join(fixtureRoot, 'test', 'run.cjs'),
    // --enable-logging surfaces webview renderer console output (CSP
    // violations, resource failures, JS errors); without it a view that
    // fails to boot times out silently.
    launchArgs: [
      '--disable-extensions',
      '--enable-logging',
      ...renderStabilityFlags,
    ],
  });

  console.log('[host-test] launching activation-failure host');
  await runTests({
    version: vscodeVersion,
    cachePath:
      process.env.VSCODE_TEST_CACHE_PATH ??
      path.join(__dirname, '.vscode-test'),
    extensionDevelopmentPath: fixtureRoot,
    extensionTestsPath: path.join(
      fixtureRoot,
      'test',
      'activation_failure.cjs',
    ),
    extensionTestsEnv: {
      FLUTTER_VSCODE_HOST_TEST_FAIL_ACTIVATION: '1',
    },
    launchArgs: ['--disable-extensions', ...renderStabilityFlags],
  });
}

main().catch((error) => {
  console.error('[host-test] failed');
  console.error(error);
  process.exitCode = 1;
});
