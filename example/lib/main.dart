import 'package:flutter/material.dart';
import 'package:flutter_vscode/flutter_vscode.dart';
import 'api_controller.dart';

void main() {
  // Initialize VS Code webview message handling
  VSCodeWebViewHelper.initialize();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Flutter VS Code Example'),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              ElevatedButton(
                onPressed: () async {
                  final api = createApiController();
                  final response = await api.showInputBox('Enter your name');
                  api.showInformationMessage('Hello, $response!');
                },
                child: const Text('Show Input Box'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
