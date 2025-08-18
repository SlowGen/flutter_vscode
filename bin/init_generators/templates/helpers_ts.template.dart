const String helpersTemplate = r'''
import * as vscode from 'vscode';
import * as path from 'path';
import * as fs from 'fs';

export function getProjectName(): string {
    // Assume the project root is one level up from the 'src' directory
    const projectRoot = path.join(__dirname, '..');
    const pubspecPath = path.join(projectRoot, 'pubspec.yaml');

    try {
        const pubspecContent = fs.readFileSync(pubspecPath, 'utf8');
        const nameMatch = /^name:\s*(.*)$/m.exec(pubspecContent);
        if (nameMatch && nameMatch[1]) {
            return nameMatch[1].trim();
        }
    } catch (e) {
        console.error("Error reading or parsing pubspec.yaml", e);
        vscode.window.showErrorMessage(`Failed to read project name from pubspec.yaml: ${e}`);
    }
    // Fallback project name
    return 'unknown_project';
}
''';
