/// fl_chart summary strip for the coverage treemap panel: a covered vs
/// uncovered donut plus a tappable bar chart of the largest children.
library;

import 'package:coverage_treemap_shared/view_contract.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:treemap_panel/treemap.dart';

// Covered/uncovered are the green and red ends of the coverage ramp:
// data encoding, not chrome, so they stay fixed across VS Code themes.
const _coveredColor = Color(0xFF35793D);
const _uncoveredColor = Color(0xFFB54533);

/// The bar chart hides below this strip width so narrow panels keep a
/// clean donut-plus-legend layout.
const _barChartMinWidth = 460.0;

/// How many of the current node's children the bar chart shows.
const _maxBars = 5;

const _chartAnimationDuration = Duration(milliseconds: 250);

/// A compact summary of the coverage [node] currently in view, rendered
/// with fl_chart: a donut of covered vs uncovered lines with the coverage
/// percent in its center and, when the strip is wide enough, a horizontal
/// bar chart of the node's largest children by lines of code.
///
/// Tapping a bar drills into that child through [onChildTap], mirroring
/// the treemap tiles.
class CoverageSummaryStrip extends StatelessWidget {
  /// Creates the strip for [node]; bar taps report through [onChildTap].
  const CoverageSummaryStrip({
    required this.node,
    required this.onChildTap,
    super.key,
  });

  /// The drill-down node currently in view.
  final CoverageNode node;

  /// Called with a tapped bar's node, exactly like a treemap tile tap.
  final ValueChanged<CoverageNode> onChildTap;

  @override
  Widget build(BuildContext context) {
    if (node.linesFound <= 0) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      height: 136,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainer,
        border: Border(
          top: BorderSide(color: theme.dividerColor),
          bottom: BorderSide(color: theme.dividerColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final barNodes = _topChildren(node);
          final showBars =
              constraints.maxWidth >= _barChartMinWidth && barNodes.isNotEmpty;
          return Row(
            children: [
              SizedBox(width: 96, child: _CoverageDonut(node: node)),
              const SizedBox(width: 12),
              if (showBars) ...[
                _CoverageLegend(node: node),
                const SizedBox(width: 16),
                Expanded(
                  child: _TopChildrenBars(
                    nodes: barNodes,
                    onChildTap: onChildTap,
                  ),
                ),
              ] else
                Expanded(child: _CoverageLegend(node: node)),
            ],
          );
        },
      ),
    );
  }
}

/// The measurable children of [node], largest first, capped at [_maxBars].
List<CoverageNode> _topChildren(CoverageNode node) {
  final measurable = [
    for (final child in node.children)
      if (child.linesFound > 0) child,
  ]..sort((a, b) => b.linesFound.compareTo(a.linesFound));
  return measurable.length > _maxBars
      ? measurable.sublist(0, _maxBars)
      : measurable;
}

String _displayName(CoverageNode node) =>
    node.isFile ? node.name : '${node.name}/';

class _CoverageDonut extends StatelessWidget {
  const _CoverageDonut({required this.node});

  final CoverageNode node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final hit = node.linesHit;
    final missed = node.linesFound - node.linesHit;
    return Stack(
      alignment: Alignment.center,
      children: [
        PieChart(
          PieChartData(
            startDegreeOffset: -90,
            sectionsSpace: 2,
            centerSpaceRadius: 30,
            pieTouchData: PieTouchData(enabled: false),
            borderData: FlBorderData(show: false),
            sections: [
              if (hit > 0)
                PieChartSectionData(
                  value: hit.toDouble(),
                  color: _coveredColor,
                  radius: 14,
                  showTitle: false,
                ),
              if (missed > 0)
                PieChartSectionData(
                  value: missed.toDouble(),
                  color: _uncoveredColor,
                  radius: 14,
                  showTitle: false,
                ),
            ],
          ),
          duration: _chartAnimationDuration,
        ),
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              coveragePercent(node.coverage),
              style: TextStyle(
                color: scheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            Text(
              'covered',
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 9),
            ),
          ],
        ),
      ],
    );
  }
}

class _CoverageLegend extends StatelessWidget {
  const _CoverageLegend({required this.node});

  final CoverageNode node;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _LegendEntry(
          color: _coveredColor,
          label: 'Covered',
          value: node.linesHit,
        ),
        const SizedBox(height: 6),
        _LegendEntry(
          color: _uncoveredColor,
          label: 'Uncovered',
          value: node.linesFound - node.linesHit,
        ),
        const SizedBox(height: 6),
        Text(
          '${node.linesFound} lines total',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontSize: 10,
          ),
        ),
      ],
    );
  }
}

class _LegendEntry extends StatelessWidget {
  const _LegendEntry({
    required this.color,
    required this.label,
    required this.value,
  });

  final Color color;
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text.rich(
            TextSpan(
              text: '$label ',
              style: TextStyle(
                color: scheme.onSurfaceVariant,
                fontSize: 11,
              ),
              children: [
                TextSpan(
                  text: '$value',
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _TopChildrenBars extends StatelessWidget {
  const _TopChildrenBars({required this.nodes, required this.onChildTap});

  final List<CoverageNode> nodes;
  final ValueChanged<CoverageNode> onChildTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'LARGEST ITEMS - TAP TO OPEN',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            color: scheme.onSurfaceVariant,
            fontSize: 9,
            letterSpacing: 0.6,
          ),
        ),
        const SizedBox(height: 4),
        Expanded(
          child: BarChart(_barData(scheme), duration: _chartAnimationDuration),
        ),
      ],
    );
  }

  BarChartData _barData(ColorScheme scheme) {
    return BarChartData(
      // One clockwise quarter turn renders the bars horizontally; the
      // (pre-rotation) bottom titles become the left-hand name labels.
      rotationQuarterTurns: 1,
      alignment: BarChartAlignment.spaceAround,
      maxY: nodes.first.linesFound.toDouble(),
      gridData: const FlGridData(show: false),
      borderData: FlBorderData(show: false),
      titlesData: FlTitlesData(
        leftTitles: const AxisTitles(),
        topTitles: const AxisTitles(),
        rightTitles: const AxisTitles(),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 76,
            interval: 1,
            minIncluded: false,
            maxIncluded: false,
            getTitlesWidget: (value, meta) =>
                _buildBarTitle(value, meta, scheme.onSurfaceVariant),
          ),
        ),
      ),
      barTouchData: BarTouchData(
        touchCallback: (event, response) {
          if (event is! FlTapUpEvent) {
            return;
          }
          final index = response?.spot?.touchedBarGroupIndex;
          if (index == null || index < 0 || index >= nodes.length) {
            return;
          }
          onChildTap(nodes[index]);
        },
        mouseCursorResolver: (event, response) => response?.spot == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        touchTooltipData: BarTouchTooltipData(
          getTooltipColor: (group) => scheme.inverseSurface,
          fitInsideHorizontally: true,
          fitInsideVertically: true,
          getTooltipItem: (group, groupIndex, rod, rodIndex) {
            final child = nodes[groupIndex];
            return BarTooltipItem(
              '${_displayName(child)}\n'
              '${coveragePercent(child.coverage, decimals: 1)} covered '
              '(${child.linesHit}/${child.linesFound} lines)',
              TextStyle(color: scheme.onInverseSurface, fontSize: 11),
            );
          },
        ),
      ),
      barGroups: [
        for (var i = 0; i < nodes.length; i++)
          BarChartGroupData(
            x: i,
            barRods: [
              BarChartRodData(
                toY: nodes[i].linesFound.toDouble(),
                width: 12,
                color: _uncoveredColor,
                borderRadius: BorderRadius.circular(2),
                rodStackItems: [
                  BarChartRodStackItem(
                    0,
                    nodes[i].linesHit.toDouble(),
                    _coveredColor,
                  ),
                  BarChartRodStackItem(
                    nodes[i].linesHit.toDouble(),
                    nodes[i].linesFound.toDouble(),
                    _uncoveredColor,
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildBarTitle(double value, TitleMeta meta, Color labelColor) {
    final index = value.toInt();
    if (value != index || index < 0 || index >= nodes.length) {
      return const SizedBox.shrink();
    }
    return SideTitleWidget(
      meta: meta,
      space: 6,
      child: RotatedBox(
        // Undoes the chart's quarter turn so the names read upright.
        quarterTurns: 3,
        child: SizedBox(
          width: 66,
          child: Text(
            _displayName(nodes[index]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.right,
            style: TextStyle(color: labelColor, fontSize: 10),
          ),
        ),
      ),
    );
  }
}
