import 'dart:io';

import '../templates/index.dart';

void setupWeb(Directory currentDir) {
  // Create web directory if it doesn't exist
  final webDir = Directory('${currentDir.path}/web');
  if (!webDir.existsSync()) {
    webDir.createSync();
  }

  // Create web/index.html
  File('${webDir.path}/index.html').writeAsStringSync(webIndexTemplate);
  print('Created: web/index.html');

  // Create web/flutter_bootstrap.js
  File(
    '${webDir.path}/flutter_bootstrap.js',
  ).writeAsStringSync(flutterBootstrapJsTemplate);
  print('Created: web/flutter_bootstrap.js');
}
