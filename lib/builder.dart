// This file is the entry point for the build_runner.
// It configures the code generator.

import 'package:build/build.dart';
import 'package:flutter_vscode/src/vscode_extension_generator.dart';
import 'package:flutter_vscode/src/vscode_generator.dart';
import 'package:flutter_vscode/src/vscode_interop_generator.dart';
import 'package:flutter_vscode/src/vscode_package_json_generator.dart';
import 'package:flutter_vscode/src/vscode_ts_generator.dart';
import 'package:source_gen/source_gen.dart';

/// Configures the build process for the VS Code Dart generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VSCodeGenerator] to the user's source code.
Builder vscodeDartGenerator(BuilderOptions options) {
  return SharedPartBuilder([VSCodeGenerator()], 'vscode');
}

/// Configures the build process for the VS Code TypeScript generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VSCodeTsGenerator] to the user's source code.
Builder vscodeTsGenerator(BuilderOptions options) {
  return VSCodeTsGenerator();
}

/// Configures the build process for the VS Code Extension generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VSCodeExtensionGenerator] to the user's source code.
Builder vscodeExtensionGenerator(BuilderOptions options) {
  return VSCodeExtensionGenerator();
}

/// Configures the build process for the package.json generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VSCodePackageJsonGenerator] to the user's source code.
Builder vscodePackageJsonGenerator(BuilderOptions options) {
  return VSCodePackageJsonGenerator();
}

/// Configures the build process for the VS Code interop generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VSCodeInteropGenerator] to the user's source code.
Builder vscodeInteropGenerator(BuilderOptions options) {
  return VSCodeInteropGenerator();
}
