import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import '../annotations.dart';

/// Generates TypeScript handler files from classes annotated with [VSCodeController].
class VSCodeTsGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
        '.dart': ['.handlers.ts']
      };

  @override
  Future<void> build(BuildStep buildStep) async {
    final inputId = buildStep.inputId;
    if (!inputId.path.endsWith('.dart')) return;

    final library = LibraryReader(await buildStep.inputLibrary);
    final output = await _generate(library, buildStep);
    
    if (output != null) {
      final outputId = inputId.changeExtension('.handlers.ts');
      await buildStep.writeAsString(outputId, output);
    }
  }

  Future<String?> _generate(LibraryReader library, BuildStep buildStep) async {
    final buffer = StringBuffer();
    buffer.writeln('import * as vscode from \'vscode\';');
    buffer.writeln();

    final controllers = library.classes
        .where((c) => const TypeChecker.fromRuntime(VSCodeController).hasAnnotationOf(c));

    if (controllers.isEmpty) {
      return null;
    }

    buffer.writeln('export function handleCommand(message: any, panel: vscode.WebviewPanel) {');
    buffer.writeln('  switch (message.command) {');

    for (final controller in controllers) {
      for (final method in controller.methods) {
        if (const TypeChecker.fromRuntime(VSCodeCommand).hasAnnotationOf(method)) {
          buffer.writeln(_generateCommandHandler(method));
        }
      }
    }

    buffer.writeln('  }');
    buffer.writeln('}');

    return buffer.toString();
  }

  String _generateCommandHandler(MethodElement method) {
    final methodName = method.name;
    final parameters = method.parameters;

    final buffer = StringBuffer();
    buffer.writeln('    case \'$methodName\': {');

    final paramNames = parameters.asMap().entries.map((entry) => 'message.params[${entry.key}]').join(', ');

    if (method.returnType.toString().contains('Future<void>') || method.returnType is VoidType) {
      buffer.writeln('      vscode.window.$methodName($paramNames);');
    } else {
      buffer.writeln('      vscode.window.$methodName($paramNames).then(result => {');
      buffer.writeln('        panel.webview.postMessage({ requestId: message.requestId, result });');
      buffer.writeln('      });');
    }

    buffer.writeln('      break;');
    buffer.writeln('    }');

    return buffer.toString();
  }
}
