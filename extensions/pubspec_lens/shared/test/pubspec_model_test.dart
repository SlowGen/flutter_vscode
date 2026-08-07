import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_lens_shared/pubspec_model.dart';
import 'package:test/test.dart';

const _pubspec = '''
name: sample
environment:
  sdk: ^3.12.0

dependencies:
  yaml: ^3.1.0
  http: 1.2.0
  flutter:
    sdk: flutter
  local_dep:
    path: ../local_dep
  forked_dep:
    git: https://example.com/forked_dep.git

dev_dependencies:
  test: ^1.25.0
''';

void main() {
  group('parsePubspec', () {
    test('reads hosted dependencies with constraints', () {
      final dependencies = parsePubspec(_pubspec);
      final yaml = dependencies.singleWhere((d) => d.name == 'yaml');

      expect(yaml.source, DependencySource.hosted);
      expect(yaml.isHosted, isTrue);
      expect(yaml.isDev, isFalse);
      expect(yaml.constraintText, '^3.1.0');
      expect(yaml.constraint, VersionConstraint.parse('^3.1.0'));
    });

    test('reads exact pins as hosted constraints', () {
      final http = parsePubspec(_pubspec).singleWhere((d) => d.name == 'http');

      expect(http.source, DependencySource.hosted);
      expect(http.constraintText, '1.2.0');
      expect(http.constraint!.allows(Version(1, 2, 0)), isTrue);
      expect(http.constraint!.allows(Version(1, 2, 1)), isFalse);
    });

    test('flags dev_dependencies', () {
      final dependencies = parsePubspec(_pubspec);
      final dev = dependencies.singleWhere((d) => d.name == 'test');

      expect(dev.isDev, isTrue);
      expect(dev.source, DependencySource.hosted);
      expect(dev.constraintText, '^1.25.0');
    });

    test('classifies sdk, path, and git dependencies as non-hosted', () {
      final dependencies = parsePubspec(_pubspec);

      expect(
        dependencies.singleWhere((d) => d.name == 'flutter').source,
        DependencySource.sdk,
      );
      expect(
        dependencies.singleWhere((d) => d.name == 'local_dep').source,
        DependencySource.path,
      );
      expect(
        dependencies.singleWhere((d) => d.name == 'forked_dep').source,
        DependencySource.git,
      );
      for (final name in ['flutter', 'local_dep', 'forked_dep']) {
        expect(
          dependencies.singleWhere((d) => d.name == name).isHosted,
          isFalse,
          reason: '$name never gets a registry lookup',
        );
      }
    });

    test('reads a git dependency declared as a map', () {
      final dependencies = parsePubspec('''
dependencies:
  pinned:
    git:
      url: https://example.com/pinned.git
      ref: v1
''');

      expect(dependencies.single.source, DependencySource.git);
    });

    test('reads a hosted-map dependency with its version constraint', () {
      final dependencies = parsePubspec('''
dependencies:
  mirrored:
    hosted: https://mirror.example.com
    version: ^2.0.0
''');
      final mirrored = dependencies.single;

      expect(mirrored.source, DependencySource.hosted);
      expect(mirrored.constraintText, '^2.0.0');
    });

    test('treats a bare entry as any-version hosted', () {
      final dependencies = parsePubspec('''
dependencies:
  anything:
''');
      final anything = dependencies.single;

      expect(anything.source, DependencySource.hosted);
      expect(anything.constraintText, isNull);
      expect(anything.constraintSpan, isNull);
      expect(anything.constraint, VersionConstraint.any);
    });

    test('keeps an unparsable constraint as unknown, not a crash', () {
      final dependencies = parsePubspec('''
dependencies:
  typo: banana
''');
      final typo = dependencies.single;

      expect(typo.source, DependencySource.hosted);
      expect(typo.constraintText, 'banana');
      expect(typo.constraint, isNull);
    });

    test('reports zero-based name and constraint spans', () {
      // Line 0: `dependencies:`; line 1: `  old_pkg: ^0.9.0`.
      final dependencies = parsePubspec('''
dependencies:
  old_pkg: ^0.9.0
''');
      final oldPkg = dependencies.single;

      expect(oldPkg.nameSpan.startLine, 1);
      expect(oldPkg.nameSpan.startColumn, 2);
      expect(oldPkg.nameSpan.endLine, 1);
      expect(oldPkg.nameSpan.endColumn, 9);
      expect(oldPkg.constraintSpan, isNotNull);
      expect(oldPkg.constraintSpan!.startLine, 1);
      expect(oldPkg.constraintSpan!.startColumn, 11);
      expect(oldPkg.constraintSpan!.endLine, 1);
      expect(oldPkg.constraintSpan!.endColumn, 17);
    });

    test('returns no dependencies for a pubspec without dependency keys', () {
      expect(parsePubspec('name: bare\n'), isEmpty);
    });

    test('throws an actionable FormatException on malformed yaml', () {
      expect(
        () => parsePubspec('dependencies:\n  bad: [unclosed\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('pubspec.yaml'),
          ),
        ),
      );
    });

    test('throws when the document is not a map', () {
      expect(
        () => parsePubspec('- not\n- a\n- pubspec\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('map'),
          ),
        ),
      );
    });

    test('throws when a dependency section is not a map', () {
      expect(
        () => parsePubspec('dependencies:\n  - listed\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('dependencies'),
          ),
        ),
      );
    });
  });

  group('verdictFor', () {
    PubspecDependency named(String name) =>
        parsePubspec(_pubspec).singleWhere((d) => d.name == name);

    PubspecDependency only(String entry) =>
        parsePubspec('dependencies:\n  $entry\n').single;

    test('a lower bound trailing the latest version is behind', () {
      // The caret admits 3.1.3, so nothing is blocked — but the pin
      // still trails what the registry publishes, which is the whole
      // point of a dependency lens.
      final verdict = verdictFor(named('yaml'), Version(3, 1, 3));

      expect(verdict.kind, VerdictKind.behind);
      expect(verdict.latest, Version(3, 1, 3));
      expect(verdict.suggestedConstraint, '^3.1.3');
    });

    test('a lower bound at the latest version is current', () {
      final verdict = verdictFor(named('yaml'), Version(3, 1, 0));

      expect(verdict.kind, VerdictKind.current);
      expect(verdict.latest, Version(3, 1, 0));
      expect(verdict.suggestedConstraint, isNull);
    });

    test('a constraint excluding the latest version is outdated', () {
      final verdict = verdictFor(named('http'), Version(2, 0, 0));

      expect(verdict.kind, VerdictKind.outdated);
      expect(verdict.latest, Version(2, 0, 0));
      expect(verdict.suggestedConstraint, '^2.0.0');
    });

    test('an exact pin at the latest version is current', () {
      final verdict = verdictFor(named('http'), Version(1, 2, 0));

      expect(verdict.kind, VerdictKind.current);
      expect(verdict.suggestedConstraint, isNull);
    });

    test('a pin ahead of the registry never suggests a downgrade', () {
      // A constraint above the registry's latest (a mirror lagging, a
      // prerelease pin) excludes the latest version, but rewriting it
      // to `^latest` would walk the pin backwards.
      final verdict = verdictFor(only('ahead: ^2.0.0'), Version(1, 6, 0));

      expect(verdict.kind, VerdictKind.current);
      expect(verdict.suggestedConstraint, isNull);
    });

    test('a hand-written range trailing the latest is behind', () {
      final verdict = verdictFor(
        only("ranged: '>=1.5.0 <2.0.0'"),
        Version(1, 6, 0),
      );

      expect(verdict.kind, VerdictKind.behind);
      expect(verdict.suggestedConstraint, '^1.6.0');
    });

    // Pubspec text cannot express a union (`VersionConstraint.parse`
    // rejects `||`), but the model type can hold one, so the bound is
    // read through the public constructor.
    PubspecDependency holding(VersionConstraint constraint) =>
        PubspecDependency(
          name: 'union_pkg',
          isDev: false,
          source: DependencySource.hosted,
          nameSpan: const SpanLocation(
            startLine: 0,
            startColumn: 2,
            endLine: 0,
            endColumn: 11,
          ),
          constraintText: constraint.toString(),
          constraint: constraint,
        );

    test('a union constraint compares against its lowest bound', () {
      final union = VersionConstraint.unionOf([
        VersionConstraint.parse('^1.0.0'),
        VersionConstraint.parse('^3.0.0'),
      ]);

      final verdict = verdictFor(holding(union), Version(3, 4, 2));

      expect(verdict.kind, VerdictKind.behind);
      expect(verdict.suggestedConstraint, '^3.4.2');
    });

    test('a union sitting entirely ahead of the registry suggests nothing', () {
      final union = VersionConstraint.unionOf([
        VersionConstraint.parse('^4.0.0'),
        VersionConstraint.parse('^5.0.0'),
      ]);

      final verdict = verdictFor(holding(union), Version(3, 0, 0));

      expect(verdict.kind, VerdictKind.current);
      expect(verdict.suggestedConstraint, isNull);
    });

    test('a constraint with no lower bound is behind', () {
      for (final entry in ['loose: any', 'bare:']) {
        final verdict = verdictFor(only(entry), Version(1, 6, 0));

        expect(verdict.kind, VerdictKind.behind, reason: entry);
        expect(verdict.suggestedConstraint, '^1.6.0', reason: entry);
      }
    });

    test('a missing registry answer is unknown', () {
      final verdict = verdictFor(named('yaml'), null);

      expect(verdict.kind, VerdictKind.unknown);
      expect(verdict.suggestedConstraint, isNull);
    });

    test('an unparsable constraint is unknown even with a latest version', () {
      final typo = parsePubspec('''
dependencies:
  typo: banana
''').single;

      expect(verdictFor(typo, Version(1, 0, 0)).kind, VerdictKind.unknown);
    });

    test('non-hosted dependencies are skipped', () {
      for (final name in ['flutter', 'local_dep', 'forked_dep']) {
        final verdict = verdictFor(named(name), Version(9, 9, 9));
        expect(verdict.kind, VerdictKind.skipped, reason: name);
        expect(verdict.suggestedConstraint, isNull, reason: name);
      }
    });
  });
}
