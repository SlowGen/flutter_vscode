import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';

class VSCodeExtensionGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/main.dart': ['src/extension.ts']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (inputId.path != 'lib/main.dart') return;

    try {
      // We need to scan all files for controllers, but only generate once from main.dart
      final output = await _generateExtension(buildStep);

      if (output != null) {
        final outputId = AssetId(inputId.package, 'src/extension.ts');
        await buildStep.writeAsString(outputId, output);
      }
    } catch (e) {
      print('Error generating extension: $e');
    }
  }

  Future<String?> _generateExtension(BuildStep buildStep) async {
    // Try to read project name from pubspec or directory
    var projectName = 'myflutterextension';
    try {
      const pubspecPath = 'pubspec.yaml';
      final file = File(pubspecPath);
      if (file.existsSync()) {
        final content = file.readAsStringSync();
        final lines = content.split('\n');
        for (final line in lines) {
          if (line.startsWith('name:')) {
            projectName = line.split(':')[1].trim();
            break;
          }
        }
      }
    } catch (e) {
      // Use default if can't read pubspec
    }

    // Generate a generic Flutter webview extension structure
    final buffer = StringBuffer();

    buffer.writeln("import * as vscode from 'vscode';");
    buffer.writeln("import * as path from 'path';");
    buffer.writeln("import * as fs from 'fs';");

    buffer.writeln();
    buffer.writeln(
        'export function activate(context: vscode.ExtensionContext) {');
    buffer.writeln("    console.log('Flutter VSCode extension activated');");
    buffer.writeln();
    buffer.writeln(
        '    const provider = new FlutterWebviewProvider(context.extensionUri);');
    buffer.writeln();
    buffer.writeln('    // Register the webview provider');
    buffer.writeln('    context.subscriptions.push(');
    buffer.writeln(
        '        vscode.window.registerWebviewViewProvider(FlutterWebviewProvider.viewType, provider)');
    buffer.writeln('    );');
    buffer.writeln();
    buffer.writeln('    // TODO: Register your custom commands here');
    buffer.writeln('    // Example:');
    buffer.writeln(
        "    // context.subscriptions.push(vscode.commands.registerCommand('yourextension.command', () => {");
    buffer.writeln('    //     if (provider.view) {');
    buffer.writeln(
        "    //         provider.view.webview.postMessage({ type: 'your-message' });");
    buffer.writeln('    //     }');
    buffer.writeln('    // }));');
    buffer.writeln('}');
    buffer.writeln();
    buffer.writeln('export function deactivate() {');
    buffer
        .writeln("    console.log('Flutter VSCode extension deactivated');");
    buffer.writeln('}');

    buffer.writeln(_getWebviewProviderClass(projectName));

    return buffer.toString();
  }

  String _getWebviewProviderClass(String projectName) {
    final sanitizedName =
        projectName.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
    final viewId = '$sanitizedName.webview';

    return '''

class FlutterWebviewProvider implements vscode.WebviewViewProvider {
    public static readonly viewType = '$viewId';

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
            // TODO: Handle messages from your Flutter app
            console.log('Received message from Flutter:', data);

            // Example message handling:
            // switch (data.type) {
            //     case 'myCustomMessage':
            //         vscode.window.showInformationMessage(`Flutter says: \${data.message}`);
            //         break;
            // }
        });
    }

    private _getHtml(webview: vscode.Webview): string {
        const webviewUri = webview.asWebviewUri(vscode.Uri.joinPath(this._extensionUri, "build", "web"));

        console.log('Loading Flutter app from:', webviewUri.toString());

        // Read the built index.html file
        const indexHtmlPath = path.join(this._extensionUri.fsPath, "build", "web", "index.html");
        let indexHtml = '';
        try {
            indexHtml = fs.readFileSync(indexHtmlPath, 'utf8');
            console.log('Successfully loaded Flutter app HTML');
        } catch (error) {
            console.error('Could not read build/web/index.html:', error);
            return `<html><body><h1>Flutter App Not Found</h1><p>Please run 'flutter build web' first, then reload the extension.</p></body></html>`;
        }

        // Replace the base href with the webview URI
        indexHtml = indexHtml.replace('<base href="/">', `<base href="\${webviewUri}/">`);

        return indexHtml;
    }
}
''';
  }
}
