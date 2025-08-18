import 'dart:io';

import '../templates/index.dart';

void createExample(Directory currentDir) {
  // Get lib directory
  final libDir = Directory('${currentDir.path}/lib');

  if (!libDir.existsSync()) {
    throw Exception(
      'Please ensure a Flutter project has been created. The lib directory was not found',
    );
  }
  // Create api_controller.dart
  File(
    '${libDir.path}/api_controller.dart',
  ).writeAsStringSync(apiControllerTemplate);
  print('Created: lib/api_controller.dart');
}
