import 'package:dart_vscode/contributions.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> descriptor() => <String, Object?>{
    'schemaVersion': 1,
    'name': 'my-extension',
    'displayName': 'My Extension',
    'description': 'Demonstrates the manifest projection.',
    'version': '0.1.0',
    'publisher': 'example',
    'activationEvents': <Object?>['onStartupFinished'],
  };

  test('a valid descriptor projects into the pinned manifest form', () {
    final manifest = ManifestProjection.fromProjectDescriptor(descriptor());

    expect(manifest.extensionId, 'example.my-extension');
    final json = manifest.toManifestJson(main: './out/bootstrap.cjs');
    expect(json['name'], 'my-extension');
    expect(json['engines'], <String, Object?>{'vscode': vscodeApiVersion});
    expect(json['main'], './out/bootstrap.cjs');
    expect(json.containsKey('contributes'), isFalse);
  });

  test('contributions assemble under the contributes key', () {
    final project = descriptor()
      ..['commands'] = <Object?>[
        <String, Object?>{'command': 'my.command', 'title': 'Run'},
      ]
      ..['viewsContainers'] = <String, Object?>{
        'activitybar': <Object?>[
          <String, Object?>{
            'id': 'myContainer',
            'title': 'Mine',
            'icon': 'icon.svg',
          },
        ],
      }
      ..['views'] = <String, Object?>{
        'myContainer': <Object?>[
          <String, Object?>{
            'id': 'my.view',
            'name': 'Things',
            'icon': r'$(package)',
          },
        ],
      };

    final json = ManifestProjection.fromProjectDescriptor(
      project,
    ).toManifestJson(main: './out/bootstrap.cjs');

    final contributes = json['contributes']! as Map<String, Object?>;
    expect(contributes.keys, ['commands', 'viewsContainers', 'views']);
  });

  test('platform admission failures carry stable diagnostic codes', () {
    final cases = <Map<String, Object?>, String>{
      (descriptor()..['name'] = 'My Extension'): 'INVALID_PROJECT_MANIFEST',
      (descriptor()..['version'] = 'not-semver'): 'INVALID_PROJECT_MANIFEST',
      (descriptor()..['unknown'] = true): 'INVALID_PROJECT_DESCRIPTOR',
      (descriptor()..['schemaVersion'] = 2): 'INVALID_PROJECT_DESCRIPTOR',
      (descriptor()
            ..['views'] = <String, Object?>{
              'nowhere': <Object?>[
                <String, Object?>{'id': 'v', 'name': 'V', 'icon': 'i.svg'},
              ],
            }):
          'INVALID_PROJECT_MANIFEST',
    };

    for (final entry in cases.entries) {
      expect(
        () => ManifestProjection.fromProjectDescriptor(entry.key),
        throwsA(
          isA<ContributionException>().having(
            (error) => error.code,
            'code',
            entry.value,
          ),
        ),
        reason: 'descriptor: ${entry.key}',
      );
    }
  });

  test('a whitespace-only view id is rejected, a whitespace title is not', () {
    // VS Code's own admission treats a whitespace container id as an error
    // but a whitespace container title as only a warning; the projection
    // matches the platform instead of exceeding it.
    final badId = descriptor()
      ..['viewsContainers'] = <String, Object?>{
        'activitybar': <Object?>[
          <String, Object?>{'id': ' ', 'title': 'Mine', 'icon': 'i.svg'},
        ],
      };
    expect(
      () => ManifestProjection.fromProjectDescriptor(badId),
      throwsA(isA<ContributionException>()),
    );

    final whitespaceTitle = descriptor()
      ..['viewsContainers'] = <String, Object?>{
        'activitybar': <Object?>[
          <String, Object?>{'id': 'ok', 'title': ' ', 'icon': 'i.svg'},
        ],
      };
    expect(
      ManifestProjection.fromProjectDescriptor(whitespaceTitle).viewsContainers,
      isNotEmpty,
    );
  });
}
