import 'dart:async';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

/// Generates the main TypeScript extension entry point.
/// 
/// This builder creates the main extension file that handles
/// activation, deactivation, and command registration.
class VSCodeMainExtensionGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/main.dart': ['src/extension.ts.updated']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (inputId.path != 'lib/main.dart') return;

    try {
      // Update the main extension.ts file to use the generated code
      final extensionPath = 
          p.join(Directory.current.path, 'src', 'extension.ts');
      final extensionFile = File(extensionPath);
      
      if (extensionFile.existsSync()) {
        final newContent = _generateMainExtensionContent();
        extensionFile.writeAsStringSync(newContent);
        
        // Create a marker file to indicate update was done
        final outputId = AssetId(inputId.package, 'src/extension.ts.updated');
        await buildStep.writeAsString(outputId, 'Updated extension.ts');
      }
    } on Exception catch (e) {
      print('Error updating extension.ts: $e');
    }
  }

  String _generateMainExtensionContent() {
    return '''
import * as vscode from 'vscode';
import { activate as activateGenerated } from './extension.generated';

export function activate(context: vscode.ExtensionContext) {
    console.log('Flutter VSCode extension is now active!');
    
    // Use generated activation logic
    activateGenerated(context);
}

export function deactivate() {
    console.log('Flutter VSCode extension deactivated.');
}
''';
  }
}
