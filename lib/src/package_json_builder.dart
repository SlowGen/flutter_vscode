import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

class PackageJsonBuilder implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
    r'lib/$lib': ['package.json'],
  };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    final library = await buildStep.inputLibrary;
    final output = _generate(LibraryReader(library), buildStep.inputId.package);

    final outputId = AssetId(inputId.package, 'package.json');
    await buildStep.writeAsString(outputId, output);
  }

  String _generate(LibraryReader library, String packageName) {
    final buffer = StringBuffer();

    const controllerChecker = TypeChecker.fromUrl(
      'package:flutter_vscode/annotations.dart#VSCodeController',
    );
    final controllers = library.classes.where(
      controllerChecker.hasAnnotationOf,
    );

    if (controllers.isEmpty) {
      return '';
    }

    final commands = controllers
        .expand((c) => c.methods)
        .where(
          (m) => const TypeChecker.fromUrl(
            'package:flutter_vscode/annotations.dart#VSCodeCommand',
          ).hasAnnotationOf(m),
        )
        .map((m) => _generatePackageJsonCommand(m, packageName))
        .join(',\n');

    buffer.write('''
      {
        "name": "$packageName",
        "displayName": "$packageName",
        "description": "A new Flutter VSCode extension.",
        "version": "0.0.1",
        "publisher": "$packageName",
        "engines": {
          "vscode": "^1.75.0"
        },
        "categories": [
          "Other"
        ],
        "activationEvents": [
          "onCommand:$packageName.helloWorld"
        ],
        "main": "./out/extension.js",
        "contributes": {
          "commands": [
            {
              "command": "$packageName.helloWorld",
              "title": "Hello World"
            },
            $commands
          ],
          "views": {
            "explorer": [
              {
                "id": "flutter_vscode",
                "name": "Flutter VSCode"
              }
            ]
          }
        },
        "scripts": {
          "vscode:prepublish": "npm run compile",
          "compile": "npm run build",
          "build": "tsc -p ./'"
        },
        "devDependencies": {
          "@types/vscode": "^1.75.0",
          "@types/glob": "^8.0.0",
          "@types/mocha": "^10.0.0",
          "@types/node": "^18.0.0",
          "eslint": "^8.24.0",
          "glob": "^8.0.0",
          "mocha": "^10.0.0",
          "typescript": "^4.8.4",
          "@vscode/test-electron": "^2.2.0"
        }
      }
      ''');

    return buffer.toString();
  }

  String _generatePackageJsonCommand(MethodElement method, String packageName) {
    final methodName = method.name;
    return '''
      {
        "command": "$packageName.$methodName",
        "title": "$methodName"
      }
      ''';
  }
}

Builder packageJsonBuilder(BuilderOptions options) => PackageJsonBuilder();
