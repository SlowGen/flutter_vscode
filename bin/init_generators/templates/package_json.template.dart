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
    "vscode:prepublish": "npm run compile"
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
