import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart' as vs;
import 'package:dart_vscode/host_commands.dart';
import 'package:dart_vscode/host_runtime.dart';
import 'package:pubspec_lens_host/generated/host_exports.g.dart';
import 'package:pubspec_lens_host/registry_client.dart';
import 'package:pubspec_lens_shared/pubspec_model.dart';
import 'package:pubspec_lens_shared/registry.dart';

/// The view id the dependencies tree binds to.
///
/// Contributed by this extension's own typed manifest (`extension.dart`
/// declares it under `views`), so the tree renders in a plain F5 session;
/// the gate proves the contribution through the `.focus` command VS Code
/// registers only for contributed views.
const _dependenciesViewId = 'pubspecLens.dependencies';

@JSExport()
class _Extension {
  _PubspecLensController? _controller;

  JSPromise<JSAny?> activate(JSObject rawContext, JSObject rawVscode) {
    final controller = _PubspecLensController(
      vs.ExtensionContext(rawContext),
      vs.VscodeApi(rawVscode).dart,
    );
    _controller = controller;
    return toHostPromise(controller.start());
  }

  JSPromise<JSAny?> deactivate() {
    final controller = _controller;
    _controller = null;
    return toHostPromise(
      Future<JSAny?>(() async {
        controller?.dispose();
        return null;
      }),
    );
  }
}

/// One dependency with its registry answer and verdict.
final class _DependencyReport {
  const _DependencyReport(this.dependency, this.verdict, this.info);

  final PubspecDependency dependency;
  final Verdict verdict;
  final PackageInfo? info;
}

/// One analyzed pubspec document.
final class _Analysis {
  const _Analysis(this.uri, this.reports);

  final vs.Uri uri;
  final List<_DependencyReport> reports;
}

final class _PubspecLensController {
  _PubspecLensController(this._context, this._api);

  final vs.ExtensionContext _context;
  final vs.VscodeApiDart _api;

  final RegistryClient _registry = RegistryClient();
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final Map<String, _Analysis> _analysesByUri = {};
  List<_DependencyReport> _treeReports = const [];

  late final vs.DiagnosticCollection _diagnostics;
  late final vs.EventEmitter<JSAny?> _treeDidChange;
  late final vs.EventEmitter<JSAny?> _lensesDidChange;

  /// Analyses are serialized on this chain so an earlier run (say the
  /// activation pass against the default registry) can never clobber
  /// the results of a later one (a refresh against a changed
  /// `pubspecLens.registryUrl`).
  Future<void> _analysisChain = Future<void>.value();

  Future<JSAny?> start() async {
    _diagnostics = _api.languages.createDiagnosticCollection('pubspec-lens');
    _treeDidChange = _api.EventEmitter.new$<JSAny?>();
    _lensesDidChange = _api.EventEmitter.new$<JSAny?>();

    ExtensionCommands(context: _context, api: _api)
      ..register('pubspec-lens.refresh', (_) async {
        _registry.clearCache();
        await _enqueueAnalyzeAll();
        return null;
      })
      ..register('pubspec-lens.update', _applyUpdate)
      ..register('pubspec-lens.smoke', (_) async {
        await _enqueueAnalyzeAll();
        var hosted = 0;
        var behind = 0;
        var outdated = 0;
        var skipped = 0;
        for (final report in _treeReports) {
          switch (report.verdict.kind) {
            case VerdictKind.current || VerdictKind.unknown:
              hosted += 1;
            case VerdictKind.behind:
              hosted += 1;
              behind += 1;
            case VerdictKind.outdated:
              hosted += 1;
              outdated += 1;
            case VerdictKind.skipped:
              skipped += 1;
          }
        }
        return jsonEncode(<String, Object?>{
          'registryUrl': _registryUrl(),
          'depsAnalyzed': _treeReports.length,
          'hosted': hosted,
          'behind': behind,
          'outdated': outdated,
          'skipped': skipped,
          'treeChildren': _treeLabels(),
        });
      });

    _registerHoverProvider();
    _registerCodeLensProvider();
    _registerTreeDataProvider();

    // The analysis triggers: activation analyzes the workspace root's
    // pubspec.yaml (plus any already-open pubspec buffer), and every
    // open/change of a pubspec.yaml document re-analyzes. No debounce
    // by design — registry answers are cached, so a re-analysis costs
    // one yaml parse.
    _subscriptions.addAll([
      _api.workspace.onDidOpenTextDocumentStream.listen((document) {
        if (_isPubspec(document.uri)) {
          unawaited(_enqueueAnalyzeAll());
        }
      }),
      _api.workspace.onDidChangeTextDocumentStream.listen((event) {
        if (_isPubspec(event.document.uri)) {
          unawaited(_enqueueAnalyzeAll());
        }
      }),
    ]);

    // Activation does not await the first pass; an unreachable
    // registry must not stall the Extension Host, and every consumer
    // of the results (refresh, smoke, update) awaits its own
    // enqueued run.
    unawaited(_enqueueAnalyzeAll());
    return null;
  }

  void dispose() {
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    _diagnostics.dispose();
    _treeDidChange.dispose();
    _lensesDidChange.dispose();
  }

  // ── analysis ─────────────────────────────────────────────────────

  Future<void> _enqueueAnalyzeAll() {
    return _analysisChain = _analysisChain.then((_) => _analyzeAll());
  }

  Future<void> _analyzeAll() async {
    final analyzed = <String>{};
    for (final document in _api.workspace.textDocuments.toDart) {
      if (!_isPubspec(document.uri)) {
        continue;
      }
      analyzed.add(document.uri.toString$());
      await _analyzeSource(document.uri, document.getText());
    }
    final root = _rootPubspecUri();
    if (root != null && !analyzed.contains(root.toString$())) {
      final content = await _readFile(root);
      if (content != null) {
        await _analyzeSource(root, content);
      }
    }
  }

  Future<void> _analyzeSource(vs.Uri uri, String content) async {
    final registryUrl = _registryUrl();
    List<PubspecDependency> dependencies;
    try {
      dependencies = parsePubspec(content);
    } on FormatException {
      // A buffer mid-edit: keep the previous analysis and diagnostics
      // instead of flapping on every broken keystroke.
      return;
    }
    final reports = <_DependencyReport>[];
    for (final dependency in dependencies) {
      final info = dependency.isHosted
          ? await _registry.fetchPackageInfo(registryUrl, dependency.name)
          : null;
      reports.add(
        _DependencyReport(
          dependency,
          verdictFor(dependency, info?.latest),
          info,
        ),
      );
    }
    _analysesByUri[uri.toString$()] = _Analysis(uri, reports);
    _publishDiagnostics(uri, reports);
    final root = _rootPubspecUri();
    if (root != null && root.toString$() == uri.toString$()) {
      _treeReports = reports;
    }
    _treeDidChange.fire(null);
    _lensesDidChange.fire(null);
  }

  void _publishDiagnostics(vs.Uri uri, List<_DependencyReport> reports) {
    final diagnostics = <vs.Diagnostic>[];
    for (final report in reports) {
      final verdict = report.verdict;
      if (verdict.kind != VerdictKind.outdated) {
        continue;
      }
      final name = report.dependency.nameSpan;
      final end = report.dependency.constraintSpan ?? name;
      final range = _rangeOf(name, end);
      // Severity is Information by design: a newer release existing
      // is advice about the ecosystem, not a defect in this file.
      final diagnostic = _api.Diagnostic.new$(
        range,
        '${report.dependency.name} ${verdict.latest} is available '
        '(pinned ${report.dependency.constraintText})',
        _api.DiagnosticSeverity.Information,
      )..source = 'pubspec-lens';
      diagnostics.add(diagnostic);
    }
    _diagnostics.set(uri, diagnostics.toJS);
  }

  // ── native UI surface ────────────────────────────────────────────

  void _registerHoverProvider() {
    final provideHover =
        ((
              vs.TextDocument document,
              vs.Position position,
              vs.CancellationToken token,
            ) {
              final report = _reportAt(document.uri, position.line.toInt());
              if (report == null || !report.dependency.isHosted) {
                return null;
              }
              final buffer = StringBuffer('**${report.dependency.name}**');
              final info = report.info;
              if (info != null) {
                buffer.write(' — latest `${info.latest}`');
              }
              switch (report.verdict.kind) {
                case VerdictKind.behind:
                  buffer.write(
                    '\n\nBehind: `${report.dependency.constraintText}` already '
                    'allows ${report.verdict.latest} — bump to '
                    '`${report.verdict.suggestedConstraint}` to require it.',
                  );
                case VerdictKind.outdated:
                  buffer.write(
                    '\n\nOutdated: `${report.dependency.constraintText}` excludes '
                    'the latest release; `${report.verdict.suggestedConstraint}` '
                    'available.',
                  );
                case VerdictKind.unknown:
                  buffer.write('\n\nNo registry answer for this package.');
                case VerdictKind.current || VerdictKind.skipped:
                  break;
              }
              final description = info?.description;
              if (description != null) {
                buffer.write('\n\n$description');
              }
              final name = report.dependency.nameSpan;
              return _api.Hover.new$(
                _api.MarkdownString.new$(buffer.toString()),
                _rangeOf(name),
              );
            })
            .toJS;
    _subscribe(
      _api.languages.registerHoverProvider(
        'yaml'.toJS,
        vs.HoverProviderDart.lit$(provideHover: toHostCallback(provideHover)),
      ),
    );
  }

  void _registerCodeLensProvider() {
    final provideCodeLenses =
        ((
              vs.TextDocument document,
              vs.CancellationToken token,
            ) {
              final analysis = _analysesByUri[document.uri.toString$()];
              if (analysis == null) {
                return <vs.CodeLens>[].toJS;
              }
              final lenses = <vs.CodeLens>[];
              for (final report in analysis.reports) {
                final suggested = report.verdict.suggestedConstraint;
                if (suggested == null ||
                    report.dependency.constraintSpan == null) {
                  continue;
                }
                final name = report.dependency.nameSpan;
                lenses.add(
                  _api.CodeLens.new$(
                    _rangeOf(name),
                    vs.CommandDart.lit$(
                      command: 'pubspec-lens.update',
                      title: 'Update to $suggested',
                      arguments: <JSAny?>[
                        document.uri.toString$().toJS,
                        report.dependency.name.toJS,
                      ].toJS,
                    ),
                  ),
                );
              }
              return lenses.toJS;
            })
            .toJS;
    _subscribe(
      _api.languages.registerCodeLensProvider(
        'yaml'.toJS,
        vs.CodeLensProviderDart<JSAny?>.lit$(
          onDidChangeCodeLenses: _lensesDidChange.event,
          provideCodeLenses: toHostCallback(provideCodeLenses),
        ),
      ),
    );
  }

  void _registerTreeDataProvider() {
    final getChildren = (([JSAny? element]) {
      if (!element.isUndefinedOrNull) {
        return <JSString>[].toJS;
      }
      return [for (final label in _treeLabels()) label.toJS].toJS;
    }).toJS;
    final getTreeItem = ((JSString element) {
      return _api.TreeItem.new$(element, _api.TreeItemCollapsibleState.None);
    }).toJS;
    _subscribe(
      _api.window.registerTreeDataProvider(
        _dependenciesViewId,
        vs.TreeDataProviderDart<JSString>.lit$(
          getChildren: toHostCallback(getChildren),
          getTreeItem: toHostCallback(getTreeItem),
          onDidChangeTreeData: _treeDidChange.event,
        ),
      ),
    );
  }

  Future<Object?> _applyUpdate(List<Object?> arguments) async {
    if (arguments.length < 2 ||
        arguments[0] is! String ||
        arguments[1] is! String) {
      throw ArgumentError(
        'pubspec-lens.update expects (documentUri, packageName).',
      );
    }
    final analysis = _analysesByUri[arguments[0]! as String];
    final name = arguments[1]! as String;
    final report = analysis?.reports
        .where(
          (report) =>
              report.dependency.name == name &&
              report.verdict.suggestedConstraint != null &&
              report.dependency.constraintSpan != null,
        )
        .firstOrNull;
    if (analysis == null || report == null) {
      return false;
    }
    final span = report.dependency.constraintSpan!;
    final edit = _api.WorkspaceEdit.new$()
      ..replace(
        analysis.uri,
        _rangeOf(span),
        report.verdict.suggestedConstraint!,
      );
    final applied = await _api.workspace.applyEdit(edit);
    if (applied) {
      // The change event re-analyzes too; this await makes the new
      // verdict visible before the command's promise resolves.
      await _enqueueAnalyzeAll();
    }
    return applied;
  }

  // ── shared lookups ───────────────────────────────────────────────

  List<String> _treeLabels() {
    return [
      for (final report in _treeReports)
        switch (report.verdict.kind) {
          VerdictKind.current =>
            '${report.dependency.name} — current '
                '(latest ${report.verdict.latest})',
          VerdictKind.behind =>
            '${report.dependency.name} — behind '
                '(${report.verdict.suggestedConstraint} available)',
          VerdictKind.outdated =>
            '${report.dependency.name} — outdated '
                '(${report.verdict.suggestedConstraint} available)',
          VerdictKind.unknown => '${report.dependency.name} — unknown',
          VerdictKind.skipped =>
            '${report.dependency.name} — skipped '
                '(${report.dependency.source.name})',
        },
    ];
  }

  _DependencyReport? _reportAt(vs.Uri uri, int line) {
    final analysis = _analysesByUri[uri.toString$()];
    if (analysis == null) {
      return null;
    }
    return analysis.reports
        .where((report) => report.dependency.nameSpan.startLine == line)
        .firstOrNull;
  }

  String _registryUrl() {
    final value = _api.workspace
        .getConfiguration('pubspecLens')
        .get<JSString>('registryUrl');
    final url = value?.toDart.trim() ?? '';
    return url.isEmpty ? 'https://pub.dev' : url;
  }

  vs.Uri? _rootPubspecUri() {
    final folders = _api.workspace.workspaceFolders?.toDart;
    if (folders == null || folders.isEmpty) {
      return null;
    }
    return _api.Uri.joinPath(folders.first.uri, ['pubspec.yaml'.toJS]);
  }

  bool _isPubspec(vs.Uri uri) {
    final path = uri.path;
    return path == 'pubspec.yaml' || path.endsWith('/pubspec.yaml');
  }

  Future<String?> _readFile(vs.Uri uri) async {
    try {
      final bytes = await _api.workspace.fs.dart.readFile(uri);
      return utf8.decode(bytes.toDart);
    } on Object {
      // A workspace without a root pubspec is a normal state.
      return null;
    }
  }

  /// Projects one [SpanLocation] (or a [start]..[end] pair) into a VS Code
  /// range.
  vs.Range _rangeOf(SpanLocation start, [SpanLocation? end]) {
    final last = end ?? start;
    return _api.Range.new$$2(
      start.startLine,
      start.startColumn,
      last.endLine,
      last.endColumn,
    );
  }

  void _subscribe(JSObject registration) {
    _context.own(registration);
  }
}

void main() {
  registerHostExports(createJSInteropWrapper(_Extension()));
}
