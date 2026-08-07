import 'dart:io';

import 'package:flutter_vscode/src/cli/build_receipt.dart';
import 'package:test/test.dart';

void main() {
  test(
    'tool digest changes when a transitive generator source changes',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'flutter_vscode_tool_identity_',
      );
      addTearDown(() => root.delete(recursive: true));
      final generator = Directory(
        '${root.path}/tool/binding_generator',
      )..createSync(recursive: true);
      File('${generator.path}/generator.dart').writeAsStringSync(
        "import 'ecmascript_whitespace.dart';\n",
      );
      final helper = File('${generator.path}/ecmascript_whitespace.dart')
        ..writeAsStringSync("const trimRule = 'first';\n");

      final before = await digestPackagePaths(
        packageRoot: root,
        relativePaths: const ['tool/binding_generator'],
      );
      helper.writeAsStringSync("const trimRule = 'second';\n");
      final after = await digestPackagePaths(
        packageRoot: root,
        relativePaths: const ['tool/binding_generator'],
      );

      expect(after, isNot(before));
    },
  );
}
