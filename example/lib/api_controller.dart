import 'package:flutter_vscode/flutter_vscode.dart';

part 'api_controller.vscode.g.part';

/// Example VSCode controller demonstrating command integration.
@VSCodeController()
abstract class ApiController {
  /// Shows an information message to the user.
  @VSCodeCommand()
  Future<void> showInformationMessage(String message);
  
  /// Shows an input box and returns the user's input.
  @VSCodeCommand()
  Future<String> showInputBox(String prompt);
  
  /// Shows an error message to the user.
  @VSCodeCommand()
  Future<void> showErrorMessage(String message);
}

/// Factory function to create an instance of the API controller.
ApiController createApiController() => ApiControllerFactory.create();
