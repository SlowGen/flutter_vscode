# Flutter VSCode Extension Framework

A Flutter package that enables you to build VSCode extensions using Flutter for the UI and Dart for the business logic. This package provides annotations, code generation, and tooling to seamlessly integrate Flutter web apps into VSCode extension webviews.

## Features

-   **Annotation-based code generation**: Use `@VSCodeController` and `@VSCodeCommand` annotations to automatically generate TypeScript extension code.
-   **Flutter UI integration**: Build your extension's UI using Flutter widgets.
-   **Bidirectional communication**: Seamless communication between Flutter (Dart) and VSCode (TypeScript).
-   **Extension scaffolding**: Automatic generation of VSCode extension project structure.
-   **Webview compatibility**: Pre-configured for VSCode webview constraints and security policies.
-   **Build automation**: Integrated build scripts for both Flutter and TypeScript compilation.

## Getting started

### Prerequisites

-   **Flutter SDK**: Install from [flutter.dev](https://flutter.dev/docs/get-started/install)
-   **Dart SDK**: Included with Flutter
-   **Node.js**: Install the latest stable version from [nodejs.org](https://nodejs.org/)
-   **VSCode**: For extension development and testing


## Usage

### 1. Create Flutter Project and Generate Extension Scaffold

First, create a web-only Flutter project:

```bash
flutter create --platforms web your_extension_name
cd your_extension_name
```

Then, add these packages to your `pubspec.yaml`:

  ```yaml
  dependencies:
    flutter_vscode: ^0.1.0

  dev_dependencies:
    build_runner: ^2.3.0
  ```

Run `flutter pub get`

Then generate the VSCode extension project structure:

```bash
dart run flutter_vscode:init
```

This command will create:
-   VSCode extension configuration (`package.json`, `tsconfig.json`)
-   TypeScript setup (`src/extension.ts`)
-   Flutter web configuration (`web/` directory with webview-compatible setup)
-   Build scripts (`scripts/compile.sh`) and `.gitignore`

### 2. Examine the Generated Extension Logic

The `dart run flutter_vscode:init` command creates an example controller class at `lib/api_controller.dart`:

Don't panic when you see the red! That is for the yet to be generated code. This will go away when you run build_runner

```dart
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
```

#### Command Types

The `@VSCodeCommand` annotation supports different command types:

- **Built-in VS Code commands**: Use VS Code's built-in command IDs like `'vscode.open'`, `'workbench.action.files.save'`
- **Custom commands**: Define your own commands like `'my-extension.sayHello'` that will be registered by your extension
- **Method name commands**: Use `@VSCodeCommand()` without parameters to use the method name as the command

You can modify this controller or create additional controllers as needed for your extension.

### 3. Build Your Flutter UI

The `dart run flutter_vscode:init` command also creates an example Flutter app that uses the generated controller. You can examine and modify `lib/main.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_vscode/flutter_vscode.dart';
import 'api_controller.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Flutter VS Code Extension',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'Flutter VS Code Extension Demo'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  late ApiController _apiController;
  String _response = '';

  @override
  void initState() {
    super.initState();
    // Create the controller instance using WebviewMessageHandler
    _apiController = ApiController(WebviewMessageHandler());
  }

  Future<void> _openFile() async {
    try {
      await _apiController.openFile('/path/to/file.txt');
      setState(() {
        _response = 'File open command sent';
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
    }
  }

  Future<void> _sayHello() async {
    try {
      final result = await _apiController.sayHello('Flutter');
      setState(() {
        _response = 'Response: $result';
      });
    } catch (e) {
      setState(() {
        _response = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              'VS Code Extension Demo',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _openFile,
              child: const Text('Open File (VS Code Command)'),
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _sayHello,
              child: const Text('Say Hello (Custom Command)'),
            ),
            const SizedBox(height: 20),
            Text(
              _response,
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4. Build and Test

1.  Run `npm install` to install TypeScript dependencies.
2.  Run `npm run compile` to build everything (Dart code generation, TypeScript compilation, Flutter web build).
3.  Open VS Code and press F5 to launch the extension development host.

## Project Structure

After running `dart run flutter_vscode:init`, your project will have:

```
├── .vscode/
│   └── launch.json          # VSCode debug configuration (created when you F5)
├── lib/
│   ├── main.dart           # Your Flutter app (generated)
│   ├── api_controller.dart # Example extension controller (generated)
│   └── api_controller.vscode.g.part # Generated Dart implementation (after build)
├── src/
│   ├── extension.ts        # TypeScript extension entry point (generated)
│   ├── helpers.ts          # Helper utilities (generated)
│   ├── generated/
│   │   ├── api_controller.ts # Generated API integration (generated)
│   │   └── commands.ts      # Command definitions (generated)
│   └── api_controller.handlers.ts # Generated TypeScript handlers (after build)
├── web/
│   ├── index.html          # Webview-compatible HTML (generated)
│   └── flutter_bootstrap.js # Flutter web bootstrap (generated)
├── scripts/
│   └── compile.sh          # Build automation script (generated)
├── package.json            # VSCode extension configuration (generated)
├── tsconfig.json           # TypeScript configuration (generated)
└── pubspec.yaml           # Flutter/Dart dependencies (updated)
```

## Generated Files

The build process automatically generates:
-   `*.handlers.ts` - TypeScript command handlers from your Dart annotations (output to `src/`)
-   `*.g.dart` - Dart implementation classes for your controllers
-   `flutter_bootstrap.js` - Webview communication bridge
-   Modified `web/index.html` (after `compile.sh` moves `index.html.temp`)

### Communicating from VSCode to Flutter

While the `@VSCodeCommand` annotations are great for Flutter-to-VSCode communication, you might need to send messages from the VSCode extension back to your Flutter UI. This is where the `WebviewMessageHandler` comes in.

You can use it in your Flutter app to listen for messages sent from the TypeScript side of your extension.

**1. Initialize the handler in your Flutter app:**

```dart
import 'package:flutter_vscode/flutter_vscode.dart';

// ... in your widget's state

late final WebviewMessageHandler _messageHandler;

@override
void initState() {
  super.initState();
  _messageHandler = WebviewMessageHandler()
    ..setMessageHandler((message) {
      // Handle the message from VSCode
      print('Received message from VSCode: ${message.command} - ${message.params} - ${message.requestId} - ${message.error} - ${message.result}');
    });
}

@override
void dispose() {
  _messageHandler.dispose();
  super.dispose();
}
```

## Additional Information

### Webview Constraints

This package handles VSCode webview limitations:
-   Content Security Policy (CSP) compliance
-   Local resource loading restrictions
-   History API compatibility
-   Remote resource blocking

### Build Integration

The `scripts/compile.sh` script handles:
1.  Dart code generation with `build_runner`
2.  Moving `web/index.html.temp` to `web/index.html`
3.  Flutter web build with webview-specific flags (`--no-web-resources-cdn --csp `) - these are necessary to comply with extension rules on external code

### Contributing

Contributions are welcome! Please see our [contributing guidelines](CONTRIBUTING.md) for details.

### Troubleshooting

If you encounter issues:
-   Ensure your `pubspec.yaml` has the correct dependencies.
-   Run `flutter pub get` to get latest dependencies.
-   Check for typos in your `part` declarations.
-   Validate VSCode and Flutter logs for hints.
-   Ensure Node.js is installed and npm dependencies are resolved.

### Issues

Report bugs and feature requests on our [GitHub issues page](https://github.com/your-repo/flutter_vscode/issues).
