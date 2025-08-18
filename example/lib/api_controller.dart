import 'package:flutter_vscode/annotations.dart';

part 'api_controller.g.dart';

@VSCodeController()
abstract class ApiController {
  @VSCodeCommand()
  Future<String> getUserName();

  @VSCodeCommand()
  Future<void> showInformationMessage(String message);
}
