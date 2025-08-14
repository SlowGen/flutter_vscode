import 'dart:async';

import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:flutter_vscode/annotations.dart';
import 'package:source_gen/source_gen.dart';

/// Generates TypeScript handler files from classes annotated with [VSCodeController].
class VSCodeTsGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        'lib/{{}}.dart': ['src/{{}}.handlers.ts']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (!inputId.path.endsWith('.dart')) return;

    // Skip generated files
    if (inputId.path.contains('.g.dart') ||
        inputId.path.contains('.part') ||
        inputId.path.contains('generated')) {
      return;
    }

    try {
      final library = LibraryReader(await buildStep.inputLibrary);
      final output = await _generate(library, buildStep);

      if (output != null) {
        // Generate TypeScript file in src folder instead of lib folder
        final fileName =
            inputId.pathSegments.last.replaceAll('.dart', '.handlers.ts');
        final outputId = AssetId(inputId.package, 'src/$fileName');
        await buildStep.writeAsString(outputId, output);
      }
    } catch (e) {
      // Skip files that can't be processed as libraries
      log.info('Skipping ${inputId.path}: $e');
    }
  }

  Future<String?> _generate(LibraryReader library, BuildStep buildStep) async {
    final buffer = StringBuffer();
    buffer.writeln("import * as vscode from 'vscode';");
    buffer.writeln();

    const controllerChecker = TypeChecker.fromUrl('package:flutter_vscode/annotations.dart#VSCodeController');
    final controllers = library.classes.where(controllerChecker.hasAnnotationOf);

    if (controllers.isEmpty) {
      return null;
    }

    buffer.writeln(
        'export function handleCommand(message: any, panel: vscode.WebviewPanel) {');
    buffer.writeln('  switch (message.command) {');

    // ignore: deprecated_member_use
    const commandChecker = TypeChecker.fromUrl('package:flutter_vscode/annotations.dart#VSCodeCommand');
    for (final controller in controllers) {
      for (final method in controller.methods2) {
        if (commandChecker.hasAnnotationOf(method)) {
          buffer.writeln(_generateCommandHandler(method));
        }
      }
    }

    buffer.writeln('  }');
    buffer.writeln('}');

    return buffer.toString();
  }

  String _generateCommandHandler(MethodElement2 method) {
    final methodName = method.lookupName;
    final parameters = method.formalParameters;

    final buffer = StringBuffer();
    buffer.writeln("    case '$methodName': {");

    final paramNames = parameters.isNotEmpty
        ? ', ${parameters.asMap().entries.map((entry) => 'message.params[${entry.key}]').join(', ')}'
        : '';

    if (method.returnType.toString().contains('Future<void>') ||
        method.returnType is VoidType) {
      buffer.writeln(
          "      vscode.commands.executeCommand('flutter-demo.$methodName'$paramNames);");
    } else {
      buffer.writeln(
          "      vscode.commands.executeCommand('flutter-demo.$methodName'$paramNames).then(result => {");
      buffer.writeln(
          '        panel.webview.postMessage({ requestId: message.requestId, result });');
      buffer.writeln('      });');
    }

    buffer.writeln('      break;');
    buffer.writeln('    }');

    return buffer.toString();
  }
}
