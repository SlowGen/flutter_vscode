/// The typed view-protocol contract between Host Dart and the treemap
/// Flutter View, declared once: each contract type carries a
/// [ViewValueSchema] that derives its codecs, and the assembled
/// [ViewOperation]s live here so host and view import one declaration.
library;

import 'package:coverage_treemap_shared/lcov.dart';
import 'package:dart_vscode/view_protocol.dart';

/// Operation name for requesting the current coverage snapshot.
const coverageSnapshotOperationName = 'coverageTreemap.getSnapshot';

/// Operation name the view calls to report its resolved theme.
const themeReportOperationName = 'coverageTreemap.reportTheme';

/// Event stream on which the host pushes fresh coverage snapshots.
const snapshotPushStreamName = 'coverageTreemap.snapshotPush';

/// Operation name the view calls after applying a pushed snapshot.
const pushReceivedOperationName = 'coverageTreemap.pushReceived';

/// Operation name the view calls after its first frame completes.
const firstFramePaintedOperationName = 'coverageTreemap.firstFramePainted';

/// One node of the protocol-safe coverage tree.
///
/// A file node has no [children]; a directory node aggregates its
/// subtree's counts.
final class CoverageNode {
  /// Creates a snapshot node.
  const CoverageNode({
    required this.name,
    required this.linesFound,
    required this.linesHit,
    this.children = const [],
    this.isFile = false,
  });

  /// Builds the node tree for [directory].
  factory CoverageNode.fromDirectory(LcovDirectory directory) => CoverageNode(
    name: directory.name,
    linesFound: directory.linesFound,
    linesHit: directory.linesHit,
    children: [
      for (final child in directory.directories)
        CoverageNode.fromDirectory(child),
      for (final file in directory.files)
        CoverageNode(
          name: file.name,
          linesFound: file.linesFound,
          linesHit: file.linesHit,
          isFile: true,
        ),
    ],
  );

  /// Final path segment for display.
  final String name;

  /// Instrumented lines in this subtree.
  final int linesFound;

  /// Executed lines in this subtree.
  final int linesHit;

  /// Child nodes; empty for files.
  final List<CoverageNode> children;

  /// Whether this node is a file rather than a directory.
  final bool isFile;

  /// Covered fraction in [0, 1].
  double get coverage => linesFound == 0 ? 0 : linesHit / linesFound;
}

/// The exact wire schema of [CoverageNode]; recursive through
/// [ViewValueKind.nested]'s lazy reference.
final ViewValueSchema<CoverageNode> coverageNodeSchema = ViewValueSchema((
  field,
) {
  final name = field('name', ViewValueKind.string, (node) => node.name);
  final linesFound = field(
    'linesFound',
    ViewValueKind.integer,
    (node) => node.linesFound,
  );
  final linesHit = field(
    'linesHit',
    ViewValueKind.integer,
    (node) => node.linesHit,
  );
  final isFile = field('isFile', ViewValueKind.boolean, (node) => node.isFile);
  final children = field(
    'children',
    ViewValueKind.listOf(ViewValueKind.nested(() => coverageNodeSchema)),
    (node) => node.children,
  );
  return (fields) => CoverageNode(
    name: name(fields),
    linesFound: linesFound(fields),
    linesHit: linesHit(fields),
    isFile: isFile(fields),
    children: children(fields),
  );
});

/// The full snapshot the host serves to the view.
final class CoverageSnapshot {
  /// Creates a snapshot.
  const CoverageSnapshot({required this.lcovPath, required this.root});

  /// Builds a snapshot from a parsed [report].
  factory CoverageSnapshot.fromReport(String lcovPath, LcovReport report) =>
      CoverageSnapshot(
        lcovPath: lcovPath,
        root: CoverageNode.fromDirectory(report.tree),
      );

  /// Workspace-relative path of the parsed tracefile.
  final String lcovPath;

  /// Root of the coverage tree.
  final CoverageNode root;
}

/// The exact wire schema of [CoverageSnapshot].
final ViewValueSchema<CoverageSnapshot> coverageSnapshotSchema =
    ViewValueSchema((field) {
      final lcovPath = field(
        'lcovPath',
        ViewValueKind.string,
        (snapshot) => snapshot.lcovPath,
      );
      final root = field(
        'root',
        ViewValueKind.nested(() => coverageNodeSchema),
        (snapshot) => snapshot.root,
      );
      return (fields) =>
          CoverageSnapshot(lcovPath: lcovPath(fields), root: root(fields));
    });

/// The view's resolved theme, reported to Host Dart so gates can verify
/// that live VS Code colors reached the Flutter View.
final class ThemeReport {
  /// Creates a report.
  const ThemeReport({required this.kind, this.editorBackground});

  /// The resolved theme-kind name (`light`, `dark`, or `highContrast`).
  final String kind;

  /// The resolved `--vscode-editor-background` as a 32-bit ARGB
  /// integer, when the theme provided it.
  final int? editorBackground;
}

/// The exact wire schema of [ThemeReport].
final ViewValueSchema<ThemeReport> themeReportSchema = ViewValueSchema((field) {
  final kind = field('kind', ViewValueKind.string, (report) => report.kind);
  final editorBackground = field(
    'editorBackground',
    ViewValueKind.integer.orNull,
    (report) => report.editorBackground,
  );
  return (fields) => ThemeReport(
    kind: kind(fields),
    editorBackground: editorBackground(fields),
  );
});

/// Fetches the current coverage snapshot from Host Dart.
final ViewOperation<void, CoverageSnapshot> snapshotOperation =
    ViewOperation.noArgs(
      coverageSnapshotOperationName,
      encodeResult: coverageSnapshotSchema.encode,
      decodeResult: coverageSnapshotSchema.decode,
    );

/// Reports the view's resolved theme to Host Dart.
final ViewOperation<ThemeReport, void> themeReportOperation =
    ViewOperation.noResult(
      themeReportOperationName,
      encodeArguments: themeReportSchema.encode,
      decodeArguments: themeReportSchema.decode,
    );

/// Acknowledges a host-pushed snapshot with its total instrumented
/// lines.
final ViewOperation<int, void> pushReceivedOperation = ViewOperation.noResult(
  pushReceivedOperationName,
  encodeArguments: ViewValueKind.integer.encode,
  decodeArguments: ViewValueKind.integer.decode,
);

/// Confirms the view painted its first frame.
///
/// This is the signal occlusion throttling suppresses: a throttled
/// webview connects and exchanges data but never completes a frame, so
/// the gates assert paint, not just boot.
final ViewOperation<bool, void> firstFramePaintedOperation =
    ViewOperation.noResult(
      firstFramePaintedOperationName,
      encodeArguments: ViewValueKind.boolean.encode,
      decodeArguments: ViewValueKind.boolean.decode,
    );
