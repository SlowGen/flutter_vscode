// Defines the annotations that developers will use.

/// A class-level annotation to mark a class as a VS Code controller.
///
/// The generator will process classes with this annotation to create
/// the communication bridge to the VS Code extension runtime.
class VSCodeController {
  /// Creates a new VSCode controller annotation.
  const VSCodeController();
}

/// A method-level annotation to mark a method as a command
/// that can be called on the VS Code extension runtime.
///
/// The annotated method must be abstract and part of a class
/// annotated with [VSCodeController].
class VSCodeCommand {
  /// Creates a new VSCode command annotation.
  /// 
  /// [command] is the VS Code command ID to execute (e.g., 'vscode.open')
  /// or a custom command name (e.g., 'my-extension.sayHello').
  /// If not provided, the method name will be used as the command name.
  const VSCodeCommand([this.command]);
  
  /// The command ID to execute in VS Code.
  final String? command;
}
