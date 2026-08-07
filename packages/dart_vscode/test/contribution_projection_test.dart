/// The author-data admission suite: every rejection and projection here
/// mirrors the pinned platform's own extension-manifest semantics, ported
/// from the generator-era suite when contribution processing became this
/// package's `contributions` library.
library;

import 'package:dart_vscode/contributions.dart';
import 'package:test/test.dart';

void main() {
  Map<String, Object?> descriptor() => <String, Object?>{
    'schemaVersion': 1,
    'name': 'fixture',
    'displayName': 'Fixture',
    'description': 'Fixture.',
    'version': '0.0.0',
    'publisher': 'test',
    'activationEvents': <Object?>[],
  };

  Matcher throwsContribution(String code, dynamic messageMatcher) => throwsA(
    isA<ContributionException>()
        .having((error) => error.code, 'code', code)
        .having((error) => error.message, 'message', messageMatcher),
  );

  test('enforces the framework-safe extension identifier grammar', () {
    expect(
      ManifestProjection.fromProjectDescriptor(
        descriptor()
          ..['name'] = 'my-extension2'
          ..['publisher'] = 'test-publisher3',
      ).extensionId,
      'test-publisher3.my-extension2',
    );

    for (final invalid in <(String, String)>[
      ('name', '../../outside'),
      ('name', '_starts_wrong'),
      ('name', 'contains.dot'),
      ('name', 'Contains-Uppercase'),
      ('publisher', '../publisher'),
      ('publisher', '-starts-wrong'),
      ('publisher', 'contains_underscore'),
      ('publisher', 'Contains-Uppercase'),
    ]) {
      expect(
        () => ManifestProjection.fromProjectDescriptor(
          descriptor()..[invalid.$1] = invalid.$2,
        ),
        throwsContribution(
          'INVALID_PROJECT_MANIFEST',
          allOf(contains(invalid.$1), contains(invalid.$2)),
        ),
        reason: '${invalid.$1}=${invalid.$2}',
      );
    }
  });

  test('requires each identity field with the platform admission code', () {
    // Presence is admission, not parse: an author-facing miss must carry
    // the author-facing code, never the maintainer INVALID_GENERATOR_INPUT.
    for (final field in [
      'name',
      'displayName',
      'description',
      'version',
      'publisher',
      'activationEvents',
    ]) {
      expect(
        () => ManifestProjection.fromProjectDescriptor(
          descriptor()..remove(field),
        ),
        throwsContribution(
          'INVALID_PROJECT_MANIFEST',
          contains('project.$field'),
        ),
        reason: field,
      );
    }
  });

  test('defaults schemaVersion the way the typed descriptor does', () {
    // The Dart descriptor constructor declares `schemaVersion = 1`; an
    // absent key admits as revision 1 on the JSON path too.
    final manifest = ManifestProjection.fromProjectDescriptor(
      descriptor()..remove('schemaVersion'),
    );
    expect(manifest.name, 'fixture');
  });

  test('rejects unknown project descriptor fields', () {
    expect(
      () => ManifestProjection.fromProjectDescriptor(
        descriptor()..['contributes'] = <String, Object?>{},
      ),
      throwsContribution('INVALID_PROJECT_DESCRIPTOR', contains('contributes')),
    );
  });

  test('rejects an unsupported project descriptor schema version', () {
    expect(
      () => ManifestProjection.fromProjectDescriptor(
        descriptor()..['schemaVersion'] = 999,
      ),
      throwsContribution(
        'INVALID_PROJECT_DESCRIPTOR',
        contains('schemaVersion'),
      ),
    );
  });

  test('rejects a manifest version that is not strict SemVer', () {
    expect(
      () => ManifestProjection.fromProjectDescriptor(
        descriptor()..['version'] = '01.02.03',
      ),
      throwsContribution(
        'INVALID_PROJECT_MANIFEST',
        contains('project.version'),
      ),
    );
  });

  test('projects command contributions from Dart-owned project data', () {
    final manifest = ManifestProjection.fromProjectDescriptor(
      descriptor()
        ..['commands'] = <Object?>[
          <String, Object?>{
            'command': 'flutter-vscode.host-test.ping',
            'title': 'Ping Dart Host',
          },
        ],
    ).toManifestJson(main: './out/bootstrap.cjs');

    expect(manifest['contributes'], {
      'commands': [
        {
          'command': 'flutter-vscode.host-test.ping',
          'title': 'Ping Dart Host',
        },
      ],
    });
  });

  test('projects view and configuration contributions from Dart-owned data', () {
    final contributes =
        ManifestProjection.fromProjectDescriptor(
              descriptor()
                ..['viewsContainers'] = <String, Object?>{
                  'activitybar': <Object?>[
                    <String, Object?>{
                      'id': 'fixtureContainer',
                      'title': 'Fixture',
                      'icon': 'media/fixture.svg',
                    },
                  ],
                }
                ..['views'] = <String, Object?>{
                  'fixtureContainer': <Object?>[
                    <String, Object?>{
                      'id': 'fixture.tree',
                      'name': 'Fixture Tree',
                      // The pinned manifest schema requires a view icon, though the
                      // runtime tolerates its absence; the projection follows the
                      // schema.
                      'icon': r'$(list-tree)',
                    },
                  ],
                }
                ..['configuration'] = <String, Object?>{
                  'title': 'Fixture',
                  'properties': <String, Object?>{
                    'fixture.registryUrl': <String, Object?>{
                      'type': 'string',
                      'default': 'https://pub.dev',
                      'description':
                          'Registry queried for the latest versions.',
                    },
                  },
                },
            ).toManifestJson(main: './out/bootstrap.cjs')['contributes']!
            as Map<String, Object?>;

    expect(contributes['viewsContainers'], {
      'activitybar': [
        {
          'id': 'fixtureContainer',
          'title': 'Fixture',
          'icon': 'media/fixture.svg',
        },
      ],
    });
    expect(contributes['views'], {
      'fixtureContainer': [
        {'id': 'fixture.tree', 'name': 'Fixture Tree', 'icon': r'$(list-tree)'},
      ],
    });
    expect(contributes['configuration'], {
      'title': 'Fixture',
      'properties': {
        'fixture.registryUrl': {
          'type': 'string',
          'default': 'https://pub.dev',
          'description': 'Registry queried for the latest versions.',
        },
      },
    });
  });

  test('rejects contribution strings the pinned host rejects', () {
    final broken = <Map<String, Object?>>[
      descriptor()
        ..['viewsContainers'] = <String, Object?>{
          'activitybar': <Object?>[
            <String, Object?>{'id': ' \t', 'title': 'F', 'icon': 'i.svg'},
          ],
        },
      descriptor()
        ..['configuration'] = <String, Object?>{
          'properties': <String, Object?>{
            // The pinned schema's propertyNames pattern is \S+: a name
            // with no non-whitespace character is unregisterable.
            ' \t': <String, Object?>{'type': 'string'},
          },
        },
    ];
    for (final project in broken) {
      expect(
        () => ManifestProjection.fromProjectDescriptor(project),
        throwsA(
          isA<ContributionException>().having(
            (error) => error.code,
            'code',
            'INVALID_PROJECT_MANIFEST',
          ),
        ),
        reason:
            'VS Code drops whitespace-only ids and names at runtime; '
            'admission must fail closed instead of shipping a dead view',
      );
    }
  });

  test('rejects a command entry missing its title', () {
    // Nested presence coverage moved here when the Dart-descriptor parse
    // stopped mirroring constructor shapes.
    expect(
      () => ManifestProjection.fromProjectDescriptor(
        descriptor()
          ..['commands'] = <Object?>[
            <String, Object?>{'command': 'test.fixture.ping'},
          ],
      ),
      throwsA(
        isA<ContributionException>().having(
          (error) => error.message,
          'message',
          contains('project.commands entry.title'),
        ),
      ),
    );
  });

  test('rejects whitespace-only required command contribution strings', () {
    for (final field in ['command', 'title']) {
      expect(
        () => ManifestProjection.fromProjectDescriptor(
          descriptor()
            ..['commands'] = <Object?>[
              <String, Object?>{
                'command': 'test.fixture.ping',
                'title': 'Ping Dart Host',
                field: ' \t\n',
              },
            ],
        ),
        throwsContribution(
          'INVALID_PROJECT_MANIFEST',
          allOf(contains(field), contains('whitespace')),
        ),
        reason: field,
      );
    }
  });

  test('uses the projected ECMAScript trim predicate for required strings', () {
    // U+0085 is Dart whitespace but not ECMAScript trim whitespace: the
    // pinned host accepts it, so admission must too.
    final commands = ManifestProjection.fromProjectDescriptor(
      descriptor()
        ..['commands'] = <Object?>[
          <String, Object?>{'command': 'test.fixture.ping', 'title': '\u0085'},
        ],
    ).commands;
    expect(commands.single['title'], '');

    expect(
      () => ManifestProjection.fromProjectDescriptor(
        descriptor()
          ..['commands'] = <Object?>[
            <String, Object?>{
              'command': 'test.fixture.ping',
              'title': '\uFEFF',
            },
          ],
      ),
      throwsA(
        isA<ContributionException>().having(
          (error) => error.code,
          'code',
          'INVALID_PROJECT_MANIFEST',
        ),
      ),
    );
  });

  test(
    'accepts empty optional command strings allowed by the pinned validator',
    () {
      final commands = <Object?>[
        <String, Object?>{
          'command': 'test.fixture.first',
          'title': 'First',
          'shortTitle': '',
          'category': '',
          'enablement': '',
          'icon': '',
        },
        <String, Object?>{
          'command': 'test.fixture.second',
          'title': 'Second',
          'icon': <String, Object?>{'dark': '', 'light': ''},
        },
      ];
      final manifest = ManifestProjection.fromProjectDescriptor(
        descriptor()..['commands'] = commands,
      ).toManifestJson(main: './out/bootstrap.cjs');

      expect(
        (manifest['contributes']! as Map<String, Object?>)['commands'],
        commands,
      );
    },
  );

  test('rejects command icon objects without both theme paths', () {
    for (final lonePath in ['dark', 'light']) {
      expect(
        () => ManifestProjection.fromProjectDescriptor(
          descriptor()
            ..['commands'] = <Object?>[
              <String, Object?>{
                'command': 'test.fixture.ping',
                'title': 'Ping Dart Host',
                'icon': <String, Object?>{lonePath: 'icons/ping.svg'},
              },
            ],
        ),
        throwsContribution(
          'INVALID_PROJECT_MANIFEST',
          allOf(contains('icon'), contains('dark'), contains('light')),
        ),
        reason: lonePath,
      );
    }
  });

  test('emits a complete manifest from project data and the pinned engine', () {
    final manifest = ManifestProjection.fromProjectDescriptor(
      descriptor(),
    ).toManifestJson(main: './out/bootstrap.cjs');

    expect(manifest, <String, Object?>{
      'name': 'fixture',
      'displayName': 'Fixture',
      'description': 'Fixture.',
      'version': '0.0.0',
      'publisher': 'test',
      'engines': <String, Object?>{'vscode': '1.129.1'},
      'main': './out/bootstrap.cjs',
      'activationEvents': <String>[],
    });
  });
}
