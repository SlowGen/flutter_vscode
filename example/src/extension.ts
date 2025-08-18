import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';
import { getProjectName } from './helpers';
import { subscribeToGeneratedContent } from './generated/subscriptions';

const projectName = getProjectName();

export function activate(context: vscode.ExtensionContext) {
    const provider = new FlutterWebviewProvider(context.extensionUri);

    // The viewType is now dynamically set based on the pubspec.yaml name
    context.subscriptions.push(
        vscode.window.registerWebviewViewProvider(FlutterWebviewProvider.viewType, provider)
    );

    subscribeToGeneratedContent(context, provider);

}

class FlutterWebviewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = `${projectName}.project`;

    public view?: vscode.WebviewView;

    constructor(
        private readonly _extensionUri: vscode.Uri,
    ) {}


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

        });
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


export function deactivate() {}

