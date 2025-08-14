import 'package:flutter_vscode/flutter_vscode.dart';

part 'api_controller.vscode.g.part';

@VSCodeController()
abstract class ApiController {
  @VSCodeCommand()
  Future<void> showInformationMessage(String message);
  
  @VSCodeCommand()
  Future<String> showInputBox(String prompt);
  
  @VSCodeCommand()
  Future<void> showErrorMessage(String message);
}

// Factory function to create an instance
ApiController createApiController() => ApiControllerFactory.create();
