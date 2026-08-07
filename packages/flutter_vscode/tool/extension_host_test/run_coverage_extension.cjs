'use strict';

const {runPackagedDriverMain} = require('./packaged_driver.cjs');

runPackagedDriverMain({
  logTag: 'coverage-treemap',
  driverDirName: 'coverage_treemap_driver',
  envPrefix: 'FLUTTER_VSCODE_COVERAGE',
  workspaceProbe: ['coverage', 'lcov.info'],
  workspaceProbeDescription: 'coverage data',
});
