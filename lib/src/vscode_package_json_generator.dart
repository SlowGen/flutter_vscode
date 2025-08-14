import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:path/path.dart' as p;

class VSCodePackageJsonGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/main.dart': ['package.json.updated']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (inputId.path != 'lib/main.dart') return;

    try {
      // Update the package.json file to include command contributions
      final packageJsonPath = p.join(Directory.current.path, 'package.json');
      final packageJsonFile = File(packageJsonPath);

      if (packageJsonFile.existsSync()) {
        final content = packageJsonFile.readAsStringSync();
        final packageJson = jsonDecode(content) as Map<String, dynamic>;

        // Update the package.json with our commands
        _updatePackageJson(packageJson);

        // Write back the updated package.json
        final updatedContent =
            const JsonEncoder.withIndent('  ').convert(packageJson);
        packageJsonFile.writeAsStringSync(updatedContent);

        // Create a marker file to indicate update was done
        final outputId = AssetId(inputId.package, 'package.json.updated');
        await buildStep.writeAsString(outputId, 'Updated package.json');
      }
    } catch (e) {
      print('Error updating package.json: $e');
    }
  }

  void _updatePackageJson(Map<String, dynamic> packageJson) {
    // Try to read actual project name from pubspec.yaml
    var projectName = 'my_flutter_extension';
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
      // Use fallback if can't read pubspec
    }

    // Use existing values if they're not template values, otherwise use project name
    if (packageJson['name'] == null ||
        packageJson['name'] == 'your_extension_name') {
      packageJson['name'] = projectName;
    }
    if (packageJson['displayName'] == null ||
        packageJson['displayName'] == 'Your Extension Display Name') {
      packageJson['displayName'] = projectName
          .replaceAll('_', ' ')
          .split(' ')
          .map((word) => word.isNotEmpty
              ? word[0].toUpperCase() + word.substring(1)
              : word)
          .join(' ');
    }
    if (packageJson['description'] == null ||
        packageJson['description'] == 'Describe your extension') {
      packageJson['description'] = 'A Flutter-based VSCode extension';
    }
    if (packageJson['publisher'] == null ||
        packageJson['publisher'] == 'your_publisher') {
      packageJson['publisher'] = 'your_publisher';
    }

    final finalProjectName = packageJson['name'] as String;
    final displayName = packageJson['displayName'] as String;

    // Keep or set basic extension properties
    packageJson['engines'] ??= {'vscode': '^1.80.0'};
    packageJson['categories'] ??= ['Other'];
    packageJson['main'] = './out/extension.js';

    // Set up activation events for webview
    final viewId = '${_sanitizeId(finalProjectName)}.webview';
    packageJson['activationEvents'] = ['onView:$viewId'];

    // Ensure contributes section exists
    packageJson['contributes'] ??= <String, dynamic>{};
    final contributes = packageJson['contributes'] as Map<String, dynamic>;

    // Ensure views section exists and has correct view ID
    contributes['views'] = {
      'explorer': [
        {'id': viewId, 'name': displayName, 'type': 'webview', 'when': 'true'}
      ]
    };

    // Add basic scripts if not present
    packageJson['scripts'] ??= {
      'vscode:prepublish': 'npm run compile',
      'compile': 'scripts/compile.sh',
      'watch': 'tsc -watch -p ./'
    };

    // Add basic devDependencies if not present
    final devDeps =
        packageJson['devDependencies'] as Map<String, dynamic>? ?? {};
    devDeps['@eslint/js'] ??= '^9.13.0';
    devDeps['@stylistic/eslint-plugin'] ??= '^2.9.0';
    devDeps['@types/node'] ??= '^24.0.14';
    devDeps['@types/vscode'] ??= '^1.80.0';
    devDeps['typescript'] ??= '^5.1.3';
    devDeps['typescript-eslint'] ??= '^8.26.0';
    devDeps['eslint'] ??= '^9.13.0';
    packageJson['devDependencies'] = devDeps;
  }

  String _sanitizeId(String name) {
    // Convert name to a valid ID format
    return name.replaceAll(RegExp('[^a-zA-Z0-9]'), '').toLowerCase();
  }
}
