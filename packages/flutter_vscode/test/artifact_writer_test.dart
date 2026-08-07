import 'dart:io';

import 'package:flutter_vscode/src/cli/artifact_writer.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test(
    'writes every Project-Derived Artifact beneath the output root',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'flutter_vscode_artifact_writer_',
      );
      addTearDown(() => root.delete(recursive: true));

      await writeProjectArtifacts(
        {
          'host/lib/generated/example.g.dart': 'generated dart\n',
          'package.json': '{}\n',
        },
        root,
      );

      expect(
        await File(
          p.join(root.path, 'host/lib/generated/example.g.dart'),
        ).readAsString(),
        'generated dart\n',
      );
      expect(
        await File(p.join(root.path, 'package.json')).readAsString(),
        '{}\n',
      );
    },
  );
}
