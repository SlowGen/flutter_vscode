# Flutter VS Code Example

This example demonstrates how to use the `flutter_vscode` package to create a Flutter web application that can communicate with VS Code extensions through webview panels.

## Overview

The `flutter_vscode` package provides annotations and code generation tools to create a seamless bridge between Flutter web applications running in VS Code webview panels and the VS Code extension API.

## Features Demonstrated

This example shows how to:
- Set up VS Code webview communication
- Create annotated controller classes for VS Code API calls
- Generate TypeScript handlers automatically
- Handle user input and display messages through VS Code APIs

## Project Structure

```
example/
├── lib/
│   ├── main.dart                          # Main Flutter application
│   ├── api_controller.dart                # Annotated controller class
│   ├── api_controller.vscode.g.part       # Generated Dart code
│   └── api_controller.handlers.ts         # Generated TypeScript handlers
└── pubspec.yaml                           # Dependencies
```

## Setup Instructions

### 1. Add Dependencies

Make sure your `pubspec.yaml` includes the necessary dependencies:

```yaml
dependencies:
  flutter:
    sdk: flutter
  flutter_vscode:
    path: ../  # or from pub.dev when published

dev_dependencies:
  build_runner: ^2.4.6
```

### 2. Create a Controller Class

Define an abstract class with VS Code API methods using annotations:

```dart
import 'package:flutter_vscode/flutter_vscode.dart';

part 'your_controller.vscode.g.part';

@VSCodeController()
abstract class YourController {
  @VSCodeCommand()
  Future<void> showInformationMessage(String message);
  
  @VSCodeCommand()
  Future<String> showInputBox(String prompt);
  
  @VSCodeCommand()
  Future<void> showErrorMessage(String message);
}

// Factory function to create an instance
YourController createYourController() => _$YourController();
```

### 3. Initialize the Webview Helper

In your Flutter app's `main()` function, initialize the VS Code webview communication:

```dart
import 'package:flutter_vscode/flutter_vscode.dart';

void main() {
  // Initialize VS Code webview message handling
  VSCodeWebViewHelper.initialize();
  runApp(const MyApp());
}
```

### 4. Generate Code

Run the build runner to generate the necessary Dart and TypeScript code:

```bash
dart run build_runner build
```

This will generate:
- `*.vscode.g.part` - Dart implementation files
- `*.handlers.ts` - TypeScript handler files for your VS Code extension

### 5. Use in Your Flutter App

Create instances of your controller and call methods:

```dart
final api = createYourController();

// Show an information message
await api.showInformationMessage('Hello from Flutter!');

// Get user input
final result = await api.showInputBox('Enter your name:');

// Show error message
await api.showErrorMessage('Something went wrong!');
```

## Running the Example

### Option 1: Using the Complete Extension (Recommended)

1. **Install dependencies:**
   ```bash
   flutter pub get
   npm install
   ```

2. **Compile the extension:**
   ```bash
   npm run compile
   ```
   This single command handles:
   - Dart code generation (`build_runner`)
   - TypeScript compilation
   - Flutter web build

3. **Run the extension:**
   - Open this project in VS Code
   - Press `F5` or use the "Run Extension" configuration in the Debug panel
   - This will open a new VS Code window with your extension loaded

### Option 2: Starting from Scratch with the Generator

If you want to create a new project using the `flutter_vscode` package:

1. **Create a new Flutter project:**
   ```bash
   flutter create my_vscode_extension
   cd my_vscode_extension
   ```

2. **Add the flutter_vscode dependency to pubspec.yaml:**
   ```yaml
   dependencies:
     flutter_vscode: ^0.0.1  # or path to local package
   
   dev_dependencies:
     build_runner: ^2.4.6
   ```

3. **Generate VSCode extension files:**
   ```bash
   dart run flutter_vscode:generate_vscode_extension
   ```

4. **Install Node.js dependencies:**
   ```bash
   npm install
   ```

5. **Create your Flutter controller and compile:**
   ```bash
   npm run compile
   # This handles code generation, TypeScript compilation, and Flutter web build
   ```

6. **Run the extension:**
   - Open your project in VS Code
   - Press `F5` to run the extension in development mode

## Code Generation

The package uses code generation to create:

### Dart Side (`*.vscode.g.part`)
- Implementation of abstract controller methods
- Message handling and serialization
- Request/response coordination

### TypeScript Side (`*.handlers.ts`)
- VS Code API call implementations
- Message routing and parameter handling
- Response handling back to Flutter

## Available VS Code APIs

The example demonstrates these VS Code APIs, but you can extend it with any VS Code API:

- `vscode.window.showInformationMessage()`
- `vscode.window.showInputBox()`
- `vscode.window.showErrorMessage()`
- And many more VS Code APIs can be added by extending your controller

## Best Practices

1. **Null Safety:** The package handles null safety properly, avoiding explicit null checkers where possible
2. **Async Operations:** Use `Future<T>` return types for VS Code APIs that return values
3. **Error Handling:** Handle errors gracefully in both Flutter and TypeScript sides
4. **Clean Architecture:** Keep controllers focused and create separate controller classes for different functionality domains

## Troubleshooting

### Build Runner Issues
If code generation fails, try:
```bash
dart run build_runner clean
dart run build_runner build --delete-conflicting-outputs
```

### VS Code Integration Issues
- Ensure your VS Code extension properly imports the generated `.handlers.ts` files
- Verify webview panel message handling is set up correctly
- Check browser developer tools for JavaScript errors in the webview

## Next Steps

- Extend the controller with more VS Code APIs
- Add error handling and validation
- Create multiple controllers for different functionality areas
- Integrate with your specific VS Code extension requirements

For more information about the `flutter_vscode` package, see the main package documentation.
