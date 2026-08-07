import 'dart:async';
import 'dart:convert';
import 'dart:math';

part 'view_protocol/frames.dart';
part 'view_protocol/host_session.dart';
part 'view_protocol/view_session.dart';

/// Stable failures produced by version-1 Host/Flutter View sessions.
enum ViewProtocolErrorCode {
  /// The peer selected a protocol version this runtime cannot speak.
  unsupportedVersion('unsupported_version'),

  /// A frame did not match the exact schema for its declared kind.
  invalidMessage('invalid_message'),

  /// A frame belongs to another Host/Flutter View session.
  sessionMismatch('session_mismatch'),

  /// A frame did not carry the nonce active for its session phase.
  nonceMismatch('nonce_mismatch'),

  /// A call named an operation Host Dart did not expose.
  operationNotAllowed('operation_not_allowed'),

  /// A request ID was reused within one active session.
  duplicateRequest('duplicate_request'),

  /// Host Dart failed while executing an allowed operation.
  operationFailed('operation_failed'),

  /// The session closed before an operation could complete.
  sessionClosed('session_closed'),

  /// An in-flight request was cancelled by its initiator.
  cancelled('cancelled');

  const ViewProtocolErrorCode(this.wireName);

  /// Stable value sent across the runtime seam.
  final String wireName;
}

/// A structured failure raised at the Host/Flutter View protocol seam.
final class ViewProtocolException implements Exception {
  /// Creates a protocol failure with a stable [code].
  factory ViewProtocolException(
    ViewProtocolErrorCode code,
    String message, {
    Object? details,
  }) {
    if (message.isEmpty) {
      throw const ViewProtocolException._(
        ViewProtocolErrorCode.invalidMessage,
        'A structured protocol error message must not be empty.',
      );
    }
    if (!_isProtocolValue(details)) {
      throw const ViewProtocolException._(
        ViewProtocolErrorCode.invalidMessage,
        'Structured protocol error details must be a protocol-safe snapshot.',
      );
    }
    return ViewProtocolException._(
      code,
      message,
      details: _protocolSnapshot(details),
    );
  }

  const ViewProtocolException._(this.code, this.message, {this.details});

  /// Machine-readable failure category.
  final ViewProtocolErrorCode code;

  /// Actionable explanation for a developer.
  final String message;

  /// Optional protocol-safe diagnostic context.
  final Object? details;

  @override
  String toString() => '${code.wireName}: $message';
}

/// Carries protocol messages across a Host Dart/Flutter View runtime seam.
abstract interface class ViewTransport {
  /// Messages received from the other runtime.
  Stream<Object?> get messages;

  /// Sends [message] to the other runtime.
  ///
  /// Completion means the transport finished the strongest delivery handoff
  /// its native API exposes. The Host adapter includes VS Code's asynchronous
  /// acceptance result; the Flutter View API is void and can confirm only its
  /// synchronous handoff. A failure that the transport can observe must
  /// complete with an error rather than use a separate side channel.
  Future<void> send(Object? message);
}

/// Optional receive-side lifecycle for transports with native listeners.
///
/// Sessions close and await this receive side before measuring their final
/// resource counts. The transport must keep [ViewTransport.send] available
/// until the final `closing` frame has been delivered.
abstract interface class ViewTransportLifecycle {
  /// Native receive subscriptions that are still active.
  int get receivingSubscriptionCount;

  /// Stops native message receipt without disabling final outbound delivery.
  Future<void> closeReceiving();
}

/// A connected pair of in-memory transports for deterministic tests.
final class InMemoryViewTransportPair {
  /// Creates two connected transport endpoints.
  factory InMemoryViewTransportPair() {
    final hostMessages = StreamController<Object?>.broadcast(sync: true);
    final viewMessages = StreamController<Object?>.broadcast(sync: true);
    return InMemoryViewTransportPair._(
      _InMemoryViewTransport(hostMessages.stream, viewMessages.add),
      _InMemoryViewTransport(viewMessages.stream, hostMessages.add),
    );
  }

  const InMemoryViewTransportPair._(this.host, this.view);

  /// The endpoint used by Host Dart.
  final ViewTransport host;

  /// The endpoint used by the Flutter View.
  final ViewTransport view;
}

typedef _HostViewOperation = FutureOr<Object?> Function(Object? arguments);

/// Encodes a typed value as a protocol-safe snapshot.
typedef ViewValueEncoder<T> = Object? Function(T value);

/// Decodes and validates a protocol snapshot as a typed value.
typedef ViewValueDecoder<T> = T Function(Object? value);

/// A structural call seam over one connected Flutter View session.
///
/// Function-typed on purpose: an Extension Project's shared package
/// assembles its [ViewOperation]s against one generated copy of this
/// protocol while the Flutter View's session may come from another
/// (`package:flutter_vscode/view.dart`), and two copies of a library
/// never share nominal types. [FlutterViewSession.operationCaller]
/// and [ViewOperation.callThrough] meet at this plain function type,
/// so one shared operation declaration serves both runtimes.
typedef ViewOperationCaller =
    Future<Object?> Function(
      String operation,
      Object? arguments,
    );

/// A typed, allowlistable operation shared by Host Dart and a Flutter View.
///
/// The codecs are deterministic application code. This contract adds no
/// reflection or public generic dispatcher: its name is matched internally
/// against the Host session's explicit allowlist.
final class ViewOperation<Request, Result> {
  /// Creates a typed operation over protocol-safe snapshot values.
  const ViewOperation({
    required String name,
    required ViewValueEncoder<Request> encodeArguments,
    required ViewValueDecoder<Request> decodeArguments,
    required ViewValueEncoder<Result> encodeResult,
    required ViewValueDecoder<Result> decodeResult,
  }) : this._(
         name,
         encodeArguments,
         decodeArguments,
         encodeResult,
         decodeResult,
       );

  const ViewOperation._(
    this._name,
    this._encodeArguments,
    this._decodeArguments,
    this._encodeResult,
    this._decodeResult,
  );

  /// A typed operation whose request side carries no value.
  ///
  /// The supplied void codecs encode `null` and reject any non-null
  /// payload, replacing the hand-written encode-null/decode-guard pair
  /// every no-argument operation otherwise repeats.
  static ViewOperation<void, Result> noArgs<Result>(
    String name, {
    required ViewValueEncoder<Result> encodeResult,
    required ViewValueDecoder<Result> decodeResult,
  }) => ViewOperation<void, Result>._(
    name,
    _encodeVoidValue,
    _decodeVoidValue,
    encodeResult,
    decodeResult,
  );

  /// A typed operation whose result side carries no value.
  ///
  /// The supplied void codecs encode `null` and reject any non-null
  /// payload, replacing the hand-written encode-null/decode-guard pair
  /// every acknowledgement-style operation otherwise repeats.
  static ViewOperation<Request, void> noResult<Request>(
    String name, {
    required ViewValueEncoder<Request> encodeArguments,
    required ViewValueDecoder<Request> decodeArguments,
  }) => ViewOperation<Request, void>._(
    name,
    encodeArguments,
    decodeArguments,
    _encodeVoidValue,
    _decodeVoidValue,
  );

  static Object? _encodeVoidValue(void value) => null;

  static void _decodeVoidValue(Object? value) {
    if (value != null) {
      throw _invalidMessage('A void operation value must be null.');
    }
  }

  final String _name;
  final ViewValueEncoder<Request> _encodeArguments;
  final ViewValueDecoder<Request> _decodeArguments;
  final ViewValueEncoder<Result> _encodeResult;
  final ViewValueDecoder<Result> _decodeResult;

  /// Adapts a typed Host Dart [handler] to an allowlisted protocol operation.
  ViewOperationBinding bind(
    FutureOr<Result> Function(Request request) handler,
  ) {
    _requireNonEmptyProtocolIdentifier(_name, 'operation name');
    return ViewOperationBinding._(
      _name,
      (arguments) async {
        final request = _decode(
          _decodeArguments,
          arguments,
          'arguments',
        );
        return _encodeResult(await handler(request));
      },
    );
  }

  /// Calls this operation through [session] with typed arguments and result.
  Future<Result> call(FlutterViewSession session, Request arguments) async {
    _requireNonEmptyProtocolIdentifier(_name, 'operation name');
    final value = await session._call(
      _name,
      arguments: _encodeArguments(arguments),
    );
    return _decode(_decodeResult, value, 'result');
  }

  /// Calls this operation through [caller] — the cross-copy twin of
  /// [call].
  ///
  /// Use it when this operation value and the connected session come
  /// from two generated copies of this protocol; see
  /// [ViewOperationCaller] for the seam.
  Future<Result> callThrough(
    ViewOperationCaller caller,
    Request arguments,
  ) async {
    _requireNonEmptyProtocolIdentifier(_name, 'operation name');
    final value = await caller(_name, _encodeArguments(arguments));
    return _decode(_decodeResult, value, 'result');
  }

  T _decode<T>(ViewValueDecoder<T> decoder, Object? value, String role) {
    try {
      return decoder(value);
    } on ViewProtocolException {
      rethrow;
    } on Object catch (error) {
      throw ViewProtocolException(
        ViewProtocolErrorCode.invalidMessage,
        'The "$_name" operation $role did not match its typed schema.',
        details: '$error',
      );
    }
  }
}

/// An opaque typed operation binding accepted by [HostViewSession.connect].
///
/// Obtain bindings from [ViewOperation.bind]. The private constructor prevents
/// callers from assembling raw string/object dispatch entries.
final class ViewOperationBinding {
  const ViewOperationBinding._(this._name, this._handler);

  final String _name;
  final _HostViewOperation _handler;
}

/// A total codec for one field kind of a declared view-value schema.
///
/// Kinds compose: [orNull] admits `null`, [listOf] repeats a kind, and
/// [nested] embeds another [ViewValueSchema] — lazily, so a schema can
/// reference itself for recursive trees. Scalar kinds are also usable
/// directly as operation payload codecs via [encode] and [decode].
final class ViewValueKind<F> {
  const ViewValueKind._(this._encode, this._decode);

  /// String values.
  static const ViewValueKind<String> string = ViewValueKind._(
    _passValue,
    _decodeString,
  );

  /// Integer values.
  static const ViewValueKind<int> integer = ViewValueKind._(
    _passValue,
    _decodeInt,
  );

  /// Boolean values.
  static const ViewValueKind<bool> boolean = ViewValueKind._(
    _passValue,
    _decodeBool,
  );

  /// Double values.
  ///
  /// Decoding accepts any wire `num`: compiled JavaScript does not
  /// preserve the int/double distinction for whole numbers.
  static const ViewValueKind<double> doubleNumber = ViewValueKind._(
    _passValue,
    _decodeDouble,
  );

  /// This kind, additionally admitting `null`.
  ViewValueKind<F?> get orNull => ViewValueKind<F?>._(
    (value) => value == null ? null : _encode(value),
    (value) => value == null ? null : _decode(value),
  );

  /// A list whose items all match [of].
  ///
  /// A failing item is rejected naming its index.
  static ViewValueKind<List<F>> listOf<F>(ViewValueKind<F> of) =>
      ViewValueKind<List<F>>._(
        (value) => [for (final item in value) of._encode(item)],
        (value) {
          if (value is! List<Object?>) {
            throw const FormatException('Expected a list value.');
          }
          final items = <F>[];
          for (var index = 0; index < value.length; index += 1) {
            try {
              items.add(of._decode(value[index]));
            } on FormatException catch (error) {
              throw FormatException(
                'The item at index $index: ${error.message}',
              );
            }
          }
          return List.unmodifiable(items);
        },
      );

  /// A nested value declared by [schema].
  ///
  /// The schema is supplied lazily so a declaration can reference
  /// itself (directly or through [listOf]) for recursive trees.
  static ViewValueKind<F> nested<F>(ViewValueSchema<F> Function() schema) =>
      ViewValueKind<F>._(
        (value) => schema().encode(value),
        (value) => schema().decode(value),
      );

  static Object? _passValue(Object? value) => value;

  static String _decodeString(Object? value) => value is String
      ? value
      : throw const FormatException('Expected a string value.');

  static int _decodeInt(Object? value) => value is int
      ? value
      : throw const FormatException('Expected an int value.');

  static bool _decodeBool(Object? value) => value is bool
      ? value
      : throw const FormatException('Expected a bool value.');

  static double _decodeDouble(Object? value) => value is num
      ? value.toDouble()
      : throw const FormatException('Expected a double value.');

  final Object? Function(F value) _encode;
  final F Function(Object? value) _decode;

  /// Encodes [value] as a protocol-safe snapshot.
  Object? encode(F value) => _encode(value);

  /// Decodes and validates a protocol snapshot as this kind.
  F decode(Object? value) => _decode(value);
}

/// Reads one declared field's decoded value inside constructor wiring.
///
/// Returned by a schema's [ViewFieldDeclarator]; call it with the
/// [ViewDecodedFields] the constructor wiring receives.
typedef ViewFieldReader<F> = F Function(ViewDecodedFields fields);

/// Declares one schema field — wire [key], value [kind], and the
/// getter [read] — and returns the field's typed reader.
typedef ViewFieldDeclarator<T> =
    ViewFieldReader<F> Function<F>(
      String key,
      ViewValueKind<F> kind,
      F Function(T value) read,
    );

/// Decoded field values handed to a schema's constructor wiring.
final class ViewDecodedFields {
  const ViewDecodedFields._(this._values);

  final Map<String, Object?> _values;
}

/// The exact wire schema of one view-contract value type, declared
/// once.
///
/// [ViewValueSchema.new]'s callback runs once at construction: it
/// declares each field on the supplied declarator — wire key, value
/// kind, getter — and returns the constructor wiring that rebuilds a
/// [T] from decoded fields. From that single declaration the schema
/// derives [encode], [decode], and the exact-schema guard: a missing
/// key, an unexpected key, or a wrong-typed value throws a
/// [FormatException] naming the key. [encode] and [decode] tear off
/// as [ViewValueEncoder] and [ViewValueDecoder], composing directly
/// into [ViewOperation] codecs.
final class ViewValueSchema<T> {
  /// Declares a schema; see the class for the declaration contract.
  factory ViewValueSchema(
    T Function(ViewDecodedFields fields) Function(
      ViewFieldDeclarator<T> field,
    )
    declare,
  ) {
    final builder = _ViewSchemaBuilder<T>();
    final construct = declare(builder.declareField);
    builder.sealed = true;
    return ViewValueSchema._(List.unmodifiable(builder.fields), construct);
  }

  const ViewValueSchema._(this._fields, this._construct);

  final List<_ViewSchemaField<T>> _fields;
  final T Function(ViewDecodedFields fields) _construct;

  /// Encodes [value] as a protocol-safe snapshot of exactly the
  /// declared keys.
  Object? encode(T value) => <String, Object?>{
    for (final field in _fields) field.key: field.encodeFrom(value),
  };

  /// Decodes and validates a protocol snapshot against the exact
  /// declared schema.
  T decode(Object? value) {
    if (value is! Map<Object?, Object?>) {
      throw const FormatException(
        'Expected a map value carrying exactly the declared keys.',
      );
    }
    for (final field in _fields) {
      if (!value.containsKey(field.key)) {
        throw FormatException('The "${field.key}" key is missing.');
      }
    }
    if (value.length != _fields.length) {
      final declared = <Object?>{for (final field in _fields) field.key};
      final unexpected = [
        for (final key in value.keys)
          if (!declared.contains(key)) '"$key"',
      ].join(', ');
      throw FormatException('Unexpected keys: $unexpected.');
    }
    final decoded = <String, Object?>{};
    for (final field in _fields) {
      try {
        decoded[field.key] = field.decodeRaw(value[field.key]);
      } on FormatException catch (error) {
        throw FormatException('The "${field.key}" key: ${error.message}');
      }
    }
    return _construct(ViewDecodedFields._(decoded));
  }
}

final class _ViewSchemaField<T> {
  const _ViewSchemaField(this.key, this.encodeFrom, this.decodeRaw);

  final String key;
  final Object? Function(T value) encodeFrom;
  final Object? Function(Object? value) decodeRaw;
}

final class _ViewSchemaBuilder<T> {
  final List<_ViewSchemaField<T>> fields = [];
  bool sealed = false;

  ViewFieldReader<F> declareField<F>(
    String key,
    ViewValueKind<F> kind,
    F Function(T value) read,
  ) {
    if (sealed) {
      throw StateError(
        'Schema fields may be declared only inside the declaration '
        'callback.',
      );
    }
    if (fields.any((field) => field.key == key)) {
      throw ArgumentError.value(
        key,
        'key',
        'A schema field key may be declared only once.',
      );
    }
    fields.add(
      _ViewSchemaField<T>(
        key,
        (value) => kind._encode(read(value)),
        kind._decode,
      ),
    );
    return (decoded) => decoded._values[key] as F;
  }
}

/// Final protocol resource counts reported by a closing runtime.
final class ViewCloseReport {
  /// Creates an instrumented close report.
  const ViewCloseReport({
    required this.pendingRequestCount,
    required this.subscriptionCount,
  });

  /// Calls still pending after cleanup.
  final int pendingRequestCount;

  /// Transport subscriptions still active after cleanup.
  final int subscriptionCount;
}
