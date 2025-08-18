import 'dart:io';

import '../templates/index.dart';

void setupTypescript(Directory currentDir) {
  // Create src directory for TypeScript files
  final srcDir = Directory('${currentDir.path}/src');
  if (!srcDir.existsSync()) {
    srcDir.createSync();
  }

  // Create extension.ts
  File('${srcDir.path}/extension.ts').writeAsStringSync(extensionTemplate);
  print('Created: src/extension.ts');

  // Create api_controller.handlers.ts
  File(
    '${srcDir.path}/api_controller.handlers.ts',
  ).writeAsStringSync(apiControllerHandlersTemplate);
  print('Created: src/api_controller.handlers.ts');

  // Create package.json
  File(
    '${currentDir.path}/package.json',
  ).writeAsStringSync(packageJsonTemplate);
  print('Created: package.json');

  // Create tsconfig.json
  File('${currentDir.path}/tsconfig.json').writeAsStringSync(tsconfigTemplate);
  print('Created: tsconfig.json');
}
