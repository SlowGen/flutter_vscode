'use strict';

const {runPackagedDriverMain} = require('./packaged_driver.cjs');

runPackagedDriverMain({
  logTag: 'pubspec-lens',
  driverDirName: 'pubspec_lens_driver',
  envPrefix: 'FLUTTER_VSCODE_PUBSPEC_LENS',
  workspaceProbe: ['pubspec.yaml'],
  workspaceProbeDescription: 'pubspec.yaml',
});
