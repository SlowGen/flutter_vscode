import 'package:coverage_treemap_shared/view_contract.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treemap_panel/drilldown.dart';

CoverageNode dir(
  String name, {
  int linesFound = 10,
  int linesHit = 5,
  List<CoverageNode> children = const [],
}) => CoverageNode(
  name: name,
  linesFound: linesFound,
  linesHit: linesHit,
  children: children,
);

CoverageNode file(String name, {int linesFound = 10, int linesHit = 5}) =>
    CoverageNode(
      name: name,
      linesFound: linesFound,
      linesHit: linesHit,
      isFile: true,
    );

void main() {
  group('descendSingleChildChain', () {
    test('descends through multiple single-directory levels', () {
      final leaf = dir(
        'src',
        children: [file('a.dart'), file('b.dart')],
      );
      final mid = dir('lib', children: [leaf]);
      final root = dir('root', children: [mid]);

      final path = descendSingleChildChain([root]);

      expect(path.map((node) => node.name), ['root', 'lib', 'src']);
    });

    test('stops when a directory has a file sibling', () {
      final sub = dir('lib', children: [file('a.dart')]);
      final root = dir('root', children: [sub, file('main.dart')]);

      final path = descendSingleChildChain([root]);

      expect(path.map((node) => node.name), ['root']);
    });

    test('ignores zero-linesFound children when counting', () {
      final covered = dir('lib', children: [file('a.dart'), file('b.dart')]);
      final uncovered = dir('generated', linesFound: 0, linesHit: 0);
      final root = dir('root', children: [uncovered, covered]);

      final path = descendSingleChildChain([root]);

      expect(path.map((node) => node.name), ['root', 'lib']);
    });

    test('does not descend into a lone file child', () {
      final root = dir('root', children: [file('main.dart')]);

      final path = descendSingleChildChain([root]);

      expect(path.map((node) => node.name), ['root']);
    });
  });

  group('rebasePath', () {
    test('keeps the deepest surviving prefix by name and re-descends', () {
      final oldSrc = dir('src', children: [file('a.dart')]);
      final oldLib = dir('lib', children: [oldSrc, file('main.dart')]);
      final oldRoot = dir('root', children: [oldLib]);
      final previousPath = [oldRoot, oldLib, oldSrc];

      final newInner = dir('inner', children: [file('c.dart'), file('d.dart')]);
      final newSrc = dir('src', children: [newInner]);
      final newLib = dir('lib', children: [newSrc, file('main.dart')]);
      final newRoot = dir('root', children: [newLib]);

      final path = rebasePath(newRoot: newRoot, previousPath: previousPath);

      // The lib > src prefix survives by name, then the lone `inner`
      // directory triggers a fresh auto-descent.
      expect(path.map((node) => node.name), ['root', 'lib', 'src', 'inner']);
      expect(path[1], same(newLib));
      expect(path[2], same(newSrc));
    });

    test('falls back to the new root when the old names vanish', () {
      final oldLib = dir('lib', children: [file('a.dart')]);
      final oldRoot = dir('root', children: [oldLib]);
      final previousPath = [oldRoot, oldLib];

      final newRoot = dir(
        'root',
        children: [
          dir('packages', children: [file('b.dart')]),
          file('main.dart'),
        ],
      );

      final path = rebasePath(newRoot: newRoot, previousPath: previousPath);

      expect(path.map((node) => node.name), ['root']);
      expect(path.single, same(newRoot));
    });

    test('stays put on an empty root', () {
      final oldRoot = dir('root', children: [file('a.dart')]);
      final newRoot = dir('root', linesFound: 0, linesHit: 0);

      final path = rebasePath(newRoot: newRoot, previousPath: [oldRoot]);

      expect(path.single, same(newRoot));
    });
  });
}
