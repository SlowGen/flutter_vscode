import 'package:coverage_treemap_shared/lcov.dart';
import 'package:coverage_treemap_shared/view_contract.dart';
import 'package:dart_vscode/view_protocol.dart';
import 'package:test/test.dart';

void main() {
  group('coverage snapshot schema', () {
    test('round-trips a report-derived snapshot', () {
      final report = parseLcov('''
SF:lib/src/a.dart
DA:1,1
DA:2,0
end_of_record
SF:lib/b.dart
DA:1,3
end_of_record
''');
      final snapshot = CoverageSnapshot.fromReport(
        'coverage/lcov.info',
        report,
      );
      final decoded = coverageSnapshotSchema.decode(
        coverageSnapshotSchema.encode(snapshot),
      );
      expect(decoded.lcovPath, 'coverage/lcov.info');
      expect(decoded.root.linesFound, 3);
      expect(decoded.root.linesHit, 2);
      final lib = decoded.root.children.single;
      expect(lib.name, 'lib');
      expect(lib.children, hasLength(2));
      final src = lib.children.singleWhere((node) => node.name == 'src');
      expect(src.isFile, isFalse);
      expect(src.children.single.name, 'a.dart');
      expect(src.children.single.isFile, isTrue);
      expect(src.coverage, 0.5);
    });

    test('decode rejects payloads with missing or extra keys by name', () {
      expect(
        () => coverageSnapshotSchema.decode(<Object?, Object?>{
          'lcovPath': 'x',
        }),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"root"'),
          ),
        ),
      );
      final valid =
          coverageSnapshotSchema.encode(
                const CoverageSnapshot(
                  lcovPath: 'coverage/lcov.info',
                  root: CoverageNode(name: '', linesFound: 0, linesHit: 0),
                ),
              )!
              as Map<String, Object?>;
      expect(
        () => coverageSnapshotSchema.decode({...valid, 'extra': 1}),
        throwsA(
          isA<FormatException>().having(
            (error) => error.message,
            'message',
            contains('"extra"'),
          ),
        ),
      );
    });
  });

  group('theme report schema', () {
    test('round-trips a report with and without a background', () {
      final full = themeReportSchema.decode(
        themeReportSchema.encode(
          const ThemeReport(kind: 'dark', editorBackground: 0xFF1E1E1E),
        ),
      );
      expect(full.kind, 'dark');
      expect(full.editorBackground, 0xFF1E1E1E);

      final bare = themeReportSchema.decode(
        themeReportSchema.encode(const ThemeReport(kind: 'highContrast')),
      );
      expect(bare.kind, 'highContrast');
      expect(bare.editorBackground, isNull);
    });

    test('decode rejects malformed payloads', () {
      expect(() => themeReportSchema.decode(null), throwsFormatException);
      expect(
        () => themeReportSchema.decode(<Object?, Object?>{'kind': 'dark'}),
        throwsFormatException,
      );
      expect(
        () => themeReportSchema.decode(<Object?, Object?>{
          'kind': 42,
          'editorBackground': null,
        }),
        throwsFormatException,
      );
      expect(
        () => themeReportSchema.decode(<Object?, Object?>{
          'kind': 'dark',
          'editorBackground': 'red',
        }),
        throwsFormatException,
      );
      expect(
        () => themeReportSchema.decode(<Object?, Object?>{
          'kind': 'dark',
          'editorBackground': null,
          'extra': true,
        }),
        throwsFormatException,
      );
    });
  });

  group('assembled operations', () {
    test('the shared package owns the one declaration of each operation', () {
      // Host and view import these instead of assembling twins; a
      // session round trip is proven by the framework's schema suite
      // and the real-host gate.
      expect(snapshotOperation, isNotNull);
      expect(themeReportOperation, isNotNull);
      expect(pushReceivedOperation, isNotNull);
    });

    test('the push acknowledgement payload is a bare int', () {
      expect(ViewValueKind.integer.encode(41), 41);
      expect(ViewValueKind.integer.decode(41), 41);
      expect(
        () => ViewValueKind.integer.decode('41'),
        throwsFormatException,
      );
    });
  });
}
