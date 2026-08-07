import 'package:pub_semver/pub_semver.dart';
import 'package:pubspec_lens_shared/registry.dart';
import 'package:test/test.dart';

void main() {
  group('packageInfoUrl', () {
    test('joins the pub API path onto the registry base', () {
      expect(
        packageInfoUrl('https://pub.dev', 'yaml'),
        'https://pub.dev/api/packages/yaml',
      );
    });

    test('tolerates a trailing slash on the base', () {
      expect(
        packageInfoUrl('https://pub.dev/', 'yaml'),
        'https://pub.dev/api/packages/yaml',
      );
    });

    test('points at gate-style local registries verbatim', () {
      expect(
        packageInfoUrl('http://127.0.0.1:8123', 'old_pkg'),
        'http://127.0.0.1:8123/api/packages/old_pkg',
      );
    });
  });

  group('RegistryCache', () {
    test('misses before a store and hits after', () {
      final cache = RegistryCache();
      expect(cache.contains('yaml'), isFalse);
      expect(cache['yaml'], isNull);

      final info = PackageInfo(latest: Version(3, 1, 3));
      cache.store('yaml', info);

      expect(cache.contains('yaml'), isTrue);
      expect(cache['yaml'], same(info));
    });

    test('clear forgets every stored answer', () {
      final cache = RegistryCache()
        ..store('yaml', PackageInfo(latest: Version(3, 1, 3)))
        ..store('http', PackageInfo(latest: Version(1, 5, 0)))
        ..clear();

      expect(cache.contains('yaml'), isFalse);
      expect(cache.contains('http'), isFalse);
    });
  });
}
