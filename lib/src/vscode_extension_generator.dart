import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:flutter_vscode/annotations.dart';
import 'package:source_gen/source_gen.dart';

class VscodeExtensionGenerator
    extends GeneratorForAnnotation<VSCodeController> {
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@VSCodeController can only be used on classes.',
        element: element,
      );
    }

    return _generateDart(element);
  }

  String _generateDart(ClassElement element) {
    final className = element.name;
    final commands = element.methods
        .where((method) => method.isAbstract)
        .map(_generateDartCommand)
        .join('\n');

    return '''
      // ignore_for_file: unused_import

      import 'package:flutter_vscode/src/vscode_controller_base.dart';
      import 'package:flutter_vscode/src/vscode_interop.dart';

      class $className extends VSCodeControllerBase {
        $className(WebviewMessageHandler handler) : super(handler);

        $commands
      }
      ''';
  }

  String _generateDartCommand(MethodElement method) {
    final methodName = method.name;
    final parameters = method.formalParameters
        .map((param) => '${param.type.getDisplayString()} ${param.name}')
        .join(', ');
    final parameterNames = method.formalParameters
        .map((param) => param.name)
        .join(', ');
    final returnType = method.returnType.isDartAsyncFuture
        ? (method.returnType as InterfaceType).typeArguments[0]
        : method.returnType;

    return '''
      Future<${returnType.getDisplayString()}>
      $methodName($parameters) {
        return sendCommand('$methodName', [$parameterNames], expectsResponse: true);
      }
      ''';
  }
}
