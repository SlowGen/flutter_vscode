// This file is the entry point for the build_runner.
// It configures the code generator.

import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Configures the build process for the VS Code Extension generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VscodeExtensionGenerator] to the user's source code.
Builder vscodeExtensionGenerator(BuilderOptions options) {
  return SharedPartBuilder([VscodeExtensionGenerator()], 'vscode');
}

/// Configures the build process for the VS Code TypeScript generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [VSCodeTsGenerator] to the user's source code.
Builder vscodeTsGenerator(BuilderOptions options) {
  return VSCodeTsGenerator();
}

/// Configures the build process for the webview builder.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [WebviewBuilder] to the user's source code.
Builder webviewBuilder(BuilderOptions options) {
  return WebviewBuilder();
}

/// Configures the build process for the package.json generator.
///
/// This function is referenced in `build.yaml` and tells `build_runner`
/// how to apply the [PackageJsonBuilder] to the user's source code.
Builder packageJsonBuilder(BuilderOptions options) {
  return PackageJsonBuilder();
}
