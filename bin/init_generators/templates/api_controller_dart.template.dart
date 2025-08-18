const String apiControllerTemplate = '''
import 'package:flutter_vscode/annotations.dart';

part 'api_controller.vscode.g.dart';

@VSCodeController()
abstract class ApiController {
  // Example of built-in VS Code command
  @VSCodeCommand('vscode.open')
  Future<void> openFile(String path);

  // Example of custom command
  @VSCodeCommand('my-extension.sayHello')
  Future<String> sayHello(String name);

  // Example with no command specified (uses method name)
  @VSCodeCommand()
  Future<String> getUserName();

  // Example of void custom command
  @VSCodeCommand('my-extension.showInfo')
  Future<void> showInformationMessage(String message);
}
''';
