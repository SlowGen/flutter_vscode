import * as vscode from 'vscode';

// Generated TypeScript handlers for VS Code commands

export function handleCommand(message: any, panel: vscode.WebviewPanel): void {
  switch (message.command) {
    case 'openFile': {
      const {
        path,
      } = message.params || {};
      vscode.commands.executeCommand('vscode.open', path);
      break;
    }

    case 'sayHello': {
      const {
        name,
      } = message.params || {};
      vscode.commands.executeCommand('my-extension.sayHello', name)
        .then(result => {
          panel.webview.postMessage({
            requestId: message.requestId,
            result
          });
        }, error => {
          panel.webview.postMessage({
            requestId: message.requestId,
            error: error.message || String(error)
          });
        });
      break;
    }

    case 'getUserName': {
      vscode.commands.executeCommand('getUserName')
        .then(result => {
          panel.webview.postMessage({
            requestId: message.requestId,
            result
          });
        }, error => {
          panel.webview.postMessage({
            requestId: message.requestId,
            error: error.message || String(error)
          });
        });
      break;
    }

    case 'showInformationMessage': {
      const {
        message: messageParam,
      } = message.params || {};
      vscode.commands.executeCommand('my-extension.showInfo', messageParam);
      break;
    }

    default:
      console.warn(`Unknown command: ${message.command}`);
      break;
  }
}

// Register custom commands
export function registerCommands(context: vscode.ExtensionContext): void {
  const disposables = [
    vscode.commands.registerCommand('my-extension.sayHello', (...args) => {
      // Custom command implementation would go here
      // This is a placeholder that can be overridden
      return Promise.resolve();
    }),
    vscode.commands.registerCommand('getUserName', (...args) => {
      // Custom command implementation would go here
      // This is a placeholder that can be overridden
      return Promise.resolve();
    }),
    vscode.commands.registerCommand('my-extension.showInfo', (...args) => {
      // Custom command implementation would go here
      // This is a placeholder that can be overridden
      return Promise.resolve();
    }),
  ];
  context.subscriptions.push(...disposables);
}
