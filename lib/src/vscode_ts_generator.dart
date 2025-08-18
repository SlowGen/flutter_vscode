import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:flutter_vscode/annotations.dart';
import 'package:path/path.dart' as p;
import 'package:source_gen/source_gen.dart';

/// Generates TypeScript handler files from classes annotated with
/// [VSCodeController].
///
/// This generator creates:
/// 1. Individual handler files for each controller in out/api/
/// 2. A barrel file (api_controller.ts) that exports all handlers
/// 3. Command registration for custom commands
class VSCodeTsGenerator implements Builder {
  @override
  Map<String, List<String>> get buildExtensions => {
    r'^lib/{{dir}}/{{file}}.dart': [
      'src/generated/api_controller.handlers.ts',
      'src/generated/subscriptions.ts',
      'src/generated/api_controller.ts',
    ],
  };

  // Keep track of all generated files for the barrel export
  static final Set<String> _generatedFiles = <String>{};
  static final Set<String> _customCommands = <String>{};

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
      final result = await _generate(library, buildStep);

      if (result != null) {
        final baseName = p.basenameWithoutExtension(inputId.path);
        final handlerOutputId = AssetId(
          inputId.package,
          'src/generated/${_snakeCase(baseName)}.handlers.ts',
        );
        await buildStep.writeAsString(handlerOutputId, result.handlerContent);

        // Track generated files for future use
        _generatedFiles.add(p.basename(handlerOutputId.path));
        _customCommands.addAll(result.customCommands);
        
        // Generate barrel file and subscriptions file
        await _generateBarrelFile(buildStep);
        await _generateSubscriptionsFile(buildStep, _customCommands);
      }
    } on Exception catch (e) {
      // Skip files that can't be processed as libraries
      log.fine('Skipping ${inputId.path}: $e');
    }
  }

  Future<GeneratorResult?> _generate(
    LibraryReader library,
    BuildStep buildStep,
  ) async {
    const controllerChecker = TypeChecker.fromUrl(
      'package:flutter_vscode/annotations.dart#VSCodeController',
    );
    final controllers = library.classes.where(
      controllerChecker.hasAnnotationOf,
    );

    if (controllers.isEmpty) {
      return null;
    }

    const commandChecker = TypeChecker.fromUrl(
      'package:flutter_vscode/annotations.dart#VSCodeCommand',
    );

    final buffer = StringBuffer()
      ..writeln("import * as vscode from 'vscode';")
      ..writeln()
      ..writeln('// Generated TypeScript handlers for VS Code commands')
      ..writeln()
      ..writeln(
        'export function handleCommand(message: any, '
        'panel: vscode.WebviewPanel): void {',
      )
      ..writeln('  switch (message.command) {');

    final customCommands = <String>{};

    for (final controller in controllers) {
      for (final method in controller.methods) {
        if (commandChecker.hasAnnotationOf(method)) {
          final result = _generateCommandHandler(
            method,
            buildStep.inputId.package,
          );
          buffer.writeln(result.handlerCode);
          if (result.isCustomCommand) {
            customCommands.add(result.commandName);
          }
        }
      }
    }

    buffer
      ..writeln('    default:')
      ..writeln(r'      console.warn(`Unknown command: ${message.command}`);')
      ..writeln('      break;')
      ..writeln('  }')
      ..writeln('}');

    // Add command registration function for custom commands
    if (customCommands.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('// Register custom commands')
        ..writeln(
          'export function registerCommands(context: vscode.ExtensionContext): void {',
        )
        ..writeln('  const disposables = [');

      for (final command in customCommands) {
        buffer
          ..writeln(
            "    vscode.commands.registerCommand('$command', (...args) => {",
          )
          ..writeln('      // Custom command implementation would go here')
          ..writeln('      // This is a placeholder that can be overridden')
          ..writeln('      return Promise.resolve();')
          ..writeln('    }),');
      }

      buffer
        ..writeln('  ];')
        ..writeln('  context.subscriptions.push(...disposables);')
        ..writeln('}');
    }

    return GeneratorResult(
      handlerContent: buffer.toString(),
      customCommands: customCommands,
    );
  }

  CommandHandlerResult _generateCommandHandler(
    MethodElement method,
    String packageName,
  ) {
    final methodName = method.name;
    final parameters = method.formalParameters;

    // Get the command from annotation
    const commandChecker = TypeChecker.fromUrl(
      'package:flutter_vscode/annotations.dart#VSCodeCommand',
    );
    final commandAnnotation = commandChecker.firstAnnotationOf(method);
    String? commandName;

    if (commandAnnotation != null) {
      final commandValue = ConstantReader(commandAnnotation).peek('command');
      commandName = commandValue?.stringValue;
    }

    // Use method name if no command specified
    commandName ??= methodName;

    // Determine if this is a built-in VS Code command or custom command
    final isVSCodeCommand =
        (commandName?.startsWith('vscode.') ?? false) ||
        (commandName?.startsWith('workbench.') ?? false) ||
        (commandName?.startsWith('editor.') ?? false);

    final buffer = StringBuffer()..writeln("    case '$methodName': {");

    // Generate parameter extraction (avoid naming conflicts)
    if (parameters.isNotEmpty) {
      buffer.writeln('      const {');
      for (final param in parameters) {
        if (param.name == 'message') {
          buffer.writeln('        message: messageParam,');
        } else {
          buffer.writeln('        ${param.name},');
        }
      }
      buffer.writeln('      } = message.params || {};');
    }

    // Generate the appropriate command execution
    final hasReturnValue =
        method.returnType.toString() != 'void' &&
        !method.returnType.toString().contains('Future<void>');

    // Ensure commandName is not null for use in string interpolation
    final finalCommandName = commandName!;

    if (isVSCodeCommand) {
      // Built-in VS Code command
      if (parameters.isNotEmpty) {
        final args = parameters
            .map((p) {
              // Handle renamed parameters for naming conflict avoidance
              return p.name == 'message' ? 'messageParam' : p.name;
            })
            .join(', ');
        if (hasReturnValue) {
          buffer
            ..writeln(
              "      vscode.commands.executeCommand('$finalCommandName', $args)",
            )
            ..writeln('        .then(result => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            result')
            ..writeln('          });')
            ..writeln('        }, error => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            error: error.message || String(error)')
            ..writeln('          });')
            ..writeln('        });');
        } else {
          buffer.writeln(
            "      vscode.commands.executeCommand('$finalCommandName', $args);",
          );
        }
      } else {
        // No parameters
        if (hasReturnValue) {
          buffer
            ..writeln(
              "      vscode.commands.executeCommand('$finalCommandName')",
            )
            ..writeln('        .then(result => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            result')
            ..writeln('          });')
            ..writeln('        }, error => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            error: error.message || String(error)')
            ..writeln('          });')
            ..writeln('        });');
        } else {
          buffer.writeln(
            "      vscode.commands.executeCommand('$finalCommandName');",
          );
        }
      }
    } else {
      // Custom command
      if (parameters.isNotEmpty) {
        final args = parameters
            .map((p) {
              // Handle renamed parameters for naming conflict avoidance
              return p.name == 'message' ? 'messageParam' : p.name;
            })
            .join(', ');
        if (hasReturnValue) {
          buffer
            ..writeln(
              "      vscode.commands.executeCommand('$finalCommandName', $args)",
            )
            ..writeln('        .then(result => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            result')
            ..writeln('          });')
            ..writeln('        }, error => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            error: error.message || String(error)')
            ..writeln('          });')
            ..writeln('        });');
        } else {
          buffer.writeln(
            "      vscode.commands.executeCommand('$finalCommandName', $args);",
          );
        }
      } else {
        // No parameters
        if (hasReturnValue) {
          buffer
            ..writeln(
              "      vscode.commands.executeCommand('$finalCommandName')",
            )
            ..writeln('        .then(result => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            result')
            ..writeln('          });')
            ..writeln('        }, error => {')
            ..writeln('          panel.webview.postMessage({')
            ..writeln('            requestId: message.requestId,')
            ..writeln('            error: error.message || String(error)')
            ..writeln('          });')
            ..writeln('        });');
        } else {
          buffer.writeln(
            "      vscode.commands.executeCommand('$finalCommandName');",
          );
        }
      }
    }

    buffer
      ..writeln('      break;')
      ..writeln('    }');

    return CommandHandlerResult(
      handlerCode: buffer.toString(),
      commandName: commandName,
      isCustomCommand: !isVSCodeCommand,
    );
  }

  Future<void> _generateBarrelFile(BuildStep buildStep) async {
    final barrelId = AssetId(
      buildStep.inputId.package,
      'src/generated/api_controller.ts',
    );
    
    final buffer = StringBuffer()
      ..writeln('// Generated barrel file for all VS Code command handlers')
      ..writeln("import * as vscode from 'vscode';")
      ..writeln();

    // Import all handler files
    for (final file in _generatedFiles) {
      final importName = _camelCase(file.replaceAll('.handlers.ts', ''));
      buffer.writeln(
        "import { handleCommand as ${importName}Handler, registerCommands as ${importName}RegisterCommands } from './$file';",
      );
    }

    buffer
      ..writeln()
      ..writeln('// Main command handler that delegates to specific handlers')
      ..writeln(
        'export function handleCommand(message: any, panel: vscode.WebviewPanel): void {',
      )
      ..writeln('  // Try each handler until one processes the command');

    for (final file in _generatedFiles) {
      final handlerName = _camelCase(file.replaceAll('.handlers.ts', ''));
      buffer.writeln('  ${handlerName}Handler(message, panel);');
    }

    buffer.writeln('}');

    // Generate command registration function
    buffer
      ..writeln()
      ..writeln('// Register all custom commands')
      ..writeln(
        'export function registerAllCommands(context: vscode.ExtensionContext): void {',
      );

    for (final file in _generatedFiles) {
      final registerName = _camelCase(file.replaceAll('.handlers.ts', ''));
      buffer.writeln('  ${registerName}RegisterCommands?.(context);');
    }

    buffer.writeln('}');

    // Write the barrel file
    try {
      await buildStep.writeAsString(barrelId, buffer.toString());
    } catch (e) {
      // If we can't write it, just log it
      log.info('Cannot write barrel file: $e');
    }
  }

  Future<void> _generateSubscriptionsFile(
    BuildStep buildStep,
    Set<String> customCommands,
  ) async {
    if (customCommands.isEmpty) return;

    final subscriptionsId = AssetId(
      buildStep.inputId.package,
      'src/generated/subscriptions.ts',
    );
    
    final buffer = StringBuffer()
      ..writeln("import * as vscode from 'vscode';")
      ..writeln()
      ..writeln('// Generated subscription handlers for custom commands')
      ..writeln()
      ..writeln('export function subscribeToGeneratedContent(')
      ..writeln('  context: vscode.ExtensionContext,')
      ..writeln('  provider: vscode.WebviewViewProvider')
      ..writeln(') {')
      ..writeln('  // Register custom commands')
      ..writeln('  const disposables = [');

    for (final command in customCommands) {
      buffer
        ..writeln(
          "    vscode.commands.registerCommand('$command', (...args) => {",
        )
        ..writeln('      // Custom command implementation')
        ..writeln('      // You can implement your command logic here')
        ..writeln(
          '      console.log(`Executing custom command: $command`, args);',
        )
        ..writeln('      return Promise.resolve();')
        ..writeln('    }),');
    }

    buffer
      ..writeln('  ];')
      ..writeln()
      ..writeln('  // Add all disposables to extension context')
      ..writeln('  context.subscriptions.push(...disposables);')
      ..writeln()
      ..writeln(
        '  console.log(`Registered ${customCommands.length} custom commands:`, [',
      )
      ..writeln('    ${customCommands.map((cmd) => "'$cmd'").join(', ')}')
      ..writeln('  ]);')
      ..writeln('}');

    // Write the subscriptions file
    try {
      await buildStep.writeAsString(subscriptionsId, buffer.toString());
    } catch (e) {
      // If we can't write it, just log it
      log.info('Cannot write subscriptions file: $e');
    }
  }

  String _snakeCase(String input) {
    return input
        .replaceAllMapped(
          RegExp('[A-Z]'),
          (match) => '_${match.group(0)!.toLowerCase()}',
        )
        .replaceFirst(RegExp('^_'), '');
  }

  String _camelCase(String input) {
    final parts = input.split('_');
    return parts.first +
        parts
            .skip(1)
            .map((part) => part[0].toUpperCase() + part.substring(1))
            .join();
  }
}

class GeneratorResult {
  GeneratorResult({
    required this.handlerContent,
    required this.customCommands,
  });

  final String handlerContent;
  final Set<String> customCommands;
}

class CommandHandlerResult {
  CommandHandlerResult({
    required this.handlerCode,
    required this.commandName,
    required this.isCustomCommand,
  });

  final String handlerCode;
  final String commandName;
  final bool isCustomCommand;
}

Builder vscodeTsGenerator(BuilderOptions options) => VSCodeTsGenerator();
