/// Pure drill-down path logic for the coverage treemap view.
///
/// These functions operate on [CoverageNode] paths only — no widget state —
/// so they can be unit-tested without a Flutter runtime.
library;

import 'package:coverage_treemap_shared/view_contract.dart';

/// Auto-descends through directories whose only child is another
/// directory, so the first render shows a spread of tiles instead of
/// one lonely wrapper square (every Dart project funnels through
/// `lib/`). The breadcrumb keeps the full chain navigable.
List<CoverageNode> descendSingleChildChain(List<CoverageNode> path) {
  final result = [...path];
  while (true) {
    final children = result.last.children.where(
      (child) => child.linesFound > 0,
    );
    if (children.length != 1) {
      break;
    }
    final only = children.single;
    if (only.isFile) {
      break;
    }
    result.add(only);
  }
  return result;
}

/// Re-resolves a drill-down [previousPath] against a fresh [newRoot],
/// keeping the deepest prefix whose directory names still exist, then
/// auto-descending via [descendSingleChildChain].
List<CoverageNode> rebasePath({
  required CoverageNode newRoot,
  required List<CoverageNode> previousPath,
}) {
  final path = [newRoot];
  for (final previous in previousPath.skip(1)) {
    CoverageNode? match;
    for (final child in path.last.children) {
      if (!child.isFile && child.name == previous.name) {
        match = child;
        break;
      }
    }
    if (match == null) {
      break;
    }
    path.add(match);
  }
  return descendSingleChildChain(path);
}
