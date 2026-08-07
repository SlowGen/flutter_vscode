import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:coverage_treemap_host/generated/host_exports.g.dart';
import 'package:coverage_treemap_shared/lcov.dart';
import 'package:coverage_treemap_shared/view_contract.dart';
import 'package:dart_vscode/dart_vscode.dart' as parity;
import 'package:dart_vscode/dart_vscode.dart' as vs;
import 'package:dart_vscode/flutter_view_host.dart';
import 'package:dart_vscode/host_commands.dart';
import 'package:dart_vscode/host_runtime.dart';

const _lcovRelativePath = 'coverage/lcov.info';

@JSExport()
class _Extension {
  _CoverageController? _controller;

  JSPromise<JSAny?> activate(JSObject rawContext, JSObject rawVscode) {
    final controller = _CoverageController(
      parity.ExtensionContext(rawContext),
      parity.VscodeApi(rawVscode),
      parity.VscodeApi(rawVscode).dart,
    );
    _controller = controller;
    return toHostPromise(controller.start());
  }

  JSPromise<JSAny?> deactivate() {
    final controller = _controller;
    _controller = null;
    return toHostPromise(
      Future<JSAny?>(() async {
        await controller?.closePanelSession();
        return null;
      }),
    );
  }
}

final class _CoverageController {
  _CoverageController(this._context, this._vscode, this._api);

  final parity.ExtensionContext _context;
  final parity.VscodeApi _vscode;
  final vs.VscodeApiDart _api;

  late final parity.TextEditorDecorationType _coveredType;
  late final parity.TextEditorDecorationType _uncoveredType;
  late final parity.StatusBarItem _statusBar;
  LcovReport? _report;
  var _highlightsEnabled = true;
  FlutterViewHost? _viewHost;
  var _pushesSent = 0;
  var _pushesApplied = 0;
  int? _lastAppliedLinesFound;
  parity.Terminal? _terminal;
  ThemeReport? _lastThemeReport;
  final Completer<String> _firstSnapshotServed = Completer<String>();
  final Completer<void> _firstFramePainted = Completer<void>();

  Future<JSAny?> start() async {
    _coveredType = _lineDecoration('diffEditor.insertedTextBackground');
    _uncoveredType = _lineDecoration('diffEditor.removedTextBackground');
    _statusBar =
        _api.window.createStatusBarItem$2(_api.StatusBarAlignment.Left, 100)
          ..command = 'coverage-treemap.runTests'.toJS
          ..tooltip = 'Run tests with coverage'.toJS;

    ExtensionCommands(context: _context, api: _api)
      ..register('coverage-treemap.refresh', (_) => _refresh())
      ..register('coverage-treemap.toggleLineHighlights', (_) {
        _highlightsEnabled = !_highlightsEnabled;
        _decorateActiveEditor();
        return null;
      })
      ..register('coverage-treemap.showTreemap', (_) => _openPanel())
      ..register('coverage-treemap.runTests', (_) {
        (_terminal ??= _api.window.createTerminal('Coverage Treemap'))
          ..show()
          ..sendText('flutter test --coverage');
        return null;
      })
      ..register('coverage-treemap.viewSmoke', (_) async {
        await _openPanel();
        final lcovPath = await _firstSnapshotServed.future.timeout(
          const Duration(seconds: 120),
          onTimeout: () => throw StateError(
            'The Flutter View did not serve a snapshot within 120s.',
          ),
        );
        await _firstFramePainted.future.timeout(
          const Duration(seconds: 300),
          onTimeout: () => throw StateError(
            'The Flutter View connected but never confirmed a painted '
            'first frame within 300s: an occluded or throttled webview '
            'renders nothing.',
          ),
        );
        return jsonEncode(<String, Object?>{
          'viewConnected': true,
          'firstFramePainted': true,
          'lcovPath': lcovPath,
        });
      })
      ..register('coverage-treemap.themeSmoke', (_) {
        final report = _lastThemeReport;
        return jsonEncode(
          report == null ? null : themeReportSchema.encode(report),
        );
      })
      ..register('coverage-treemap.pushSmoke', (_) {
        return jsonEncode(<String, Object?>{
          'pushesSent': _pushesSent,
          'pushesApplied': _pushesApplied,
          'lastAppliedLinesFound': _lastAppliedLinesFound,
        });
      })
      ..register('coverage-treemap.smoke', (_) async {
        await _refresh();
        final report = _report;
        final payload = report == null
            ? null
            : coverageSnapshotSchema.encode(
                CoverageSnapshot.fromReport(_lcovRelativePath, report),
              );
        return jsonEncode(payload);
      });

    final watcher = _api.workspace
        .createFileSystemWatcher('**/$_lcovRelativePath'.toJS)
        .dart;
    _subscribeParity(watcher);
    _subscriptions.addAll([
      watcher.onDidChangeStream.listen(_refreshOnEvent),
      watcher.onDidCreateStream.listen(_refreshOnEvent),
      watcher.onDidDeleteStream.listen(_refreshOnEvent),
      _api.window.onDidChangeActiveTextEditorStream.listen(
        (_) => _decorateActiveEditor(),
      ),
    ]);

    await _refresh();
    return null;
  }

  /// Closes the view session resources when the panel or extension ends.
  Future<void> closePanelSession() async {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    final viewHost = _viewHost;
    _viewHost = null;
    await viewHost?.close();
  }

  final List<StreamSubscription<Object?>> _subscriptions = [];

  void _refreshOnEvent(Object? _) => unawaited(_refresh());

  void _subscribeParity(JSObject registration) {
    _context.own(registration);
  }

  Future<void> _refresh() async {
    final content = await _readLcov();
    if (content == null) {
      _report = null;
      _statusBar
        ..text = r'$(beaker) Cov: no data'
        ..show();
      _decorateActiveEditor();
      return;
    }
    try {
      _report = parseLcov(content);
    } on FormatException catch (error) {
      _report = null;
      unawaited(
        _api.window.showErrorMessage(
          'Coverage Treemap could not parse $_lcovRelativePath: '
          '${error.message}',
        ),
      );
    }
    final report = _report;
    if (report != null) {
      final percent = (report.coverage * 100).toStringAsFixed(1);
      _statusBar
        ..text = '\$(beaker) Cov $percent%'
        ..show();
      final viewHost = _viewHost;
      if (viewHost != null) {
        _pushesSent += 1;
        unawaited(
          viewHost.session
              .emitEvent(
                snapshotPushStreamName,
                coverageSnapshotSchema.encode(
                  CoverageSnapshot.fromReport(_lcovRelativePath, report),
                ),
              )
              .catchError((Object _) {}),
        );
      }
    }
    _decorateActiveEditor();
  }

  Future<String?> _readLcov() async {
    final folders = _api.workspace.workspaceFolders?.toDart;
    if (folders == null || folders.isEmpty) {
      return null;
    }
    final uri = _api.Uri.joinPath(
      folders.first.uri,
      ['coverage'.toJS, 'lcov.info'.toJS],
    );
    try {
      final bytes = await _api.workspace.fs.dart.readFile(uri);
      return utf8.decode(bytes.toDart);
    } on Object {
      // A missing or unreadable coverage file is a normal state.
      return null;
    }
  }

  void _decorateActiveEditor() {
    final editor = _api.window.activeTextEditor;
    if (editor == null) {
      return;
    }
    final report = _report;
    final covered = <parity.Range>[];
    final uncovered = <parity.Range>[];
    if (report != null && _highlightsEnabled) {
      final relative = _api.workspace.asRelativePath(editor.document.uri);
      for (final file in report.files) {
        if (file.path != relative) {
          continue;
        }
        for (final entry in file.lineHits.entries) {
          final line = entry.key - 1;
          if (line < 0) {
            continue;
          }
          final range = _api.Range.new$$2(line, 0, line, 0);
          (entry.value > 0 ? covered : uncovered).add(range);
        }
        break;
      }
    }
    editor
      ..setDecorations(_coveredType, covered.toJS)
      ..setDecorations(_uncoveredType, uncovered.toJS);
  }

  Future<void> _openPanel() async {
    if (_viewHost != null) {
      return;
    }
    _viewHost = FlutterViewHost.open(
      context: _context,
      vscode: _vscode,
      viewName: 'treemap_panel',
      viewType: 'coverageTreemap.panel',
      title: 'Coverage Treemap',
      onClosed: () => _viewHost = null,
      operations: [
        pushReceivedOperation.bind((linesFound) {
          _pushesApplied += 1;
          _lastAppliedLinesFound = linesFound;
        }),
        snapshotOperation.bind((_) async {
          await _refresh();
          final report = _report;
          if (report == null) {
            throw StateError(
              'No coverage data at $_lcovRelativePath. Run your tests '
              'with coverage first.',
            );
          }
          final snapshot = CoverageSnapshot.fromReport(
            _lcovRelativePath,
            report,
          );
          if (!_firstSnapshotServed.isCompleted) {
            _firstSnapshotServed.complete(snapshot.lcovPath);
          }
          return snapshot;
        }),
        firstFramePaintedOperation.bind((painted) {
          if (painted && !_firstFramePainted.isCompleted) {
            _firstFramePainted.complete();
          }
        }),
        themeReportOperation.bind((report) {
          _lastThemeReport = report;
        }),
      ],
    );
  }

  parity.TextEditorDecorationType _lineDecoration(String colorId) =>
      _api.window.createTextEditorDecorationType(
        vs.DecorationRenderOptionsDart.lit$(
          backgroundColor: _api.ThemeColor.new$(colorId),
          isWholeLine: true,
        ),
      );
}

void main() {
  registerHostExports(createJSInteropWrapper(_Extension()));
}
