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

  // Create helpers.ts
  File('${srcDir.path}/helpers.ts').writeAsStringSync(helpersTemplate);
  print('Created: src/helpers.ts');

  // Create generated file directory
  final generatedDir = Directory('${srcDir.path}/generated');
  if (!generatedDir.existsSync()) {
    generatedDir.createSync();
  }

  // Create command handler
  File(
    '${generatedDir.path}/commands.ts',
  ).writeAsStringSync(commandHandlerTemplate);
  print('Created: src/generated/commands.ts');

  // Create barrel for generated files
  File(
    '${generatedDir.path}/api_controller.ts',
  ).writeAsStringSync(barrelTsTemplate);

  // Create package.json
  File(
    '${currentDir.path}/package.json',
  ).writeAsStringSync(packageJsonTemplate);
  print('Created: package.json');

  // Create tsconfig.json
  File('${currentDir.path}/tsconfig.json').writeAsStringSync(tsconfigTemplate);
  print('Created: tsconfig.json');
}
