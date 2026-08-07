import 'package:coverage_treemap_shared/lcov.dart';
import 'package:test/test.dart';

const _sample = '''
SF:lib/src/parser.dart
DA:1,4
DA:2,0
DA:3,1
LF:3
LH:2
end_of_record
SF:lib/src/render/painter.dart
DA:10,0
DA:11,0
LF:2
LH:0
end_of_record
SF:lib/main.dart
DA:1,7
LF:1
LH:1
end_of_record
''';

void main() {
  group('parseLcov', () {
    test('parses per-file line hit maps', () {
      final report = parseLcov(_sample);
      expect(report.files, hasLength(3));
      final parser = report.files.singleWhere(
        (file) => file.path == 'lib/src/parser.dart',
      );
      expect(parser.lineHits, {1: 4, 2: 0, 3: 1});
      expect(parser.linesFound, 3);
      expect(parser.linesHit, 2);
    });

    test('computes per-file coverage fractions', () {
      final report = parseLcov(_sample);
      final painter = report.files.singleWhere(
        (file) => file.path == 'lib/src/render/painter.dart',
      );
      expect(painter.coverage, 0.0);
      final main = report.files.singleWhere(
        (file) => file.path == 'lib/main.dart',
      );
      expect(main.coverage, 1.0);
    });

    test('derives LF/LH from DA records when absent', () {
      final report = parseLcov('''
SF:lib/a.dart
DA:1,1
DA:2,0
end_of_record
''');
      final file = report.files.single;
      expect(file.linesFound, 2);
      expect(file.linesHit, 1);
    });

    test('aggregates totals across the report', () {
      final report = parseLcov(_sample);
      expect(report.linesFound, 6);
      expect(report.linesHit, 3);
      expect(report.coverage, 0.5);
    });

    test('groups files into a directory tree with rolled-up coverage', () {
      final report = parseLcov(_sample);
      final root = report.tree;
      expect(root.linesFound, 6);
      expect(root.linesHit, 3);
      final lib = root.directories.singleWhere((d) => d.name == 'lib');
      final src = lib.directories.singleWhere((d) => d.name == 'src');
      expect(src.linesFound, 5);
      expect(src.linesHit, 2);
      expect(src.files.single.name, 'parser.dart');
      final render = src.directories.singleWhere((d) => d.name == 'render');
      expect(render.files.single.name, 'painter.dart');
      expect(lib.files.single.name, 'main.dart');
    });

    test('ignores record kinds it does not consume', () {
      final report = parseLcov('''
TN:
SF:lib/a.dart
FN:1,main
FNDA:3,main
FNF:1
FNH:1
BRDA:1,0,0,1
BRF:1
BRH:1
DA:1,3
end_of_record
''');
      expect(report.files.single.lineHits, {1: 3});
    });

    test('rejects DA outside a file section, naming the line', () {
      expect(
        () => parseLcov('DA:1,1\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('line 1'),
          ),
        ),
      );
    });

    test('rejects malformed DA payloads, naming the payload', () {
      expect(
        () => parseLcov('SF:lib/a.dart\nDA:one,two\nend_of_record\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('DA:one,two'),
          ),
        ),
      );
    });

    test('rejects an unterminated file section', () {
      expect(
        () => parseLcov('SF:lib/a.dart\nDA:1,1\n'),
        throwsA(
          isA<FormatException>().having(
            (e) => e.message,
            'message',
            contains('end_of_record'),
          ),
        ),
      );
    });

    test('an empty report has zero coverage and an empty tree', () {
      final report = parseLcov('');
      expect(report.files, isEmpty);
      expect(report.coverage, 0.0);
      expect(report.tree.directories, isEmpty);
      expect(report.tree.files, isEmpty);
    });
  });
}
