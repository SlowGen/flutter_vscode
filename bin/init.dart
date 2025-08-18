#!/usr/bin/env dart

import 'dart:io';

const String extensionTemplate = '''
import * as vscode from 'vscode';
import { handleCommand } from '../src/api_controller.handlers';

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
    "compile": "npm run build",
    "build": "tsc -p ./",
    "watch": "tsc -watch -p ./"
  },
  "devDependencies": {
    "@types/vscode": "^1.74.0",
    "typescript": "^4.9.4",
    "@types/node": "^18.0.0",
    "@types/glob": "^8.0.0",
    "@types/mocha": "^10.0.0",
    "eslint": "^8.24.0",
    "glob": "^8.0.0",
    "mocha": "^10.0.0"
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
      "ES2020",
      "dom"
    ],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true,
    "moduleResolution": "node",
    "types": ["node"]
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

const String compileShTemplate = '''
#!/bin/bash
dart run build_runner build --delete-conflicting-outputs
if [ -f web/index.html.temp ]; then
  mv web/index.html.temp web/index.html
fi
flutter build web --no-web-resources-cdn --csp --pwa-strategy none --no-tree-shake-icons
''';

void main(List<String> arguments) async {
  print('Initializing Flutter VS Code extension...');

  final currentDir = Directory.current;

  // Check if this is a Flutter project
  final pubspecFile = File('${currentDir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print(
      'Error: No pubspec.yaml found.',
    );
    exit(1);
  }

  // Create src directory for TypeScript files
  final srcDir = Directory('${currentDir.path}/src');
  if (!srcDir.existsSync()) {
    srcDir.createSync();
  }

  // Create extension.ts
  File('${srcDir.path}/extension.ts').writeAsStringSync(extensionTemplate);
  print('Created: src/extension.ts');

  // Create package.json
  File(
    '${currentDir.path}/package.json',
  ).writeAsStringSync(packageJsonTemplate);
  print('Created: package.json');

  // Create tsconfig.json
  File('${currentDir.path}/tsconfig.json').writeAsStringSync(tsconfigTemplate);
  print('Created: tsconfig.json');

  // Create web directory if it doesn't exist
  final webDir = Directory('${currentDir.path}/web');
  if (!webDir.existsSync()) {
    webDir.createSync();
  }

  // Create web/index.html
  File('${webDir.path}/index.html').writeAsStringSync(webIndexTemplate);
  print('Created: web/index.html');

  // Create scripts directory if it doesn't exist
  final scriptsDir = Directory('${currentDir.path}/scripts');
  if (!scriptsDir.existsSync()) {
    scriptsDir.createSync();
  }

  // Create scripts/compile.sh
  File('${scriptsDir.path}/compile.sh').writeAsStringSync(compileShTemplate);
  if (Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['+x', '${scriptsDir.path}/compile.sh']);
  }
  print('Created: scripts/compile.sh');
  print('Flutter VS Code extension scaffolding complete!');
  print('Next steps:');
  print('1. Run "npm install" to install TypeScript dependencies');
  print(
    '2. Define your VS Code controllers using ',
  );
  print('@VSCodeController and @VSCodeCommand annotations');
  print('3. Run "npm run compile" to build everything');
  print(
    '4. Open VS Code and press F5 to run the extension in development mode',
  );
}
  // TODO(gemini): the initally generated code is missing the .gitignore additions. Init should add node_modules, out and files generated with build_runner
  // TODO(gemini): The initially generated code should contain code on the ts side that is capable of receiving the messages sent from the flutter side
  // TODO(gemini): The vscode_interop should be built into the package and accessible by the user via the package. The user can instantiate the message handler via the package and there should be instructions on how to do so in the readme
  // TODO(gemini): Can we set up the init script to run npm install for the user after the appropriate files have been created?
