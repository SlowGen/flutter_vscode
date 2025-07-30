import * as vscode from 'vscode';

export function handleCommand(message: any, panel: vscode.WebviewPanel) {
  switch (message.command) {
    case 'showInformationMessage': {
      vscode.window.showInformationMessage(message.params[0]);
      break;
    }

    case 'showInputBox': {
      vscode.window.showInputBox(message.params[0]).then(result => {
        panel.webview.postMessage({ requestId: message.requestId, result });
      });
      break;
    }

    case 'showErrorMessage': {
      vscode.window.showErrorMessage(message.params[0]);
      break;
    }

  }
}
