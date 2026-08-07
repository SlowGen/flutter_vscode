import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_lens_shared/registry.dart';
import 'package:test/test.dart';

void main() {
  group('parsePackageInfo', () {
    test('reads the pub.dev package response shape', () {
      const body = '''
{
  "name": "yaml",
  "latest": {
    "version": "3.1.3",
    "pubspec": {
      "name": "yaml",
      "description": "A parser for YAML, a human-friendly data format."
    }
  }
}
''';
      final info = parsePackageInfo(body);

      expect(info.latest, Version(3, 1, 3));
      expect(
        info.description,
        'A parser for YAML, a human-friendly data format.',
      );
    });

    test('tolerates a missing description', () {
      final info = parsePackageInfo(
        '{"name": "terse", "latest": {"version": "1.0.0", "pubspec": {}}}',
      );

      expect(info.latest, Version(1, 0, 0));
      expect(info.description, isNull);
    });

    test('throws an actionable FormatException on non-JSON bodies', () {
      expect(
        () => parsePackageInfo('<html>offline portal</html>'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('package'),
          ),
        ),
      );
    });

    test('throws when the body is not a JSON object', () {
      expect(
        () => parsePackageInfo('[1, 2, 3]'),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when latest.version is absent', () {
      expect(
        () => parsePackageInfo('{"name": "hollow", "latest": {}}'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('latest'),
          ),
        ),
      );
    });

    test('throws when latest.version is not a semantic version', () {
      expect(
        () => parsePackageInfo(
          '{"latest": {"version": "not-a-version"}}',
        ),
        throwsA(isA<FormatException>()),
      );
    });
  });
}
