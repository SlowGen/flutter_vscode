const String extensionTemplate = '''
import * as vscode from 'vscode';
import { handleCommand } from './api_controller.handlers';

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

        // Handle messages from the webview
        panel.webview.onDidReceiveMessage(
            message => {
                if (message.command) {
                    handleCommand(message, panel);
                } else {
                    // Forward responses back to the Flutter app
                    panel.webview.postMessage(message);
                }
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
