// This is the heart of the code generation.
// It finds annotated code and generates the necessary files.
// Note: This is a simplified skeleton for now.

import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';
import '../annotations.dart';

class VSCodeGenerator extends GeneratorForAnnotation<VSCodeController> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    // Ensure we are working with a class element.
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '`@VSCodeController` can only be used on classes.',
        element: element,
      );
    }

    final classElement = element;
    final className = classElement.name;

    // We will generate the implementation for the abstract class.
    final buffer = StringBuffer();

    // Generate the implementation class.
    const implClassName = '_\$';
    buffer.writeln('class $implClassName$className implements $className {');
    buffer.writeln();

    // Find all methods annotated with @VSCodeCommand.
    for (final method in classElement.methods) {
      if (const TypeChecker.fromRuntime(VSCodeCommand).hasAnnotationOf(method)) {
        buffer.writeln(_generateMethodImplementation(method));
      }
    }

    buffer.writeln('}');
    buffer.writeln();

    // Generate a factory extension for easier instantiation
    buffer.writeln('extension ${className}Factory on $className {');
    buffer.writeln('  static $className create() => $implClassName$className();');
    buffer.writeln('}');
    buffer.writeln();

    // In a real implementation, we would also generate the TypeScript file here.
    // For now, we'll just focus on the Dart side.

    return buffer.toString();
  }

  String _generateMethodImplementation(MethodElement method) {
    final methodName = method.name;
    final parameters = method.parameters;
    final returnType = method.returnType;

    final buffer = StringBuffer();
    buffer.write('@override ');
    buffer.write('$returnType $methodName(');
    buffer.write(parameters.map((p) => '${p.type} ${p.name}').join(', '));
    buffer.writeln(') {');

    final paramList = parameters.map((p) => p.name).join(', ');

    if (returnType is VoidType) {
      // This is a synchronous void method. It returns nothing.
      buffer.writeln(
          '  VSCodeControllerBase.sendCommand(\'$methodName\', [$paramList], expectsResponse: false,);');
    } else if (returnType is InterfaceType && returnType.isDartAsyncFuture) {
      // This is a Future.
      final futureTypeArg =
          returnType.typeArguments.isNotEmpty ? returnType.typeArguments.first : null;

      if (futureTypeArg != null && futureTypeArg is VoidType) {
        // This is a Future<void>.
        buffer.writeln(
            '  return VSCodeControllerBase.sendCommand(\'$methodName\', [$paramList], expectsResponse: false,);');
      } else {
        // This is a Future<T> where T is not void.
        final returnTypeName =
            futureTypeArg?.getDisplayString() ?? 'dynamic';
        buffer.writeln(
            '  return VSCodeControllerBase.sendCommand<$returnTypeName>(\'$methodName\', [$paramList], expectsResponse: true,);');
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
