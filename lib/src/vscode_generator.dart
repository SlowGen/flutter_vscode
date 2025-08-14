// This is the heart of the code generation.
// It finds annotated code and generates the necessary files.
// Note: This is a simplified skeleton for now.

import 'package:analyzer/dart/element/element2.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:flutter_vscode/annotations.dart';
import 'package:source_gen/source_gen.dart';

class VSCodeGenerator extends GeneratorForAnnotation<VSCodeController> {
  @override
  dynamic generateForAnnotatedElement(
    covariant Element2 element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    // Ensure we are working with a class element.
    if (element is! ClassElement2) {
      throw InvalidGenerationSourceError(
        '`@VSCodeController` can only be used on classes.',
        element: element,
      );
    }

    final classElement = element;
    final className = classElement.lookupName;

    // We will generate the implementation for the abstract class.
    final buffer = StringBuffer();

    // Note: part-of directive will be added automatically by source_gen
    // so we don't need to add it here

    // Generate the implementation class.
    const implClassName = r'_$';
    buffer.writeln('class $implClassName$className implements $className {');
    buffer.writeln();

    // Find all methods annotated with @VSCodeCommand.
    for (final method in classElement.methods2) {
      const checker = TypeChecker.fromUrl(
        'package:flutter_vscode/annotations.dart#VSCodeCommand',
      );
      if (checker.hasAnnotationOf(method)) {
        buffer.writeln(_generateMethodImplementation(method));
      }
    }

    buffer.writeln('}');
    buffer.writeln();

    // Generate a factory extension for easier instantiation
    buffer.writeln('extension ${className}Factory on $className {');
    buffer.writeln(
      '  static $className create() => $implClassName$className();',
    );
    buffer.writeln('}');
    buffer.writeln();

    // In a real implementation, we would also generate the TypeScript file here.
    // For now, we'll just focus on the Dart side.

    return buffer.toString();
  }

  String _generateMethodImplementation(MethodElement2 method) {
    final methodName = method.lookupName;
    final parameters = method.formalParameters;
    final returnType = method.returnType;

    final buffer = StringBuffer();
    buffer.write('@override ');
    buffer.write('$returnType $methodName(');
    buffer.write(parameters.map((p) => '${p.type} ${p.displayName}').join(', '));
    buffer.writeln(') {');

    final paramList = parameters.map((p) => p.displayName).join(', ');

    if (returnType is VoidType) {
      // This is a synchronous void method. It returns nothing.
      buffer.writeln(
        "  VSCodeControllerBase.sendCommand('$methodName', [$paramList], expectsResponse: false,);",
      );
    } else if (returnType is InterfaceType && returnType.isDartAsyncFuture) {
      // This is a Future.
      final futureTypeArg = returnType.typeArguments.isNotEmpty
          ? returnType.typeArguments.first
          : null;

      if (futureTypeArg != null && futureTypeArg is VoidType) {
        // This is a Future<void>.
        buffer.writeln(
          "  return VSCodeControllerBase.sendCommand('$methodName', [$paramList], expectsResponse: false,);",
        );
      } else {
        // This is a Future<T> where T is not void.
        final returnTypeName = futureTypeArg?.getDisplayString() ?? 'dynamic';
        buffer.writeln(
          "  return VSCodeControllerBase.sendCommand<$returnTypeName>('$methodName', [$paramList], expectsResponse: true,);",
        );
      }
    } else {
      // This is a synchronous method with a return value, which isn't supported.
      throw InvalidGenerationSourceError(
        'Methods annotated with @VSCodeCommand must return a Future or void.',
        element: method,
      );
    }

    buffer.writeln('}');

    return buffer.toString();
  }
}
