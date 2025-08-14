#!/usr/bin/env dart

import 'dart:io';

const String extensionTemplate = '''
import * as vscode from 'vscode';
import { handleCommand } from '../lib/api_controller.handlers';

export function activate(context: vscode.ExtensionContext) {
    const disposable = vscode.commands.registerCommand('flutter-vscode.openWebview', () => {
        const panel = vscode.window.createWebviewPanel(
            'flutterVSCode',
            'Flutter VS Code Extension',
            vscode.ViewColumn.One,
            {
                enableScripts: true,
                retainContextWhenHidden: true,
            }
        );

        // Load the Flutter web app
        panel.webview.html = getWebviewContent();

        // Handle messages from the webview using generated handlers
        panel.webview.onDidReceiveMessage(
            message => {
                handleCommand(message, panel);
            },
            undefined,
            context.subscriptions
        );
    });

    context.subscriptions.push(disposable);
}

function getWebviewContent(): string {
    return `<!DOCTYPE html>
<html>
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Flutter VS Code Extension</title>
</head>
<body>
    <div id="output"></div>
    <script src="main.dart.js"></script>
    <script>
        // Bridge for communication with VS Code
        const vscode = acquireVsCodeApi();
        
        window.addEventListener('message', event => {
            const message = event.data;
            if (message && message.requestId) {
                // Forward response back to Flutter
                window.postMessage(message, '*');
            }
        });
        
        // Override postMessage to send to VS Code
        const originalPostMessage = window.postMessage;
        window.postMessage = function(message, origin) {
            if (typeof message === 'object' && message.command) {
                vscode.postMessage(message);
            } else {
                originalPostMessage.call(window, message, origin);
            }
        };
    </script>
</body>
</html>`;
}

export function deactivate() {}
''';

const String packageJsonTemplate = '''
{
  "name": "flutter-vscode-extension",
  "displayName": "Flutter VS Code Extension",
  "description": "A VS Code extension built with Flutter",
  "version": "0.0.1",
  "engines": {
    "vscode": "^1.74.0"
  },
  "categories": [
    "Other"
  ],
  "activationEvents": [],
  "main": "./out/extension.js",
  "contributes": {
    "commands": [
      {
        "command": "flutter-vscode.openWebview",
        "title": "Open Flutter Webview"
      }
    ]
  },
  "scripts": {
    "vscode:prepublish": "npm run compile",
    "compile": "tsc -p ./",
    "watch": "tsc -watch -p ./"
  },
  "dependencies": {
    "@types/vscode": "^1.74.0"
  },
  "devDependencies": {
    "typescript": "^4.9.4"
  }
}
''';

const String tsconfigTemplate = '''
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2020",
    "outDir": "out",
    "lib": [
      "ES2020"
    ],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true
  }
}
''';

const String webIndexTemplate = '''
<!DOCTYPE html>
<html>
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Flutter VS Code Extension</title>
  <script>
    // Bridge for communication with VS Code
    const vscode = acquireVsCodeApi();
    
    window.addEventListener('message', event => {
      const message = event.data;
      if (message && message.requestId) {
        // Forward response back to Flutter
        window.postMessage(message, '*');
      }
    });
    
    // Override postMessage to send to VS Code
    const originalPostMessage = window.postMessage;
    window.postMessage = function(message, origin) {
      if (typeof message === 'object' && message.command) {
        vscode.postMessage(message);
      } else {
        originalPostMessage.call(window, message, origin);
      }
    };
  </script>
</head>
<body>
  <div id="output"></div>
  <script src="main.dart.js"></script>
</body>
</html>
''';

void main(List<String> arguments) async {
  print('Initializing Flutter VS Code extension...');
  
  final currentDir = Directory.current;
  
  // Check if this is a Flutter project
  final pubspecFile = File('${currentDir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: This does not appear to be a Flutter project. No pubspec.yaml found.');
    exit(1);
  }
  
  // Create src directory for TypeScript files
  final srcDir = Directory('${currentDir.path}/src');
  if (!srcDir.existsSync()) {
    srcDir.createSync();
  }
  
  // Create extension.ts
  final extensionFile = File('${srcDir.path}/extension.ts');
  extensionFile.writeAsStringSync(extensionTemplate);
  print('Created: src/extension.ts');
  
  // Create package.json
  final packageJsonFile = File('${currentDir.path}/package.json');
  packageJsonFile.writeAsStringSync(packageJsonTemplate);
  print('Created: package.json');
  
  // Create tsconfig.json
  final tsconfigFile = File('${currentDir.path}/tsconfig.json');
  tsconfigFile.writeAsStringSync(tsconfigTemplate);
  print('Created: tsconfig.json');
  
  // Create web directory if it doesn't exist
  final webDir = Directory('${currentDir.path}/web');
  if (!webDir.existsSync()) {
    webDir.createSync();
  }
  
  // Create web/index.html
  final indexFile = File('${webDir.path}/index.html');
  indexFile.writeAsStringSync(webIndexTemplate);
  print('Created: web/index.html');
  
  print(r'\nFlutter VS Code extension scaffolding complete!');
  print(r'\nNext steps:');
  print('1. Define your VS Code controllers using @VSCodeController and @VSCodeCommand annotations');
  print('2. Run "dart run build_runner build" to generate the Dart and TypeScript handlers');
  print('3. Copy the generated *.handlers.ts files from lib/ to src/ directory');
  print('4. Run "npm install" to install TypeScript dependencies');
  print('5. Run "flutter build web" to build your Flutter app');
  print('6. Run "npm run compile" to compile TypeScript');
  print('7. Open VS Code and press F5 to run the extension in development mode');
}
