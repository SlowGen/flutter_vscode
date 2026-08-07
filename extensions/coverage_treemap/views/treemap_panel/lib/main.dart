/// The coverage treemap Flutter View for the coverage_treemap extension.
library;

import 'dart:async';

import 'package:coverage_treemap_shared/view_contract.dart';
import 'package:flutter/material.dart';
import 'package:flutter_vscode/view.dart';
import 'package:treemap_panel/drilldown.dart';
import 'package:treemap_panel/summary_charts.dart';
import 'package:treemap_panel/treemap.dart';

/// Runs the coverage treemap view over one connected [ViewShell], which
/// owns the session, the live VS Code theme, and every protocol
/// subscription for the lifetime of the view.
Future<void> main() async {
  final shell = await ViewShell.connect();
  runFlutterView(TreemapApp(shell: shell));
  unawaited(_confirmFirstFrame(shell));
}

/// Reports the first completed frame to Host Dart.
///
/// An occluded or throttled webview connects but never completes a
/// frame, so the desktop and container gates await this confirmation
/// rather than trusting the connection alone. Failure to deliver the
/// report leaves the host's gate timeout to tell the story; the view
/// itself keeps rendering.
Future<void> _confirmFirstFrame(ViewShell shell) async {
  await WidgetsBinding.instance.endOfFrame;
  try {
    await firstFramePaintedOperation.callThrough(
      shell.session.operationCaller,
      true,
    );
  } on Object {
    // Diagnostic-only from the view's perspective.
  }
}

/// Root widget themed from the host VS Code color theme.
///
/// The shell's theme snapshot captured at startup seeds the Material
/// theme; its deduplicated theme stream rebuilds it live when the user
/// switches VS Code color themes.
class TreemapApp extends StatelessWidget {
  /// Creates the root widget over the connected [shell].
  const TreemapApp({required this.shell, super.key});

  /// The connected view shell owning session and theme lifecycles.
  final ViewShell shell;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<VSCodeThemeSnapshot>(
      stream: shell.themeChanges,
      initialData: shell.theme,
      builder: (context, snapshot) {
        final theme = vsCodeThemeData(snapshot.data ?? shell.theme);
        return MaterialApp(
          title: 'Coverage Treemap',
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(
            textTheme: theme.textTheme.apply(fontFamily: 'Roboto'),
          ),
          home: _TreemapPage(shell: shell),
        );
      },
    );
  }
}

class _TreemapPage extends StatefulWidget {
  const _TreemapPage({required this.shell});

  final ViewShell shell;

  @override
  State<_TreemapPage> createState() => _TreemapPageState();
}

class _TreemapPageState extends State<_TreemapPage> {
  CoverageSnapshot? _snapshot;
  List<CoverageNode> _path = const [];
  CoverageNode? _selectedFile;
  Object? _error;
  var _loading = true;

  @override
  void initState() {
    super.initState();
    // The shell owns these subscriptions: disposing it ends both streams,
    // so nothing here holds a StreamSubscription to cancel by hand.
    widget.shell.themeChanges.listen(
      (snapshot) => unawaited(_reportTheme(snapshot)),
    );
    widget.shell.events(snapshotPushStreamName).listen(_applyPushedSnapshot);
    unawaited(_reportTheme(widget.shell.theme));
    unawaited(_load());
  }

  @override
  void dispose() {
    unawaited(widget.shell.dispose());
    super.dispose();
  }

  /// Applies a host-pushed snapshot and acknowledges it, so the panel
  /// refreshes without polling whenever the coverage file changes.
  void _applyPushedSnapshot(Object? payload) {
    final CoverageSnapshot snapshot;
    try {
      snapshot = coverageSnapshotSchema.decode(payload);
    } on FormatException {
      // A malformed push is ignored; pull refresh remains available.
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _snapshot = snapshot;
      _path = rebasePath(newRoot: snapshot.root, previousPath: _path);
      _selectedFile = null;
      _loading = false;
    });
    unawaited(
      pushReceivedOperation
          .callThrough(
            widget.shell.session.operationCaller,
            snapshot.root.linesFound,
          )
          .catchError((Object _) {}),
    );
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshot = await snapshotOperation.callThrough(
        widget.shell.session.operationCaller,
        null,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _snapshot = snapshot;
        _path = rebasePath(newRoot: snapshot.root, previousPath: _path);
        _selectedFile = null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  /// Reports the resolved theme to Host Dart for gate verification.
  Future<void> _reportTheme(VSCodeThemeSnapshot snapshot) async {
    try {
      await themeReportOperation.callThrough(
        widget.shell.session.operationCaller,
        ThemeReport(
          kind: snapshot.kind.name,
          editorBackground: snapshot.editorBackground,
        ),
      );
    } on Object {
      // Theme reporting is diagnostic-only; the view keeps rendering
      // when the host cannot accept a report.
    }
  }

  void _refresh() => unawaited(_load());

  void _handleNodeTap(CoverageNode node) {
    setState(() {
      if (node.isFile) {
        _selectedFile = node;
      } else {
        _path = descendSingleChildChain([..._path, node]);
        _selectedFile = null;
      }
    });
  }

  void _navigateTo(int index) {
    setState(() {
      _path = _path.sublist(0, index + 1);
      _selectedFile = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(body: SafeArea(child: _buildBody()));
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _error;
    if (error != null) {
      return _ErrorPanel(error: error, onRetry: _refresh);
    }
    final snapshot = _snapshot;
    if (snapshot == null || _path.isEmpty) {
      return const _EmptyPanel(isRoot: true);
    }
    final current = _path.last;
    final hasTiles = current.children.any((child) => child.linesFound > 0);
    return Column(
      children: [
        _HeaderBar(
          path: _path,
          lcovPath: snapshot.lcovPath,
          selectedFile: _selectedFile,
          onNavigate: _navigateTo,
          onRefresh: _refresh,
        ),
        if (current.linesFound > 0)
          CoverageSummaryStrip(node: current, onChildTap: _handleNodeTap),
        Expanded(
          child: hasTiles
              ? Padding(
                  padding: const EdgeInsets.all(8),
                  child: TreemapView(
                    nodes: current.children,
                    onNodeTap: _handleNodeTap,
                  ),
                )
              : _EmptyPanel(isRoot: _path.length == 1),
        ),
      ],
    );
  }
}

class _HeaderBar extends StatelessWidget {
  const _HeaderBar({
    required this.path,
    required this.lcovPath,
    required this.selectedFile,
    required this.onNavigate,
    required this.onRefresh,
  });

  final List<CoverageNode> path;
  final String lcovPath;
  final CoverageNode? selectedFile;
  final ValueChanged<int> onNavigate;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = path.last;
    final file = selectedFile;
    final subtitle = file == null
        ? lcovPath
        : '${file.name} - ${coveragePercent(file.coverage, decimals: 1)} '
              '(${file.linesHit}/${file.linesFound} lines)';
    return ColoredBox(
      color: scheme.surfaceContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: _Breadcrumb(path: path, onNavigate: onNavigate),
                ),
                const SizedBox(width: 12),
                Text(
                  coveragePercent(current.coverage, decimals: 1),
                  style: TextStyle(
                    color: scheme.onSurface,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: onRefresh,
                  child: const Text('Refresh'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _Breadcrumb extends StatelessWidget {
  const _Breadcrumb({required this.path, required this.onNavigate});

  final List<CoverageNode> path;
  final ValueChanged<int> onNavigate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final crumbs = <Widget>[];
    for (var i = 0; i < path.length; i++) {
      final isLast = i == path.length - 1;
      final name = i == 0 ? 'root' : path[i].name;
      if (i > 0) {
        crumbs.add(
          Text(
            ' > ',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13),
          ),
        );
      }
      crumbs.add(
        isLast
            ? Text(
                name,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              )
            : InkWell(
                onTap: () => onNavigate(i),
                child: Text(
                  name,
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 13,
                  ),
                ),
              ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: crumbs),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  const _ErrorPanel({required this.error, required this.onRetry});

  final Object error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Could not load coverage',
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '$error',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton(onPressed: onRetry, child: const Text('Retry')),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  const _EmptyPanel({required this.isRoot});

  final bool isRoot;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        isRoot
            ? 'No coverage data - run your tests with coverage'
            : 'This directory has no measurable coverage',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontSize: 13,
        ),
      ),
    );
  }
}
