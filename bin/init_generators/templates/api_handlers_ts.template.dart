const String apiControllerHandlersTemplate = r'''
import * as vscode from 'vscode';

export function handleCommand(message: { command: string, [key: string]: any }, panel: vscode.WebviewPanel) {
    const { command } = message;

    switch (command) {
        // Add your command handlers here
        default:
            vscode.window.showInformationMessage(`Unknown command: ${command}`);
    }
}
''';
