import * as vscode from 'vscode';

export function handleCommand(message: any, panel: vscode.WebviewPanel) {
  switch (message.command) {
    case 'getUserName': {
      vscode.commands.executeCommand('flutter_vscode_example.getUserName').then(result => {
        panel.webview.postMessage({ requestId: message.requestId, result });
      });
      break;
    }

    case 'showInformationMessage': {
      const params = {
        message: message.params.message,
      };
      vscode.commands.executeCommand('flutter_vscode_example.showInformationMessage', params);
      break;
    }

  }
}
