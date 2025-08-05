# Flutter VSCode Extension Framework

A Flutter package that enables you to build VSCode extensions using Flutter for the UI and Dart for the business logic. This package provides annotations, code generation, and tooling to seamlessly integrate Flutter web apps into VSCode extension webviews.

## Features

- **Annotation-based code generation**: Use `@VSCodeController` and `@VSCodeCommand` annotations to automatically generate TypeScript extension code
- **Flutter UI integration**: Build your extension's UI using Flutter widgets
- **Bidirectional communication**: Seamless communication between Flutter (Dart) and VSCode (TypeScript)
- **Extension scaffolding**: Automatic generation of VSCode extension project structure
- **Webview compatibility**: Pre-configured for VSCode webview constraints and security policies
- **Build automation**: Integrated build scripts for both Flutter and TypeScript compilation

## Getting started

### Prerequisites

- **Flutter SDK**: Install from [flutter.dev](https://flutter.dev/docs/get-started/install)
- **Dart SDK**: Included with Flutter
- **Node.js**: Install the latest stable version from [nodejs.org](https://nodejs.org/)
- **VSCode**: For extension development and testing

### Installation

1. Add this package to your `pubspec.yaml`:

```yaml
dependencies:
  flutter_vscode: ^0.1.0

dev_dependencies:
  build_runner: ^2.3.0
```

2. Run `flutter pub get`

## Usage

### 1. Generate Extension Scaffold

Create a new VSCode extension project structure:

```bash
dart run flutter_vscode/bin/generate_vscode_extension.dart
```

This creates:
- VSCode extension configuration (`package.json`, `launch.json`)
- TypeScript setup (`tsconfig.json`, `src/extension.ts`)
- Flutter web configuration (`web/` directory with webview-compatible setup)
- Build scripts and `.gitignore`

### 2. Define Your Extension Logic

Create a controller class with annotations:

```dart
import 'package:flutter_vscode/flutter_vscode.dart';

// IMPORTANT: Add this part directive for code generation
part 'my_extension_controller.g.dart';

@VSCodeController()
abstract class MyExtensionController {
  @VSCodeCommand()
  void sayHello(String name);
  
  @VSCodeCommand()
  Future<String> openPanel();
  
  @VSCodeCommand()
  void updateStatusBar(int count);
}
```

### 3. Build Your Flutter UI

Create your Flutter app that uses the generated controller:

```dart
import 'package:flutter/material.dart';
import 'my_extension_controller.dart'; // Import your controller

void main() {
  runApp(const MyExtensionApp());
}

class MyExtensionApp extends StatelessWidget {
  const MyExtensionApp({super.key});
  
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'VSCode Extension Demo',
      home: const ExtensionPanel(),
    );
  }
}

class ExtensionPanel extends StatefulWidget {
  const ExtensionPanel({super.key});
  
  @override
  State<ExtensionPanel> createState() => _ExtensionPanelState();
}

class _ExtensionPanelState extends State<ExtensionPanel> {
  late MyExtensionController _controller;
  int _counter = 0;
  
  @override
  void initState() {
    super.initState();
    // Use the generated factory method to create controller instance
    _controller = MyExtensionControllerFactory.create();
  }
  
  void _incrementCounter() {
    setState(() {
      _counter++;
    });
    
    // Communicate with VSCode extension
    try {
      _controller.updateStatusBar(_counter);
    } catch (e) {
      debugPrint('Could not update VSCode status bar: $e');
    }
  }
  
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VSCode Extension Demo'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Text('You have clicked the button this many times:'),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              onPressed: _incrementCounter,
              child: const Text('Increment & Update Status Bar'),
            ),
          ],
        ),
      ),
    );
  }
}
```

### 4. Generate Extension Code

Run code generation to create TypeScript extension handlers:

```bash
dart run build_runner build
```

### 5. Build and Test

```bash
# Install Node.js dependencies
npm install

# Build everything (Dart, TypeScript, Flutter web)
npm run compile

# Test in VSCode
# Press F5 in VSCode to launch extension development host
```

## Project Structure

After running the generator, your project will have:

```
├── .vscode/
│   └── launch.json          # VSCode debug configuration
├── lib/
│   └── main.dart           # Your Flutter app
├── src/
│   └── extension.ts        # TypeScript extension entry point
├── web/
│   ├── index.html          # Webview-compatible HTML
│   ├── flutter_bootstrap.js # Flutter web bootstrap
│   └── manifest.json       # Web app manifest
├── scripts/
│   └── compile.sh          # Build automation script
├── package.json            # VSCode extension configuration
├── tsconfig.json           # TypeScript configuration
└── pubspec.yaml           # Flutter/Dart dependencies
```

## Generated Files

The build process automatically generates:
- `*.handlers.ts` - TypeScript command handlers from your Dart annotations
- `*.g.dart` - Dart implementation classes for your controllers
- Webview registration code in `extension.ts`

## Additional Information

### Webview Constraints

This package handles VSCode webview limitations:
- Content Security Policy (CSP) compliance
- Local resource loading restrictions
- History API compatibility
- Remote resource blocking

### Build Integration

The generated `compile.sh` script handles:
1. Dart code generation with `build_runner`
2. TypeScript compilation
3. Flutter web build with webview-specific flags

### Contributing

Contributions are welcome! Please see our [contributing guidelines](CONTRIBUTING.md) for details.

### Troubleshooting

If you encounter issues:
- Ensure your `pubspec.yaml` has the correct dependencies
- Run `flutter pub get` to get latest dependencies
- Check for typos in your `part` declarations
- Validate VSCode and Flutter logs for hints
- Ensure Node.js is installed and npm dependencies are resolved

### Issues

Report bugs and feature requests on our [GitHub issues page](https://github.com/your-repo/flutter_vscode/issues).
