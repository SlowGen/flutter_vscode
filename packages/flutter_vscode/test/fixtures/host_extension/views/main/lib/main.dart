import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_vscode/view.dart';
import 'package:flutter_vscode_host_fixture_shared/fixture_view_contract.dart';
import 'package:web/web.dart' as web;

const _readHostValueOperation = ViewOperation<ReadHostValueRequest, String>(
  name: readHostValueOperationName,
  encodeArguments: encodeReadHostValueRequest,
  decodeArguments: decodeReadHostValueRequest,
  encodeResult: encodeReadHostValueResult,
  decodeResult: decodeReadHostValueResult,
);

const _disallowedOperation = ViewOperation<Object?, Object?>(
  name: disallowedOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
);

const _failingOperation = ViewOperation<Object?, Object?>(
  name: failingOperationName,
  encodeArguments: encodeFixtureSnapshot,
  decodeArguments: decodeFixtureSnapshot,
  encodeResult: encodeFixtureSnapshot,
  decodeResult: decodeFixtureSnapshot,
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

void main() => runApp(const _FixtureView());

class _FixtureView extends StatefulWidget {
  const _FixtureView();

  @override
  State<_FixtureView> createState() => _FixtureViewState();
}

class _FixtureViewState extends State<_FixtureView> {
  late final VSCodeViewBootstrap _bootstrap;
  var _text = 'Connecting to Host Dart…';

  @override
  void initState() {
    super.initState();
    try {
      _bootstrap = VSCodeViewBootstrap.acquire();
      _observeRun(_run());
    } on Object catch (error) {
      _showError(error);
    }
  }

  Future<void> _run() async {
    FlutterViewSession? session;
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

    try {
      final connectedSession = await _bootstrap.connect();
      session = connectedSession;
      if (_fixtureMode() == protocolProbeMode) {
        await _runProtocolProbe(connectedSession);
        return;
      }
      final value = await _readHostValueOperation.call(
        connectedSession,
        const ReadHostValueRequest('greeting'),
      );
      if (!mounted) {
        return;
      }

      final rendered = Completer<void>();
      setState(() => _text = value);
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _confirmHostObservedRender(connectedSession, value);
          await connectedSession.reportRendered(value);
          rendered.complete();
        } on Object catch (error, stackTrace) {
          rendered.completeError(error, stackTrace);
        }
      });
      await rendered.future;
      await connectedSession.closed;
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    } finally {
      final connectedSession = session;
      if (connectedSession != null) {
        await preserveFirstError(connectedSession.close);
        await preserveFirstError(() async {
          await connectedSession.closed;
        });
      }
      await preserveFirstError(_bootstrap.close);
    }
    if (firstError != null) {
      Error.throwWithStackTrace(firstError!, firstStackTrace!);
    }
  }

  Future<void> _runProtocolProbe(FlutterViewSession session) async {
    _observeExpectedSessionClose(_wrongNonceOperation.call(session, null));
    _observeExpectedSessionClose(_malformedSchemaOperation.call(session, null));
    _observeExpectedSessionClose(
      _unsupportedVersionOperation.call(session, null),
    );
    String? disallowedOperationCode;
    try {
      await _disallowedOperation.call(session, null);
    } on ViewProtocolException catch (error) {
      disallowedOperationCode = error.code.wireName;
    }
    String? structuredErrorCode;
    String? structuredErrorMessage;
    try {
      await _failingOperation.call(session, null);
    } on ViewProtocolException catch (error) {
      structuredErrorCode = error.code.wireName;
      structuredErrorMessage = error.message;
    }
    _observeExpectedSessionClose(
      _pendingAcrossReloadOperation.call(session, null),
    );
    final phase = await _protocolProbePhaseOperation.call(session, null);
    if (phase == 'reload') {
      _observeExpectedSessionClose(_requestReloadOperation.call(session, null));
      await session.closed;
      return;
    }
    if (phase != 'complete') {
      throw StateError('Host Dart returned an unknown protocol probe phase.');
    }
    final report = <String, Object?>{
      'disallowedOperationCode': disallowedOperationCode,
      'structuredErrorCode': structuredErrorCode,
      'structuredErrorMessage': structuredErrorMessage,
    };
    if (!mounted) {
      return;
    }
    final rendered = Completer<void>();
    setState(() => _text = 'Protocol probe completed');
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        await _confirmHostObservedRender(session, 'Protocol probe completed');
        await session.reportRendered(report);
        rendered.complete();
      } on Object catch (error, stackTrace) {
        rendered.completeError(error, stackTrace);
      }
    });
    await rendered.future;
    await session.closed;
  }

  void _observeExpectedSessionClose(Future<Object?> call) {
    unawaited(
      call.then<void>(
        (_) {},
        onError: (Object _, StackTrace _) {},
      ),
    );
  }

  void _observeRun(Future<void> run) {
    unawaited(
      run.then<void>(
        (_) {},
        onError: (Object error, StackTrace _) {
          try {
            _showError(error);
          } on Object {
            // The State is already gone; the asynchronous failure is observed.
          }
        },
      ),
    );
  }

  void _showError(Object error) {
    if (mounted) {
      setState(() => _text = 'Flutter View failed: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: const Color(0xFF1E1E1E),
      child: Center(
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: SizedBox(
            width: 400,
            height: 64,
            child: HtmlElementView.fromTagName(
              key: ValueKey('host-value-$_text'),
              tagName: 'div',
              onElementCreated: (element) {
                final rendered = element as web.HTMLElement;
                (rendered
                      ..textContent = _text
                      ..setAttribute(hostRenderedContentAttributeName, _text))
                    .style
                  ..color = '#f3f3f3'
                  ..fontSize = '18px'
                  ..display = 'flex'
                  ..alignItems = 'center'
                  ..justifyContent = 'center'
                  ..width = '100%'
                  ..height = '100%';
              },
            ),
          ),
        ),
      ),
    );
  }
}

String _fixtureMode() {
  final element = web.document.querySelector(
    'meta[name="$fixtureModeMetaName"]',
  );
  return (element as web.HTMLMetaElement?)?.content.trim() ?? '';
}

Future<void> _confirmHostObservedRender(
  FlutterViewSession session,
  String expectedContent,
) async {
  final deadline = DateTime.now().add(const Duration(seconds: 5));
  String token;
  do {
    final element = web.document.querySelector(
      'meta[name="$hostRenderObservationMetaName"]',
    );
    final marker = element as web.HTMLMetaElement?;
    token = marker?.content.trim() ?? '';
    final content = marker?.getAttribute('data-rendered-content')?.trim() ?? '';
    if (token.isNotEmpty && content.isNotEmpty) {
      if (content != expectedContent) {
        throw StateError(
          'Host Dart observed "$content" instead of "$expectedContent".',
        );
      }
      final policy = web.document.querySelector(
        'meta[http-equiv="Content-Security-Policy"]',
      );
      final confirmed = await _confirmRenderObservationOperation.call(
        session,
        ConfirmRenderObservationRequest(
          token: token,
          content: content,
          // Read from this document, not from the framework's template: the
          // point is what the webview was actually served.
          contentSecurityPolicy:
              (policy as web.HTMLMetaElement?)?.content.trim() ?? '',
        ),
      );
      if (!confirmed) {
        throw StateError('Host Dart rejected its render observation.');
      }
      return;
    }
    await Future<void>.delayed(const Duration(milliseconds: 20));
  } while (DateTime.now().isBefore(deadline));
  throw StateError('Host Dart did not observe a rendered Flutter surface.');
}
