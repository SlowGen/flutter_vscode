/// The Host Dart runtime seam: error mapping, callback wrapping, promise
/// bridging, and the host `fetch` binding.
///
/// Framework code, not generated code. The two pieces that genuinely belong
/// to one extension -- the source-map stack mapper and the callback wrapper,
/// both keyed by that extension's collision-resistant global -- are injected
/// by its generated runtime through [installHostRuntime]. Everything else
/// lives here once, analyzed and testable.
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// Maps a host stack trace back onto Dart source frames.
typedef HostStackMapper = JSString Function(String stack);

/// Wraps a callback so synchronous throws keep mapped Dart frames.
typedef HostCallbackWrapper = JSFunction Function(JSFunction callback);

HostStackMapper? _installedStackMapper;
HostCallbackWrapper? _installedCallbackWrapper;

/// Installs the per-extension interop bindings.
///
/// A project's generated runtime calls this during activation: the JavaScript
/// globals are keyed to that extension, the code that uses them is not.
void installHostRuntime({
  required HostStackMapper mapStack,
  required HostCallbackWrapper wrapCallback,
}) {
  _installedStackMapper = mapStack;
  _installedCallbackWrapper = wrapCallback;
}

JSString _mapHostStack(String stack) {
  final mapper = _installedStackMapper;
  return mapper == null ? stack.toJS : mapper(stack);
}

JSFunction _wrapHostCallback(JSFunction callback) {
  final wrapper = _installedCallbackWrapper;
  return wrapper == null ? callback : wrapper(callback);
}

/// Native JavaScript error used to preserve Dart failure details.
@JS('Error')
extension type JavaScriptError._(JSObject _) implements JSObject {
  /// Creates an error with [message].
  external factory JavaScriptError(JSString message);

  /// Host-visible stack trace.
  external JSString get stack;

  /// Replaces the host-visible stack trace.
  external set stack(JSString value);
}

/// Creates a native host error whose stack retains mapped Dart source frames.
JavaScriptError toHostError(Object error, StackTrace stackTrace) {
  final hostError = JavaScriptError(error.toString().toJS);
  final stack = '${hostError.stack.toDart}\n$stackTrace';
  hostError.stack = _mapHostStack(stack);
  return hostError;
}

/// Wraps [callback] so synchronous throws retain mapped Dart source frames.
JSFunction toHostCallback(JSFunction callback) => _wrapHostCallback(callback);

/// One HTTP response snapshot from the Extension Host's global `fetch`.
final class HostFetchResponse {
  /// Creates a response snapshot.
  const HostFetchResponse({required this.status, required this.body});

  /// HTTP status code.
  final int status;

  /// Response body decoded as text.
  final String body;

  /// Whether [status] is in the 2xx range.
  bool get ok => status >= 200 && status < 300;
}

@JS('fetch')
external JSPromise<JSObject> _hostGlobalFetch(JSString url, JSObject init);

/// Performs an HTTP request with the Extension Host's global `fetch`.
///
/// The supported host network path: Node's WHATWG `fetch`, bound by the
/// generated runtime and returned as a protocol-safe snapshot.
Future<HostFetchResponse> hostFetch(
  String url, {
  String method = 'GET',
  Map<String, String> headers = const {},
  String? body,
}) async {
  final init = JSObject()..setProperty('method'.toJS, method.toJS);
  if (headers.isNotEmpty) {
    final headerBag = JSObject();
    for (final entry in headers.entries) {
      headerBag.setProperty(entry.key.toJS, entry.value.toJS);
    }
    init.setProperty('headers'.toJS, headerBag);
  }
  if (body != null) {
    init.setProperty('body'.toJS, body.toJS);
  }
  final response = await _hostGlobalFetch(url.toJS, init).toDart;
  final status = (response.getProperty('status'.toJS)! as JSNumber).toDartInt;
  final text =
      await (response.callMethod('text'.toJS)! as JSPromise<JSString>).toDart;
  return HostFetchResponse(status: status, body: text.toDart);
}

/// Converts [future] to a host promise while retaining Dart stack frames.
JSPromise<T> toHostPromise<T extends JSAny?>(Future<T> future) {
  return JSPromise<T>(
    (JSFunction resolve, JSFunction reject) {
      unawaited(
        future.then<void>(
          (value) {
            resolve.callAsFunction(resolve, value);
          },
          onError: (Object error, StackTrace stackTrace) {
            reject.callAsFunction(
              reject,
              toHostError(error, stackTrace),
            );
          },
        ),
      );
    }.toJS,
  );
}
