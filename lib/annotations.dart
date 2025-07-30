// Defines the annotations that developers will use.

/// A class-level annotation to mark a class as a VS Code controller.
///
/// The generator will process classes with this annotation to create
/// the communication bridge to the VS Code extension runtime.
class VSCodeController {
  const VSCodeController();
}

/// A method-level annotation to mark a method as a command
/// that can be called on the VS Code extension runtime.
///
/// The annotated method must be abstract and part of a class
/// annotated with [VSCodeController].
class VSCodeCommand {
  const VSCodeCommand();
}
