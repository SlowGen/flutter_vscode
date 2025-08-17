// ignore_for_file: avoid_print - This is a CLI tool that needs console output

import 'dart:io';
import 'package:path/path.dart' as p;

void main() {
  final currentDirectory = Directory.current.path;
  print('Generating VSCode extension files in: $currentDirectory');

  try {
    // Create all necessary directories and files
    _createDirectories(currentDirectory);
    _createLaunchConfig(currentDirectory);
    _createCompileScript(currentDirectory);
    _createExtensionFile(currentDirectory);
    _createPackageJson(currentDirectory);
    _createTsConfig(currentDirectory);
    _updateWebFolder(currentDirectory);
    _updateGitignore(currentDirectory);

    print('');
    print('✅ VSCode extension files generated successfully!');
    print('Next steps:');
    print('1. Run: npm install');
    print('2. Press F5 in VS Code to run the extension');
  } on Exception catch (e, stackTrace) {
    print('');
    print('❌ Error generating VSCode extension files:');
    print('Error: $e');
    print('');
    print('Stack trace:');
    print(stackTrace);
    print('');
    print('Common solutions:');
    print('• Check you have write permissions in the current directory');
    print('• Ensure you have sufficient disk space');
    print('• Try running from a different directory');
    print('• Close any files that might be open in editors');
    exit(1);
  }
}

void _createDirectories(String currentDirectory) {
  Directory(p.join(currentDirectory, '.vscode')).createSync(recursive: true);
  Directory(p.join(currentDirectory, 'out')).createSync(recursive: true);
  Directory(p.join(currentDirectory, 'scripts')).createSync(recursive: true);
  Directory(p.join(currentDirectory, 'src')).createSync(recursive: true);
}

void _createLaunchConfig(String currentDirectory) {
  File(
    p.join(currentDirectory, '.vscode', 'launch.json'),
  ).writeAsStringSync(_getLaunchJson());
}

void _createCompileScript(String currentDirectory) {
  final file = File(p.join(currentDirectory, 'scripts', 'compile.sh'))
    ..writeAsStringSync(_getCompileScript());

  if (Platform.isLinux || Platform.isMacOS) {
    Process.runSync('chmod', ['+x', file.path]);
  }
}

void _createExtensionFile(String currentDirectory) {
  final file = File(p.join(currentDirectory, 'src', 'extension.ts'));

  // Try to copy from template if it exists
  final templatePath = p.join(
    Directory.current.path,
    'tool',
    'extension.ts.template',
  );
  if (File(templatePath).existsSync()) {
    final content = File(templatePath).readAsStringSync();
    file.writeAsStringSync(content);
  } else {
    file.writeAsStringSync(_getExtensionTs());
  }
}

void _createPackageJson(String currentDirectory) {
  File(
    p.join(currentDirectory, 'package.json'),
  ).writeAsStringSync(_getPackageJson());
}

void _createTsConfig(String currentDirectory) {
  File(
    p.join(currentDirectory, 'tsconfig.json'),
  ).writeAsStringSync(_getTsConfig());
}

void _updateWebFolder(String currentDirectory) {
  // Modify index.html for VSCode webview compatibility
  File(
    p.join(currentDirectory, 'web', 'index.html'),
  ).writeAsStringSync(_getWebIndexHtml());

  // Create flutter_bootstrap.js
  File(
    p.join(currentDirectory, 'web', 'flutter_bootstrap.js'),
  ).writeAsStringSync(_getFlutterBootstrapJs());
}

void _updateGitignore(String currentDirectory) {
  final file = File(p.join(currentDirectory, '.gitignore'));
  final entries = [
    '# VSCode extension specific',
    'node_modules/',
    'out/',
    '*.vsix',
    '',
    '# Flutter build output',
    'build/',
    '',
    '# Dart/Flutter generated files',
    '*.g.dart',
    '*.g.part',
    '',
    '# TypeScript generated files',
    '*.handlers.ts',
    '',
    '# IDE files',
    '.vscode/settings.json',
  ];

  if (file.existsSync()) {
    final existing = file.readAsStringSync();
    final newEntries = <String>[];

    for (final entry in entries) {
      if (entry.isEmpty || entry.startsWith('#')) continue;
      if (!existing.contains(entry)) {
        newEntries.add(entry);
      }
    }

    if (newEntries.isNotEmpty) {
      file.writeAsStringSync(
        '\n# VSCode extension entries\n${newEntries.join('\n')}\n',
        mode: FileMode.append,
      );
    }
  } else {
    file.writeAsStringSync('${entries.join('\n')}\n');
  }
}

String _getLaunchJson() {
  return r'''
// A launch configuration that compiles the extension and then opens it inside a new window
// Use IntelliSense to learn about possible attributes.
// Hover to view descriptions of existing attributes.
// For more information, visit: https://go.microsoft.com/fwlink/?linkid=830387
{
	"version": "0.2.0",
	"configurations": [
		{
			"name": "Run Extension",
			"type": "extensionHost",
			"request": "launch",
			"runtimeExecutable": "${execPath}",
			"args": [
				"--extensionDevelopmentPath=${workspaceRoot}",
				"--disable-extensions",
				],
			"outFiles": ["${workspaceFolder}/out/**/*.js"],
			"preLaunchTask": "npm: vscode:prepublish"
		}
	]
}
''';
}

String _getCompileScript() {
  return '''
#!/bin/bash

# Generate Dart code using build_runner
dart run build_runner build --delete-conflicting-outputs

# Compile TypeScript
tsc -p ./

# Build Flutter web
flutter build web --no-web-resources-cdn --csp --pwa-strategy none --no-tree-shake-icons
''';
}

String _getExtensionTs() {
  return '''
import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

// This extension is a starting template for a Flutter VSCode extension.
// Extension configuration and commands will be generated by build_runner.

export function activate(context: vscode.ExtensionContext) {
    console.log('Flutter VSCode extension is now active!');

    // Extension initialization code will be generated here by build_runner
    // based on your Flutter app configuration.

}

export function deactivate() {
    console.log('Flutter VSCode extension deactivated.');
}
''';
}

String _getPackageJson() {
  return '''
{
  "name": "your_extension_name",
  "displayName": "Your Extension Display Name",
  "description": "Describe your extension",
  "version": "0.0.1",
  "publisher": "your_publisher",
  "engines": {
    "vscode": "^1.75.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [],
  "main": "./out/extension.js",
  "files": [
    "out",
    "build/web"
  ],
  "contributes": {
  },
  "scripts": {
    "vscode:prepublish": "npm run compile",
    "compile": "scripts/compile.sh",
  },
  "devDependencies": {
    "@eslint/js": "^9.13.0",
    "@stylistic/eslint-plugin": "^2.9.0",
    "@types/node": "^24.0.14",
    "@types/vscode": "^1.73.0",
    "@vscode/wasm-component-model": "^1.0.2",
    "eslint": "^9.13.0",
    "typescript": "^5.8.2",
    "typescript-eslint": "^8.26.0"
  }
}''';
}

String _getTsConfig() {
  return '''
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "es2020",
    "outDir": "out",
    "lib": ["es2020"],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true,
    "moduleResolution": "node",
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true
  },
  "exclude": ["node_modules", "out", "lib", "build", "web"]
}''';
}

String _getWebIndexHtml() {
  return '''
\u003c!DOCTYPE html>
\u003chtml>
\u003chead>
  \u003cbase href="\$FLUTTER_BASE_HREF">

  \u003cmeta charset="UTF-8">
  \u003cmeta content="IE=Edge" http-equiv="X-UA-Compatible">
  \u003cmeta name="description" content="A new Flutter project.">

  \u003cscript>
    // Disable history API for webview compatibility
    (function() {
      function initializeHistoryAPI() {
        if (typeof window !== 'undefined' \u0026\u0026 window.history) {
          window.history.replaceState = function() {
            console.log('History replaceState blocked for webview compatibility');
          };
          window.history.pushState = function() {
            console.log('History pushState blocked for webview compatibility');
          };
        } else {
          // Retry after a short delay if window is not available yet
          setTimeout(initializeHistoryAPI, 10);
        }
      }

      // Initialize immediately or when DOM is ready
      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initializeHistoryAPI);
      } else {
        initializeHistoryAPI();
      }
    })();
  \u003c/script>

  \u003ctitle>Your Flutter VSCode Extension\u003c/title>
  \u003clink rel="manifest" href="manifest.json">
\u003c/head>
\u003cbody>
  \u003cscript src="main.dart.js" defer>\u003c/script>
\u003c/body>
\u003c/html>
''';
}

String _getFlutterBootstrapJs() {
  return '''
{{flutter_js}}
{{flutter_build_config}}

// the below loader ensures that the local copy of canvasKit is used
// and there is no attempt to download it. Attempting to download it
// will cause the extension to fail as remote resources are blocked

_flutter.loader.load({
    config: {
        canvasKitBaseUrl: "canvaskit/"
    },
});
''';
}
