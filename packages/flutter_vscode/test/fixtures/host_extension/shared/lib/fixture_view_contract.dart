/// Exact name of the fixture's single Host Dart operation.
const readHostValueOperationName = 'fixture.readHostValue';

/// Operation intentionally omitted from the Host allowlist by the real-view
/// protocol probe.
const disallowedOperationName = 'fixture.notAllowed';

/// Operation whose Host handler intentionally fails for the protocol probe.
const failingOperationName = 'fixture.fail';

/// Operation whose call frame receives a wrong nonce in the protocol probe.
const wrongNonceOperationName = 'fixture.wrongNonce';

/// Operation whose call frame gains an extra field in the protocol probe.
const malformedSchemaOperationName = 'fixture.malformedSchema';

/// Operation whose call frame selects an unsupported protocol version.
const unsupportedVersionOperationName = 'fixture.unsupportedVersion';

/// Operation that remains pending while the real Flutter View reloads.
const pendingAcrossReloadOperationName = 'fixture.pendingAcrossReload';

/// Operation that tells the protocol probe whether this is its first runtime.
const protocolProbePhaseOperationName = 'fixture.protocolProbePhase';

/// Operation that asks Host Dart to reload the current real webview document.
const requestReloadOperationName = 'fixture.requestReload';

/// Operation that relays a Host-owned DOM observation token after a frame.
const confirmRenderObservationOperationName =
    'fixture.confirmRenderObservation';

/// Host-generated metadata that selects the fixture's protocol probe.
const fixtureModeMetaName = 'flutter-vscode-fixture-mode';

/// Metadata value for the fixture's real-webview protocol probe.
const protocolProbeMode = 'protocol-probe';

/// Host-generated metadata populated only by its DOM render observer.
const hostRenderObservationMetaName = 'flutter-vscode-host-render-observation';

/// Host-generated metadata naming the exact content its DOM observer expects.
const hostExpectedRenderContentMetaName =
    'flutter-vscode-host-expected-render-content';

/// Attribute attached to the visible Flutter-owned DOM rendering fixture.
const hostRenderedContentAttributeName = 'data-flutter-vscode-rendered-content';

/// Typed input accepted by the fixture's Host Dart operation.
final class ReadHostValueRequest {
  /// Creates a request for the host value identified by [key].
  const ReadHostValueRequest(this.key);

  /// Host-owned value to read.
  final String key;
}

/// Host-owned DOM observation returned independently from `reportRendered`.
final class ConfirmRenderObservationRequest {
  /// Creates an exact observation containing the Host token and DOM content.
  const ConfirmRenderObservationRequest({
    required this.token,
    required this.content,
    required this.contentSecurityPolicy,
  });

  /// Opaque token populated only by the Host-owned DOM observer.
  final String token;

  /// Exact content found in the Flutter semantics DOM.
  final String content;

  /// The Content Security Policy present in the view's own document.
  ///
  /// Read from the live webview rather than from the emitted template, so a
  /// policy VS Code rewrote, or one whose nonce does not match the script it
  /// admits, is observable instead of assumed.
  final String contentSecurityPolicy;
}

/// Encodes a typed fixture request as an exact protocol snapshot.
Object? encodeReadHostValueRequest(ReadHostValueRequest request) {
  return <String, Object?>{'key': request.key};
}

/// Validates and decodes the exact fixture request schema.
ReadHostValueRequest decodeReadHostValueRequest(Object? value) {
  if (value case <Object?, Object?>{
    'key': final String key,
  } when value.length == 1) {
    return ReadHostValueRequest(key);
  }
  throw const FormatException('Expected exactly one string key.');
}

/// Encodes the typed Host Dart result.
Object? encodeReadHostValueResult(String value) => value;

/// Validates and decodes the typed Host Dart result.
String decodeReadHostValueResult(Object? value) {
  if (value is String) {
    return value;
  }
  throw const FormatException('Expected a string host value.');
}

/// Passes a protocol-safe fixture snapshot through unchanged.
Object? encodeFixtureSnapshot(Object? value) => value;

/// Passes a validated protocol snapshot through unchanged.
Object? decodeFixtureSnapshot(Object? value) => value;

/// Encodes a Host-owned DOM render observation.
Object? encodeConfirmRenderObservationRequest(
  ConfirmRenderObservationRequest request,
) {
  return <String, Object?>{
    'token': request.token,
    'content': request.content,
    'contentSecurityPolicy': request.contentSecurityPolicy,
  };
}

/// Validates and decodes a Host-owned DOM render observation.
ConfirmRenderObservationRequest decodeConfirmRenderObservationRequest(
  Object? value,
) {
  if (value
      case <Object?, Object?>{
        'token': final String token,
        'content': final String content,
        'contentSecurityPolicy': final String contentSecurityPolicy,
      }
      when value.length == 3 &&
          token.isNotEmpty &&
          content.isNotEmpty &&
          contentSecurityPolicy.isNotEmpty) {
    return ConfirmRenderObservationRequest(
      token: token,
      content: content,
      contentSecurityPolicy: contentSecurityPolicy,
    );
  }
  throw const FormatException(
    'Expected exact non-empty render token, content, and policy fields.',
  );
}

/// Decodes a boolean fixture value.
bool decodeFixtureBool(Object? value) {
  if (value is bool) {
    return value;
  }
  throw const FormatException('Expected a boolean fixture value.');
}
