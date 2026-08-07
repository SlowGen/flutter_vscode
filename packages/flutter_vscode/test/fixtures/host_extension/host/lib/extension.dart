import 'dart:async';
import 'dart:js_interop';
import 'dart:math';

import 'package:dart_vscode/dart_vscode.dart' as parity;
import 'package:dart_vscode/flutter_view_host.dart';
import 'package:dart_vscode/host_commands.dart';
import 'package:dart_vscode/host_runtime.dart';
import 'package:dart_vscode/view_protocol.dart';
import 'package:flutter_vscode_host_fixture/generated/host_exports.g.dart';
import 'package:flutter_vscode_host_fixture_shared/fixture_view_contract.dart';

const _pingCommand = 'flutter-vscode.host-test.ping';
const _eventCountCommand = 'flutter-vscode.host-test.openEventCount';
const _unsubscribeCommand = 'flutter-vscode.host-test.unsubscribeOpenEvent';
const _identityCommand = 'flutter-vscode.host-test.hoverDocumentMatchedEvent';
const _failAsyncCommand = 'flutter-vscode.host-test.failAsync';
const _failSyncCommand = 'flutter-vscode.host-test.failSync';
const _jsPromiseSourceCommand = 'flutter-vscode.host-test.jsPromiseSource';
const _jsPromiseRoundTripCommand =
    'flutter-vscode.host-test.jsPromiseRoundTrip';
const _hoverReceivedCancellationTokenCommand =
    'flutter-vscode.host-test.hoverReceivedCancellationToken';
const _paritySmokeCommand = 'flutter-vscode.host-test.paritySmoke';
const _disposeParityProviderCommand =
    'flutter-vscode.host-test.disposeParityProvider';
const _openFlutterViewCommand = 'flutter-vscode.host-test.openFlutterView';
const _probeFlutterViewProtocolCommand =
    'flutter-vscode.host-test.probeFlutterViewProtocol';

@JS('process.env.FLUTTER_VSCODE_HOST_TEST_FAIL_ACTIVATION')
external JSString? get _activationFailureFlag;

const _readHostValueOperation = ViewOperation<ReadHostValueRequest, String>(
  name: readHostValueOperationName,
  encodeArguments: encodeReadHostValueRequest,
  decodeArguments: decodeReadHostValueRequest,
  encodeResult: encodeReadHostValueResult,
  decodeResult: decodeReadHostValueResult,
);

const _wrongNonceOperation = ViewOperation<Object?, Object?>(
  name: wrongNonceOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

const _malformedSchemaOperation = ViewOperation<Object?, Object?>(
  name: malformedSchemaOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

const _unsupportedVersionOperation = ViewOperation<Object?, Object?>(
  name: unsupportedVersionOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

const _pendingAcrossReloadOperation = ViewOperation<Object?, Object?>(
  name: pendingAcrossReloadOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

const _protocolProbePhaseOperation = ViewOperation<Object?, Object?>(
  name: protocolProbePhaseOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

const _requestReloadOperation = ViewOperation<Object?, Object?>(
  name: requestReloadOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

final _confirmRenderObservationOperation =
    ViewOperation<ConfirmRenderObservationRequest, bool>(
      name: confirmRenderObservationOperationName,
      encodeArguments: encodeConfirmRenderObservationRequest,
      decodeArguments: decodeConfirmRenderObservationRequest,
      encodeResult: (value) => value,
      decodeResult: decodeFixtureBool,
    );

@JSExport()
class _VSCodeHostExtension {
  var _openEventCount = 0;
  parity.Disposable? _openEventSubscription;
  parity.TextDocument? _lastOpenedDocument;
  var _hoverDocumentMatchedEvent = false;
  var _hoverReceivedCancellationToken = false;

  JSPromise<JSAny?> activate(JSObject rawContext, JSObject rawVscode) {
    return toHostPromise(
      Future<JSAny?>(() {
        try {
          final context = parity.ExtensionContext(rawContext);
          final vscode = parity.VscodeApi(rawVscode);
          final ping = (() {
            return Future<JSString>.value('pong from Dart'.toJS).toJS;
          }).toJS;

          final registration = vscode.commands.registerCommand(
            _pingCommand,
            toHostCallback(ping),
          );
          _addSubscription(context, registration);

          final jsPromiseRoundTrip = (() {
            final source = vscode.commands
                .executeCommand<JSAny?>(_jsPromiseSourceCommand.toJS)
                .toDart;
            return toHostPromise(
              source.then<JSAny?>((value) {
                final text = (value! as JSString).toDart;
                return 'Dart received: $text'.toJS;
              }),
            );
          }).toJS;
          final jsPromiseRoundTripRegistration = vscode.commands
              .registerCommand(
                _jsPromiseRoundTripCommand,
                toHostCallback(jsPromiseRoundTrip),
              );
          _addSubscription(context, jsPromiseRoundTripRegistration);

          parity.Disposable? parityHoverRegistration;
          final paritySmoke = (() {
            final api = parity.VscodeApi(rawVscode);
            final position = api.Position.new$(3.toJS, 7.toJS);
            final translated = position.translate(1);
            final uri = api.Uri.file('/parity/smoke.json');
            api.workspace.onDidChangeConfiguration
                .call(((JSObject event) {}).toJS)
                .dispose();
            final provider = parity.HoverProvider.lit$(
              provideHover:
                  ((
                        JSObject document,
                        JSObject hoverPosition,
                        JSObject token,
                      ) {
                        final markdown = api.MarkdownString.new$(
                          'Hover from the parity layer'.toJS,
                        );
                        return api.Hover.new$(markdown);
                      })
                      .toJS,
            );
            final selector = parity.DocumentFilter.lit$(
              language: 'json'.toJS,
            );
            parityHoverRegistration = api.languages.registerHoverProvider(
              selector,
              provider,
            );
            return toHostPromise(
              Future<JSAny?>(() async {
                final families = <String, Object?>{};

                final commands = await api.commands.getCommands(true).toDart;
                families['commands'] = true;

                api.authentication.onDidChangeSessions
                    .call(((JSObject event) {}).toJS)
                    .dispose();
                families['authentication'] = true;

                api.comments
                    .createCommentController(
                      'parity-comments',
                      'Parity Comments',
                    )
                    .dispose();
                families['comments'] = true;

                api.debug.onDidChangeBreakpoints
                    .call(((JSObject event) {}).toJS)
                    .dispose();
                families['debug'] = true;

                await api.env.clipboard.writeText('parity-clip').toDart;
                final clipboard =
                    (await api.env.clipboard.readText().toDart).toDart;
                families['env'] = true;

                final self = api.extensions.getExtension(
                  'flutter-vscode-test.host-extension-fixture',
                );
                families['extensions'] = self != null;

                final localized = api.l10n.t('parity {0}'.toJS, <JSAny?>[
                  '42'.toJS,
                ]);
                families['l10n'] = localized.toDart.contains('parity 42');

                final languages = await api.languages.getLanguages().toDart;
                families['languages'] = languages.toDart.isNotEmpty;

                families['lm'] =
                    api.lm.tools.toDart.isEmpty ||
                    api.lm.tools.toDart.isNotEmpty;

                api.notebooks
                    .createNotebookController(
                      'parity-notebooks',
                      'jupyter-notebook',
                      'Parity Notebooks',
                    )
                    .dispose();
                families['notebooks'] = true;

                api.scm
                    .createSourceControl('parity-scm', 'Parity SCM')
                    .dispose();
                families['scm'] = true;

                final taskProvider = parity.TaskProvider.lit$(
                  provideTasks: ((JSObject token) => null).toJS,
                  resolveTask: ((JSObject task, JSObject token) => null).toJS,
                );
                api.tasks
                    .registerTaskProvider('parity-task-type', taskProvider)
                    .dispose();
                families['tasks'] = true;

                api.tests
                    .createTestController('parity-tests', 'Parity Tests')
                    .dispose();
                families['tests'] = true;

                api.window.createOutputChannel('Parity Smoke')
                  ..appendLine('parity families')
                  ..dispose();
                families['window'] = true;

                api.chat
                    .createChatParticipant(
                      'flutter-vscode-test.parity',
                      ((
                            JSObject request,
                            JSObject chatContext,
                            JSObject response,
                            JSObject token,
                          ) => null)
                          .toJS,
                    )
                    .dispose();
                families['chat'] = true;

                final document = await api.workspace
                    .openTextDocument$3(
                      parity.WorkspaceOpenTextDocument$2.lit$(
                        language: 'plaintext'.toJS,
                        content: 'parity edit target'.toJS,
                      ),
                    )
                    .toDart;
                final edit = api.WorkspaceEdit.new$()
                  ..insert(
                    document.uri,
                    api.Position.new$(0.toJS, 0.toJS),
                    'parity ',
                  );
                final applied =
                    (await api.workspace.applyEdit(edit).toDart).toDart;
                families['workspace'] = true;

                final emitter = api.EventEmitter.new$();
                String? received;
                final emitterSubscription = emitter.event.call(
                  ((JSAny? value) {
                    received = (value! as JSString).toDart;
                  }).toJS,
                );
                emitter.fire('parity-event'.toJS);
                emitterSubscription.dispose();
                emitter.dispose();

                final tokenSource = api.CancellationTokenSource.new$();
                final before = tokenSource.token.isCancellationRequested;
                tokenSource.cancel();
                final after = tokenSource.token.isCancellationRequested;
                tokenSource.dispose();

                final narrowed =
                    api.Position.isInstance(position) &&
                    !api.Uri.isInstance(position);

                // cc:tuple — real directory entries as [name, FileType].
                final parityContext = parity.ExtensionContext(rawContext);
                final entries =
                    (await api.workspace.fs
                            .readDirectory(parityContext.extensionUri)
                            .toDart)
                        .toDart;
                final firstEntry = entries.first;
                final tupleEntryName = firstEntry.$1.toDart;
                final tupleEntryIsFile = entries.any(
                  (entry) => entry.$2.toDartInt == api.FileType.File,
                );

                // cc:intersection — Memento & setKeysForSync live.
                final state = parityContext.globalState
                  ..setKeysForSync(<JSAny?>[].toJS as JSArray<JSString>);
                await state.update('parityKey', 'parity-state'.toJS).toDart;
                final intersectionRoundTrip =
                    (state.get('parityKey')! as JSString).toDart;

                // cc:external-setter — write then read a real QuickPick.
                final quickPick = api.window.createQuickPick()
                  ..value = 'parity-value';
                final setterRoundTrip = quickPick.value;
                quickPick.dispose();

                // cc:index-signature — operator [] on live configuration.
                final configuration = api.workspace.getConfiguration();
                final indexSignatureRead = configuration['editor'] != null;

                // cc:narrowing cc:mixed-union — narrow a union value that
                // VS Code itself produced.
                await api.window.showTextDocument(document).toDart;
                final activeTab = api.window.tabGroups.activeTabGroup.activeTab;
                final tabInputNarrowed =
                    activeTab != null &&
                    api.TabInputText.isInstance(activeTab.input);

                // cc:function-type — VS Code-invoked callback arguments
                // plus a lit$ progress report.
                final progressResult =
                    (await api.window
                            .withProgress<JSString>(
                              parity.ProgressOptions.lit$(
                                location:
                                    api.ProgressLocation.Notification.toJS,
                              ),
                              ((JSObject progress, JSObject token) {
                                parity.Progress(progress).report(
                                  parity.WindowWithProgress$1.lit$(
                                    message: 'parity progress'.toJS,
                                  ),
                                );
                                return Future<JSAny?>.value(
                                  'parity-progress'.toJS,
                                ).toJS;
                              }).toJS,
                            )
                            .toDart)
                        .toDart;

                final change = parity.PositionWith$1.lit$(line: 9.toJS);
                final moved = position.with$$2(change);

                return <String, Object?>{
                  'version': api.version,
                  'viewColumnActive': api.ViewColumn.Active,
                  'fileTypeFile': api.FileType.File,
                  'translatedLine': translated.line,
                  'uriFsPath': uri.fsPath,
                  'uriToString': uri.toString$(),
                  'commandCount': commands.toDart.length,
                  'eventSubscribed': true,
                  'families': families,
                  'eventEmitterRoundTrip': received,
                  'cancellationFlipped': !before && after,
                  'workspaceEditApplied': applied,
                  'clipboardRoundTrip': clipboard,
                  'narrowedPosition': narrowed,
                  'stableLiteralWith': moved.line,
                  'tupleEntryName': tupleEntryName,
                  'tupleEntryIsFile': tupleEntryIsFile,
                  'intersectionRoundTrip': intersectionRoundTrip,
                  'setterRoundTrip': setterRoundTrip,
                  'indexSignatureRead': indexSignatureRead,
                  'tabInputNarrowed': tabInputNarrowed,
                  'progressResult': progressResult,
                }.jsify();
              }),
            );
          }).toJS;
          final paritySmokeRegistration = vscode.commands.registerCommand(
            _paritySmokeCommand,
            toHostCallback(paritySmoke),
          );
          _addSubscription(context, paritySmokeRegistration);
          final disposeParityProvider = (() {
            parityHoverRegistration?.dispose();
            parityHoverRegistration = null;
            return null;
          }).toJS;
          final disposeParityProviderRegistration = vscode.commands
              .registerCommand(
                _disposeParityProviderCommand,
                toHostCallback(disposeParityProvider),
              );
          _addSubscription(context, disposeParityProviderRegistration);

          final hostFetchProbe = ((JSAny? portValue) {
            final port = (portValue! as JSNumber).toDartInt;
            return toHostPromise(
              hostFetch('http://127.0.0.1:$port/ping').then(
                (response) => '${response.status}:${response.body}'.toJS,
              ),
            );
          }).toJS;
          final hostFetchProbeRegistration = vscode.commands.registerCommand(
            'flutter-vscode.host-test.hostFetchProbe',
            toHostCallback(hostFetchProbe),
          );
          _addSubscription(context, hostFetchProbeRegistration);

          final failAsync = (() {
            return toHostPromise(
              Future<JSAny?>.error(
                StateError('Dart command failed intentionally'),
                StackTrace.current,
              ),
            );
          }).toJS;
          final failAsyncRegistration = vscode.commands.registerCommand(
            _failAsyncCommand,
            toHostCallback(failAsync),
          );
          _addSubscription(context, failAsyncRegistration);

          JSAny? failSyncCallback() {
            throw StateError('Dart synchronous failure');
          }

          final failSync = failSyncCallback.toJS;
          final failSyncRegistration = vscode.commands.registerCommand(
            _failSyncCommand,
            toHostCallback(failSync),
          );
          _addSubscription(context, failSyncRegistration);

          final provideHover =
              (
                    parity.TextDocument document,
                    parity.Position position,
                    parity.CancellationToken token,
                  ) {
                    _hoverDocumentMatchedEvent = identical(
                      _lastOpenedDocument,
                      document,
                    );
                    _hoverReceivedCancellationToken =
                        !token.isCancellationRequested;
                    final contents = vscode.MarkdownString.new$(
                      'Hover from Dart at '
                              '${position.line.toInt()}:'
                              '${position.character.toInt()}'
                          .toJS,
                    );
                    final range = vscode.Range.new$$2(
                      0.toJS,
                      0.toJS,
                      0.toJS,
                      5.toJS,
                    );
                    return vscode.Hover.new$(contents, range);
                  }
                  .toJS;
          final provider = parity.HoverProvider.lit$(
            provideHover: toHostCallback(provideHover),
          );
          final providerRegistration = vscode.languages.registerHoverProvider(
            'plaintext'.toJS,
            provider,
          );
          _addSubscription(context, providerRegistration);
          // The packaged driver activates through a JSON document because a
          // fresh harness window may already hold an untitled plaintext
          // editor, which would activate onLanguage:plaintext at startup.
          final jsonProviderRegistration = vscode.languages
              .registerHoverProvider('json'.toJS, provider);
          _addSubscription(context, jsonProviderRegistration);

          final onDidOpenDocument = ((parity.TextDocument document) {
            _openEventCount += 1;
            _lastOpenedDocument = document;
          }).toJS;
          _openEventSubscription = vscode.workspace.onDidOpenTextDocument.call(
            onDidOpenDocument,
          );

          final eventCount = (() => _openEventCount.toJS).toJS;
          final eventCountRegistration = vscode.commands.registerCommand(
            _eventCountCommand,
            toHostCallback(eventCount),
          );
          _addSubscription(context, eventCountRegistration);

          final identityResult = (() => _hoverDocumentMatchedEvent.toJS).toJS;
          final identityRegistration = vscode.commands.registerCommand(
            _identityCommand,
            toHostCallback(identityResult),
          );
          _addSubscription(context, identityRegistration);

          final cancellationTokenResult =
              (() => _hoverReceivedCancellationToken.toJS).toJS;
          final cancellationTokenRegistration = vscode.commands.registerCommand(
            _hoverReceivedCancellationTokenCommand,
            toHostCallback(cancellationTokenResult),
          );
          _addSubscription(context, cancellationTokenRegistration);

          final unsubscribe = _disposeOpenEventSubscription.toJS;
          final unsubscribeRegistration = vscode.commands.registerCommand(
            _unsubscribeCommand,
            toHostCallback(unsubscribe),
          );
          _addSubscription(context, unsubscribeRegistration);

          final openFlutterView = (() => toHostPromise(
            _openView(context, vscode),
          )).toJS;
          final openFlutterViewRegistration = vscode.commands.registerCommand(
            _openFlutterViewCommand,
            toHostCallback(openFlutterView),
          );
          _addSubscription(context, openFlutterViewRegistration);
          final probeFlutterViewProtocol = (() => toHostPromise(
            _openView(context, vscode, fixtureMode: protocolProbeMode),
          )).toJS;
          final probeFlutterViewProtocolRegistration = vscode.commands
              .registerCommand(
                _probeFlutterViewProtocolCommand,
                toHostCallback(probeFlutterViewProtocol),
              );
          _addSubscription(context, probeFlutterViewProtocolRegistration);
          if (_activationFailureFlag?.toDart == '1') {
            throw StateError('Dart host activation failed intentionally');
          }
          return null;
        } catch (error) {
          _disposeOpenEventSubscription();
          Error.throwWithStackTrace(
            StateError('Host activation failed: $error'),
            StackTrace.current,
          );
        }
      }),
    );
  }

  JSPromise<JSAny?> deactivate() {
    return Future<JSAny?>(() {
      _disposeOpenEventSubscription();
      return null;
    }).toJS;
  }

  void _disposeOpenEventSubscription() {
    _openEventSubscription?.dispose();
    _openEventSubscription = null;
  }

  Future<JSAny?> _openView(
    parity.ExtensionContext context,
    parity.VscodeApi vscode, {
    String fixtureMode = '',
  }) async {
    final protocolProbe = fixtureMode == protocolProbeMode
        ? _ProtocolProbe()
        : null;
    final renderObservationToken = _secureToken();
    final scriptNonce = _secureToken();
    final expectedRenderedContent = protocolProbe == null
        ? 'hello from Host Dart'
        : 'Protocol probe completed';
    var hostObservedRenderCount = 0;
    int? viewColdStartMs;
    String? hostObservedRenderedContent;
    String? observedContentSecurityPolicy;
    late final _ViewResources resources;
    late final FlutterViewHost viewHost;
    viewHost = FlutterViewHost.open(
      context: context,
      vscode: vscode,
      viewName: 'main',
      viewType: 'flutter-vscode.host-test.mainPanel',
      title: 'Flutter View Fixture',
      extraHead: _fixtureHead(
        fixtureMode: fixtureMode,
        scriptNonce: scriptNonce,
        renderObservationToken: renderObservationToken,
        expectedRenderedContent: expectedRenderedContent,
      ),
      scriptNonce: scriptNonce,
      onIncomingMessage: protocolProbe?.observeIncoming,
      onClosed: () {
        unawaited(
          resources
              .cleanup(panelAlreadyDisposed: true)
              .then<void>((_) {}, onError: (Object _, StackTrace _) {}),
        );
      },
      operations: [
        _readHostValueOperation.bind((request) {
          if (request.key != 'greeting') {
            throw ArgumentError.value(request.key, 'key');
          }
          return 'hello from Host Dart';
        }),
        const ViewOperation<Object?, Object?>(
          name: failingOperationName,
          encodeArguments: encodeFixtureSnapshot,
          decodeArguments: decodeFixtureSnapshot,
          encodeResult: encodeFixtureSnapshot,
          decodeResult: decodeFixtureSnapshot,
        ).bind(
          (_) => throw StateError('Host operation failed intentionally'),
        ),
        _wrongNonceOperation.bind((value) {
          protocolProbe?.wrongNonceHandlerInvocations += 1;
          return value;
        }),
        _malformedSchemaOperation.bind((value) {
          protocolProbe?.malformedSchemaHandlerInvocations += 1;
          return value;
        }),
        _unsupportedVersionOperation.bind((value) {
          protocolProbe?.unsupportedVersionHandlerInvocations += 1;
          return value;
        }),
        _pendingAcrossReloadOperation.bind((_) {
          final result = Completer<Object?>();
          protocolProbe!.pendingResults.add(result);
          return result.future;
        }),
        _protocolProbePhaseOperation.bind((_) {
          protocolProbe!.phaseInvocations += 1;
          return protocolProbe.phaseInvocations == 1 ? 'reload' : 'complete';
        }),
        _requestReloadOperation.bind((_) {
          protocolProbe!
            ..pendingRequestsBeforeReload =
                viewHost.session.pendingRequestCount - 1
            ..reloadCount += 1;
          unawaited(Future<void>(viewHost.reload));
          return null;
        }),
        _confirmRenderObservationOperation.bind((observation) {
          if (observation.token != renderObservationToken) {
            throw StateError(
              'Flutter View did not confirm the Host-owned render token.',
            );
          }
          if (observation.content != expectedRenderedContent) {
            throw StateError(
              'Host DOM observer found "${observation.content}" instead of '
              '"$expectedRenderedContent".',
            );
          }
          hostObservedRenderCount += 1;
          viewColdStartMs ??= DateTime.now()
              .difference(viewHost.loadStartedAt)
              .inMilliseconds;
          hostObservedRenderedContent = observation.content;
          observedContentSecurityPolicy = observation.contentSecurityPolicy;
          return true;
        }),
      ],
    );
    resources = _ViewResources(viewHost);
    final session = viewHost.session;
    final transport = viewHost.transport;
    JSAny? result;
    Object? firstError;
    StackTrace? firstStackTrace;
    try {
      await _awaitViewMilestone(session.ready, transport);
      final rendered = await _awaitViewMilestone(session.rendered, transport);
      if (hostObservedRenderedContent != expectedRenderedContent) {
        throw StateError(
          'Host did not independently observe the expected rendered content.',
        );
      }
      if (protocolProbe != null) {
        protocolProbe.hostPendingRequestsBeforeShutdown =
            session.pendingRequestCount;
      }
      final viewCloseReport = await _awaitViewMilestone(
        session.shutdown(),
        transport,
      );
      final hostCloseReport = await _awaitViewMilestone(
        session.closed,
        transport,
      );
      final hostReceivingSubscriptions = transport.receivingSubscriptionCount;
      if (hostReceivingSubscriptions != 0) {
        throw StateError(
          'Host retained its native Flutter View receiver after session close.',
        );
      }
      if (protocolProbe != null) {
        protocolProbe.hostPendingRequestsAtClose =
            hostCloseReport.pendingRequestCount;
        for (final pendingResult in protocolProbe.pendingResults) {
          if (!pendingResult.isCompleted) {
            pendingResult.complete(null);
          }
        }
        await Future.wait(
          protocolProbe.pendingResults.map((pending) => pending.future),
        );
        await _awaitNoPendingHostOperations(session);
      }
      if (viewCloseReport.pendingRequestCount != 0 ||
          viewCloseReport.subscriptionCount != 0) {
        throw StateError(
          'Flutter View reported live protocol work during shutdown.',
        );
      }
      await resources.cleanup();
      if (resources.pendingRequestCount != 0 ||
          resources.subscriptionCount != 0 ||
          resources.pendingSendCount != 0) {
        throw StateError('Host retained Flutter View resources after cleanup.');
      }
      final report = <String, Object?>{
        'renderedValue': rendered,
        'closed': true,
        'viewPendingRequests': viewCloseReport.pendingRequestCount,
        'viewSubscriptions': viewCloseReport.subscriptionCount,
        'hostPendingRequests': resources.pendingRequestCount,
        'hostSubscriptions': resources.subscriptionCount,
        'hostPendingSends': resources.pendingSendCount,
        'hostReceivingSubscriptions': hostReceivingSubscriptions,
        'hostObservedRenderCount': hostObservedRenderCount,
        'viewColdStartMs': viewColdStartMs,
        'hostObservedRenderedContent': hostObservedRenderedContent,
        'contentSecurityPolicy': observedContentSecurityPolicy,
      };
      if (fixtureMode == protocolProbeMode) {
        if (rendered case <Object?, Object?>{
          'disallowedOperationCode': final String code,
          'structuredErrorCode': final String errorCode,
          'structuredErrorMessage': final String errorMessage,
        }) {
          report
            ..['disallowedOperationCode'] = code
            ..['structuredErrorCode'] = errorCode
            ..['structuredErrorMessage'] = errorMessage
            ..['wrongNonceFramesInjected'] =
                protocolProbe!.wrongNonceFramesInjected
            ..['wrongNonceHandlerInvocations'] =
                protocolProbe.wrongNonceHandlerInvocations
            ..['malformedSchemaFramesInjected'] =
                protocolProbe.malformedSchemaFramesInjected
            ..['malformedSchemaHandlerInvocations'] =
                protocolProbe.malformedSchemaHandlerInvocations
            ..['unsupportedVersionFramesInjected'] =
                protocolProbe.unsupportedVersionFramesInjected
            ..['unsupportedVersionHandlerInvocations'] =
                protocolProbe.unsupportedVersionHandlerInvocations
            ..['readyFramesObserved'] = protocolProbe.readyFramesObserved
            ..['reloadCount'] = protocolProbe.reloadCount
            ..['pendingRequestsBeforeReload'] =
                protocolProbe.pendingRequestsBeforeReload
            ..['hostPendingRequestsBeforeShutdown'] =
                protocolProbe.hostPendingRequestsBeforeShutdown
            ..['hostPendingRequestsAtClose'] =
                protocolProbe.hostPendingRequestsAtClose;
        } else {
          throw StateError(
            'The Flutter View protocol probe did not return its exact report.',
          );
        }
      }
      result = report.jsify();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    } finally {
      try {
        await resources.cleanup();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError, firstStackTrace!);
    }
    return result;
  }
}

final class _ProtocolProbe {
  int wrongNonceFramesInjected = 0;
  int wrongNonceHandlerInvocations = 0;
  int malformedSchemaFramesInjected = 0;
  int malformedSchemaHandlerInvocations = 0;
  int unsupportedVersionFramesInjected = 0;
  int unsupportedVersionHandlerInvocations = 0;
  int readyFramesObserved = 0;
  int reloadCount = 0;
  int pendingRequestsBeforeReload = 0;
  int hostPendingRequestsBeforeShutdown = 0;
  int hostPendingRequestsAtClose = 0;
  int phaseInvocations = 0;
  final List<Completer<Object?>> pendingResults = [];

  void observeIncoming(Object? value) {
    if (value case final Map<Object?, Object?> frame
        when frame['kind'] == 'ready') {
      readyFramesObserved += 1;
    }
    if (value case final Map<Object?, Object?> frame
        when frame['kind'] == 'call' &&
            frame['operation'] == wrongNonceOperationName &&
            frame['nonce'] == 'fixture-invalid-active-nonce') {
      wrongNonceFramesInjected += 1;
    }
    if (value case final Map<Object?, Object?> frame
        when frame['kind'] == 'call' &&
            frame['operation'] == malformedSchemaOperationName &&
            frame['unexpected'] == true) {
      malformedSchemaFramesInjected += 1;
    }
    if (value case final Map<Object?, Object?> frame
        when frame['kind'] == 'call' &&
            frame['operation'] == unsupportedVersionOperationName &&
            frame['version'] == 3) {
      unsupportedVersionFramesInjected += 1;
    }
  }
}

Future<void> _awaitNoPendingHostOperations(HostViewSession session) async {
  for (var attempt = 0; attempt < 100; attempt += 1) {
    if (session.pendingRequestCount == 0) {
      return;
    }
    await Future<void>.delayed(Duration.zero);
  }
  throw StateError(
    'Host operation handlers did not settle after their results completed.',
  );
}

Future<T> _awaitViewMilestone<T>(
  Future<T> milestone,
  HostWebviewTransport transport,
) {
  return Future.any<T>([
    milestone,
    transport.failure,
  ]).timeout(
    // Generous on purpose: a cold macOS runner spends real time in
    // Gatekeeper and first-launch Electron caches before the webview's
    // first frame, and the assertion here is that the view boots, not that
    // it boots fast -- cold-start latency is measured and reported
    // separately. The first native macOS run timed out at 30 seconds and
    // passed warm; 120 seconds then timed out when the local workflow
    // aggregate ran this step right after three container jobs on the
    // same machine, while the standalone gate rendered in under 200ms.
    // CI runners are always cold and the local mirror is colder still.
    const Duration(seconds: 300),
  );
}

final class _ViewResources {
  _ViewResources(this.viewHost);

  final FlutterViewHost viewHost;
  Future<void>? _cleanup;
  var _panelAlreadyDisposed = false;

  int get pendingRequestCount => viewHost.session.pendingRequestCount;

  int get pendingSendCount => viewHost.transport.pendingSendCount;

  int get subscriptionCount =>
      viewHost.session.subscriptionCount + viewHost.transport.subscriptionCount;

  Future<void> cleanup({bool panelAlreadyDisposed = false}) {
    _panelAlreadyDisposed |= panelAlreadyDisposed;
    return _cleanup ??= _cleanupOwned();
  }

  Future<void> _cleanupOwned() async {
    Object? firstError;
    StackTrace? firstStackTrace;

    Future<void> preserveFirstError(FutureOr<void> Function() action) async {
      try {
        await action();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    await preserveFirstError(viewHost.session.close);
    await preserveFirstError(() async {
      await viewHost.session.closed;
    });
    await preserveFirstError(
      () => viewHost.transport.close().timeout(const Duration(seconds: 5)),
    );
    if (!_panelAlreadyDisposed) {
      await preserveFirstError(_disposeHostPanel);
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  void _disposeHostPanel() {
    viewHost.panel.dispose();
  }
}

/// Fixture-owned `<head>` fragments composed into [FlutterViewHost.open]:
/// probe-selection and render-observation metas plus the adversity
/// scripts, all carrying the fixture's CSP [scriptNonce].
List<String> _fixtureHead({
  required String fixtureMode,
  required String scriptNonce,
  required String renderObservationToken,
  required String expectedRenderedContent,
}) {
  final expectedContentMeta =
      '<meta name="$hostExpectedRenderContentMetaName" '
      'content="${_html(expectedRenderedContent)}">';
  return [
    '<meta name="$fixtureModeMetaName" content="${_html(fixtureMode)}">',
    '<meta name="$hostRenderObservationMetaName" content="">',
    expectedContentMeta,
    if (fixtureMode == protocolProbeMode) _faultInjectionScript(scriptNonce),
    _renderObserverScript(
      scriptNonce: scriptNonce,
      renderObservationToken: renderObservationToken,
    ),
  ];
}

/// Fixture-only fault injection: mutates protocol frames inside the
/// Flutter View before delegating to VS Code's native postMessage
/// boundary.
String _faultInjectionScript(String scriptNonce) {
  return '''
<script nonce="$scriptNonce">
    (() => {
      const acquireNativeVsCodeApi = globalThis.acquireVsCodeApi;
      globalThis.acquireVsCodeApi = () => {
        const nativeApi = acquireNativeVsCodeApi();
        return {
          postMessage(message) {
            let outgoing = message;
            if (message?.kind === 'call') {
              switch (message.operation) {
                case '$wrongNonceOperationName':
                  outgoing = {
                    ...message,
                    nonce: 'fixture-invalid-active-nonce',
                  };
                  break;
                case '$malformedSchemaOperationName':
                  outgoing = {...message, unexpected: true};
                  break;
                case '$unsupportedVersionOperationName':
                  outgoing = {...message, version: 3};
                  break;
              }
            }
            nativeApi.postMessage(outgoing);
          },
          getState() {
            return nativeApi.getState();
          },
          setState(state) {
            return nativeApi.setState(state);
          },
        };
      };
    })();
  </script>''';
}

/// Fixture-only DOM observer that stamps the Host-owned render token
/// once the expected content is visibly rendered.
String _renderObserverScript({
  required String scriptNonce,
  required String renderObservationToken,
}) {
  return '''
<script nonce="$scriptNonce">
    (() => {
      const marker = document.querySelector(
        'meta[name="$hostRenderObservationMetaName"]',
      );
      const expected = document.querySelector(
        'meta[name="$hostExpectedRenderContentMetaName"]',
      )?.getAttribute('content') ?? '';
      const observeRenderedContent = () => {
        const renderedNodes = Array.from(document.querySelectorAll(
          '[$hostRenderedContentAttributeName]',
        ));
        const matchingNode = renderedNodes.find((node) => {
          const markedContent = node.getAttribute(
            '$hostRenderedContentAttributeName',
          );
          const textContent = node.textContent?.trim() ?? '';
          const bounds = node.getBoundingClientRect();
          return markedContent === expected &&
            textContent === expected &&
            bounds.width > 0 &&
            bounds.height > 0;
        });
        if (matchingNode === undefined) {
          requestAnimationFrame(observeRenderedContent);
          return;
        }
        const observedContent = matchingNode.textContent?.trim() ?? '';
        marker.setAttribute('content', '$renderObservationToken');
        marker.setAttribute('data-rendered-content', observedContent);
      };
      requestAnimationFrame(observeRenderedContent);
    })();
  </script>''';
}

String _secureToken() {
  final random = Random.secure();
  return List.generate(
    24,
    (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
}

/// Adds [registration] to the native extension subscription collection.
void _addSubscription(parity.ExtensionContext context, JSObject registration) {
  context.own(registration);
}

String _html(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&#39;');

void main() {
  registerHostExports(createJSInteropWrapper(_VSCodeHostExtension()));
}
