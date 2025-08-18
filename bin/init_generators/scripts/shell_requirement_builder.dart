import 'dart:io';

import '../templates/index.dart';

Future<void> setupShell(Directory currentDir) async {
  // Create scripts directory if it doesn't exist
  final scriptsDir = Directory('${currentDir.path}/scripts');
  if (!scriptsDir.existsSync()) {
    scriptsDir.createSync();
  }

  // Create scripts/compile.sh
  File('${scriptsDir.path}/compile.sh').writeAsStringSync(compileShTemplate);
  if (Platform.isLinux || Platform.isMacOS) {
    await Process.run('chmod', ['+x', '${scriptsDir.path}/compile.sh']);
  } else if (Platform.isWindows) {
    // TODO(chris): check if this is even correct
    await Process.run('set', ['+x', '${scriptsDir.path}/compile.sh']);
  }
  print('Created: scripts/compile.sh');
}
