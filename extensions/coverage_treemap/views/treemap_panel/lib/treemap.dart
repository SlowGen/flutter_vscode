/// Squarified treemap layout and rendering for coverage nodes.
library;

import 'dart:math' as math;

import 'package:coverage_treemap_shared/view_contract.dart';
import 'package:flutter/material.dart';

// The red-amber-green coverage ramp is data encoding, not chrome: it
// stays fixed across VS Code themes so a tile's color always means the
// same coverage.
const _lowColor = Color(0xFFB54533);
const _midColor = Color(0xFFBD8628);
const _highColor = Color(0xFF35793D);

/// Tile label color. Labels sit on the fixed coverage ramp rather than
/// on theme chrome, so they keep a fixed light color that reads on all
/// three ramp stops in every VS Code theme.
const _labelColor = Color(0xFFF2F2F2);

/// One coverage node laid out as a rectangle by [squarify].
final class TreemapTile {
  /// Creates a laid-out tile.
  const TreemapTile({required this.node, required this.rect});

  /// The coverage node this tile represents.
  final CoverageNode node;

  /// The tile's rectangle inside the treemap's coordinate space.
  final Rect rect;
}

typedef _RowEntry = ({double area, CoverageNode node});

/// Lays out the measurable [nodes] inside [size] with the classic squarified
/// treemap algorithm (Bruls, Huizing, and van Wijk).
///
/// Nodes without instrumented lines are skipped; every remaining tile's area
/// is proportional to its node's `linesFound`.
List<TreemapTile> squarify(List<CoverageNode> nodes, Size size) {
  final visible = [
    for (final node in nodes)
      if (node.linesFound > 0) node,
  ]..sort((a, b) => b.linesFound.compareTo(a.linesFound));
  if (visible.isEmpty || size.width <= 0 || size.height <= 0) {
    return const [];
  }
  final totalLines = visible.fold<int>(0, (sum, node) => sum + node.linesFound);
  final scale = size.width * size.height / totalLines;
  final entries = <_RowEntry>[
    for (final node in visible) (area: node.linesFound * scale, node: node),
  ];
  final tiles = <TreemapTile>[];
  var remaining = Offset.zero & size;
  var index = 0;
  while (index < entries.length) {
    if (remaining.width <= 0 || remaining.height <= 0) {
      break;
    }
    final side = math.min(remaining.width, remaining.height);
    final maxArea = entries[index].area;
    var count = 1;
    var sum = maxArea;
    var minArea = maxArea;
    var worst = _worstAspect(maxArea, minArea, sum, side);
    while (index + count < entries.length) {
      final nextArea = entries[index + count].area;
      final nextMin = math.min(minArea, nextArea);
      final nextSum = sum + nextArea;
      final nextWorst = _worstAspect(maxArea, nextMin, nextSum, side);
      if (nextWorst > worst) {
        break;
      }
      count += 1;
      sum = nextSum;
      minArea = nextMin;
      worst = nextWorst;
    }
    remaining = _layoutRow(
      entries.sublist(index, index + count),
      sum,
      remaining,
      tiles,
    );
    index += count;
  }
  return tiles;
}

/// The worst (largest) tile aspect ratio a row would have when laid along a
/// side of length [side] with the given per-tile area extremes and row [sum].
double _worstAspect(double maxArea, double minArea, double sum, double side) {
  final sumSquared = sum * sum;
  final sideSquared = side * side;
  return math.max(
    sideSquared * maxArea / sumSquared,
    sumSquared / (sideSquared * minArea),
  );
}

/// Lays one row of tiles along the shorter side of [remaining], appends the
/// resulting tiles to [tiles], and returns the rectangle left over.
Rect _layoutRow(
  List<_RowEntry> row,
  double sum,
  Rect remaining,
  List<TreemapTile> tiles,
) {
  if (remaining.width >= remaining.height) {
    final stripWidth = sum / remaining.height;
    var top = remaining.top;
    for (final entry in row) {
      final height = entry.area / stripWidth;
      tiles.add(
        TreemapTile(
          node: entry.node,
          rect: Rect.fromLTWH(remaining.left, top, stripWidth, height),
        ),
      );
      top += height;
    }
    return Rect.fromLTRB(
      remaining.left + stripWidth,
      remaining.top,
      remaining.right,
      remaining.bottom,
    );
  }
  final stripHeight = sum / remaining.width;
  var left = remaining.left;
  for (final entry in row) {
    final width = entry.area / stripHeight;
    tiles.add(
      TreemapTile(
        node: entry.node,
        rect: Rect.fromLTWH(left, remaining.top, width, stripHeight),
      ),
    );
    left += width;
  }
  return Rect.fromLTRB(
    remaining.left,
    remaining.top + stripHeight,
    remaining.right,
    remaining.bottom,
  );
}

/// Maps a [coverage] fraction in `[0, 1]` to a red-amber-green tile color.
Color coverageColor(double coverage) {
  final t = coverage.clamp(0, 1).toDouble();
  return t < 0.5
      ? Color.lerp(_lowColor, _midColor, t * 2)!
      : Color.lerp(_midColor, _highColor, (t - 0.5) * 2)!;
}

/// Formats a [coverage] fraction in `[0, 1]` as a percent label.
String coveragePercent(double coverage, {int decimals = 0}) =>
    '${(coverage * 100).toStringAsFixed(decimals)}%';

/// An interactive squarified treemap over one directory's children.
class TreemapView extends StatelessWidget {
  /// Creates a treemap over [nodes] that reports taps through [onNodeTap].
  const TreemapView({required this.nodes, required this.onNodeTap, super.key});

  /// The children of the directory currently in view.
  final List<CoverageNode> nodes;

  /// Called with the tapped tile's node.
  final ValueChanged<CoverageNode> onNodeTap;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tiles = squarify(nodes, constraints.biggest);
        return ColoredBox(
          // The editor background doubles as the gap color between
          // tiles, so the treemap sits directly on the host theme.
          color: Theme.of(context).scaffoldBackgroundColor,
          child: Stack(
            children: [
              for (final tile in tiles)
                Positioned.fromRect(
                  rect: tile.rect,
                  child: _TreemapTileView(tile: tile, onNodeTap: onNodeTap),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _TreemapTileView extends StatelessWidget {
  const _TreemapTileView({required this.tile, required this.onNodeTap});

  final TreemapTile tile;
  final ValueChanged<CoverageNode> onNodeTap;

  @override
  Widget build(BuildContext context) {
    final node = tile.node;
    final displayName = node.isFile ? node.name : '${node.name}/';
    final percent = coveragePercent(node.coverage);
    final showLabel = tile.rect.width >= 56 && tile.rect.height >= 24;
    final twoLines = showLabel && tile.rect.height >= 44;
    return Tooltip(
      message:
          '$displayName ${coveragePercent(node.coverage, decimals: 1)} '
          'covered (${node.linesHit}/${node.linesFound} lines)',
      waitDuration: const Duration(milliseconds: 400),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: () => onNodeTap(node),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: coverageColor(node.coverage),
              border: Border.all(
                color: Theme.of(context).scaffoldBackgroundColor,
              ),
            ),
            child: showLabel
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 3,
                    ),
                    child: Align(
                      alignment: Alignment.topLeft,
                      child: Text(
                        twoLines
                            ? '$displayName\n$percent'
                            : '$displayName $percent',
                        maxLines: twoLines ? 2 : 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: _labelColor,
                          fontSize: 11,
                          height: 1.3,
                        ),
                      ),
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }
}
