import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

export function activate(context: vscode.ExtensionContext) {
    console.log('Congratulations, your extension "ext-poc" is now active!');

    const provider = new FlutterWebviewProvider(context.extensionUri);

    // Register the provider for the webview view.
    // Use webview activation.
	context.subscriptions.push(
		vscode.window.registerWebviewViewProvider(FlutterWebviewProvider.viewType, provider)
	);

    // Add the status bar item to subscriptions
    context.subscriptions.push(provider.statusBarItem);

    // Register the commands defined in package.json
    context.subscriptions.push(vscode.commands.registerCommand('extPoc.addOne', () => {
        // Send a message to the webview when the command is executed
        if (provider.view) {
            provider.view.webview.postMessage({ type: 'add' });
        }
    }));

    context.subscriptions.push(vscode.commands.registerCommand('extPoc.reset', () => {
        if (provider.view) {
            // The Flutter app will send a message back for this command.
            provider.view.webview.postMessage({ type: 'reset' });
        }
    }));
}

export function deactivate() {}

class FlutterWebviewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = 'extPoc.counter';

    public view?: vscode.WebviewView;
    private _statusBarItem?: vscode.StatusBarItem;

    constructor(
        private readonly _extensionUri: vscode.Uri,
    ) {
        // Status bar item will be created when needed
    }

    public get statusBarItem(): vscode.StatusBarItem {
        if (!this._statusBarItem) {
            this._createStatusBarItem();
        }
        return this._statusBarItem!;
    }

    private _createStatusBarItem(): void {
        this._statusBarItem = vscode.window.createStatusBarItem(vscode.StatusBarAlignment.Left, 100);
        this._statusBarItem.text = "$(symbol-number) Counter: 0";
        this._statusBarItem.tooltip = "Flutter Counter Value";
        this._statusBarItem.show();
    }

    public resolveWebviewView(
        webviewView: vscode.WebviewView,
        context: vscode.WebviewViewResolveContext,
        _token: vscode.CancellationToken,
    ) {
        this.view = webviewView;

        // Configure the webview
        webviewView.webview.options = {
            enableScripts: true,
            localResourceRoots: [
                vscode.Uri.joinPath(this._extensionUri, 'build', 'web')
            ]
        };

        // Set its HTML content
        webviewView.webview.html = this._getHtml(webviewView.webview);

        // Handle messages from the webview
        webviewView.webview.onDidReceiveMessage(data => {
            switch (data.type) {
                case 'resetCounter':
                    vscode.window.showInformationMessage(`Flutter app says: "Resetting counter." Old value was: ${data.value}`);
                    this._updateStatusBar(data.value || 0);
                    break;
                case 'counterUpdate':
                    this._updateStatusBar(data.value);
                    break;
            }
        });
    }

    private _updateStatusBar(value: number): void {
        // The public `statusBarItem` getter is the only way to access this
        // from outside, and it ensures the item is created.
        this.statusBarItem.text = `$(symbol-number) Counter: ${value}`;
        this.statusBarItem.tooltip = `Flutter Counter Value: ${value}`;
    }


    private _getHtml(webview: vscode.Webview): string {
		const webviewUri = webview.asWebviewUri(vscode.Uri.joinPath(this._extensionUri, "build", "web"));

        console.log('webviewUri', webviewUri);

        // Read the built index.html file
        const indexHtmlPath = path.join(this._extensionUri.fsPath, "build", "web", "index.html");
        let indexHtml = '';
        try {
            indexHtml = fs.readFileSync(indexHtmlPath, 'utf8');
            console.log('Successfully read index.html');
        } catch (error) {
            console.error('Could not read build/web/index.html:', error);
            return `<html><body><h1>Error: Could not load Flutter app</h1><p>build/web/index.html not found</p></body></html>`;
        }

        // Replace the base href with the webview URI
        // The built index.html will have <base href="/"> instead of $FLUTTER_BASE_HREF
        indexHtml = indexHtml.replace('<base href="/">', `<base href="${webviewUri}/">`);

        console.log('Modified index.html for webview');
        return indexHtml;
    }
}

