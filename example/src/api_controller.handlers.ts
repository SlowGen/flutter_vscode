import * as vscode from 'vscode';

export function handleCommand(message: any, panel: vscode.WebviewPanel) {
  switch (message.command) {
    case 'showInformationMessage': {
      vscode.commands.executeCommand('flutter-demo.showInformationMessage', message.params[0]);
      break;
    }

    case 'showInputBox': {
      vscode.commands.executeCommand('flutter-demo.showInputBox', message.params[0]).then(result => {
        panel.webview.postMessage({ requestId: message.requestId, result });
      });
      break;
    }

    case 'showErrorMessage': {
      vscode.commands.executeCommand('flutter-demo.showErrorMessage', message.params[0]);
      break;
    }

  }
}
