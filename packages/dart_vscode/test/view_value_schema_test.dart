import 'package:dart_vscode/view_protocol.dart';
import 'package:test/test.dart';

/// A ThemeReport-shaped contract type: string plus int-or-null.
final class _Report {
  const _Report({required this.kind, this.editorBackground});

  final String kind;
  final int? editorBackground;
}

final ViewValueSchema<_Report> _reportSchema = ViewValueSchema((field) {
  final kind = field('kind', ViewValueKind.string, (report) => report.kind);
  final editorBackground = field(
    'editorBackground',
    ViewValueKind.integer.orNull,
    (report) => report.editorBackground,
  );
  return (fields) => _Report(
    kind: kind(fields),
    editorBackground: editorBackground(fields),
  );
});

/// A CoverageNode-shaped recursive tree.
final class _Node {
  const _Node({
    required this.name,
    required this.linesFound,
    required this.isFile,
    this.children = const [],
  });

  final String name;
  final int linesFound;
  final bool isFile;
  final List<_Node> children;
}

final ViewValueSchema<_Node> _nodeSchema = ViewValueSchema((field) {
  final name = field('name', ViewValueKind.string, (node) => node.name);
  final linesFound = field(
    'linesFound',
    ViewValueKind.integer,
    (node) => node.linesFound,
  );
  final isFile = field('isFile', ViewValueKind.boolean, (node) => node.isFile);
  final children = field(
    'children',
    ViewValueKind.listOf(ViewValueKind.nested(() => _nodeSchema)),
    (node) => node.children,
  );
  return (fields) => _Node(
    name: name(fields),
    linesFound: linesFound(fields),
    isFile: isFile(fields),
    children: children(fields),
  );
});

/// A CoverageSnapshot-shaped composite nesting the recursive tree.
final class _Snapshot {
  const _Snapshot({required this.lcovPath, required this.root});

  final String lcovPath;
  final _Node root;
}

final ViewValueSchema<_Snapshot> _snapshotSchema = ViewValueSchema((field) {
  final lcovPath = field(
    'lcovPath',
    ViewValueKind.string,
    (snapshot) => snapshot.lcovPath,
  );
  final root = field(
    'root',
    ViewValueKind.nested(() => _nodeSchema),
    (snapshot) => snapshot.root,
  );
  return (fields) => _Snapshot(lcovPath: lcovPath(fields), root: root(fields));
});

void main() {
  group('ViewValueSchema round trips', () {
    test('a flat value with an int-or-null field, both populated and null', () {
      final full = _reportSchema.decode(
        _reportSchema.encode(
          const _Report(kind: 'dark', editorBackground: 0xFF1E1E1E),
        ),
      );
      expect(full.kind, 'dark');
      expect(full.editorBackground, 0xFF1E1E1E);

      final bare = _reportSchema.decode(
        _reportSchema.encode(const _Report(kind: 'highContrast')),
      );
      expect(bare.kind, 'highContrast');
      expect(bare.editorBackground, isNull);
    });

    test('the encoded form is a plain protocol snapshot', () {
      expect(
        _reportSchema.encode(const _Report(kind: 'light')),
        {'kind': 'light', 'editorBackground': null},
      );
    });

    test('a recursive tree nested inside a composite value', () {
      const snapshot = _Snapshot(
        lcovPath: 'coverage/lcov.info',
        root: _Node(
          name: '',
          linesFound: 3,
          isFile: false,
          children: [
            _Node(
              name: 'lib',
              linesFound: 3,
              isFile: false,
              children: [
                _Node(name: 'a.dart', linesFound: 2, isFile: true),
                _Node(name: 'b.dart', linesFound: 1, isFile: true),
              ],
            ),
          ],
        ),
      );

      final decoded = _snapshotSchema.decode(_snapshotSchema.encode(snapshot));

      expect(decoded.lcovPath, 'coverage/lcov.info');
      expect(decoded.root.children.single.name, 'lib');
      final files = decoded.root.children.single.children;
      expect(files, hasLength(2));
      expect(files.first.name, 'a.dart');
      expect(files.first.isFile, isTrue);
      expect(files.first.children, isEmpty);
      expect(files.last.linesFound, 1);
    });
  });

  group('ViewValueSchema exact-schema guard', () {
    Matcher throwsFormatExceptionNaming(String fragment) => throwsA(
      isA<FormatException>().having(
        (error) => error.message,
        'message',
        contains(fragment),
      ),
    );

    test('a missing key is rejected by name', () {
      expect(
        () => _reportSchema.decode(<Object?, Object?>{'kind': 'dark'}),
        throwsFormatExceptionNaming('"editorBackground"'),
      );
    });

    test('an extra key is rejected by name', () {
      expect(
        () => _reportSchema.decode(<Object?, Object?>{
          'kind': 'dark',
          'editorBackground': null,
          'extra': true,
        }),
        throwsFormatExceptionNaming('"extra"'),
      );
    });

    test('a wrong-typed value is rejected by key name', () {
      expect(
        () => _reportSchema.decode(<Object?, Object?>{
          'kind': 42,
          'editorBackground': null,
        }),
        throwsFormatExceptionNaming('"kind"'),
      );
      expect(
        () => _reportSchema.decode(<Object?, Object?>{
          'kind': 'dark',
          'editorBackground': 'red',
        }),
        throwsFormatExceptionNaming('"editorBackground"'),
      );
    });

    test('null is rejected for a non-nullable field by key name', () {
      expect(
        () => _reportSchema.decode(<Object?, Object?>{
          'kind': null,
          'editorBackground': null,
        }),
        throwsFormatExceptionNaming('"kind"'),
      );
    });

    test('a non-map value is rejected', () {
      expect(
        () => _reportSchema.decode('not a map'),
        throwsFormatException,
      );
      expect(() => _reportSchema.decode(null), throwsFormatException);
    });

    test('a wrong-typed tree leaf names the failing path', () {
      final wire =
          _snapshotSchema.encode(
                const _Snapshot(
                  lcovPath: 'coverage/lcov.info',
                  root: _Node(
                    name: '',
                    linesFound: 1,
                    isFile: false,
                    children: [
                      _Node(name: 'a.dart', linesFound: 1, isFile: true),
                    ],
                  ),
                ),
              )!
              as Map<Object?, Object?>;
      final root = wire['root']! as Map<Object?, Object?>;
      final child =
          (root['children']! as List<Object?>).first! as Map<Object?, Object?>;
      child['linesFound'] = 'one';

      expect(
        () => _snapshotSchema.decode(wire),
        throwsFormatExceptionNaming('"linesFound"'),
      );
      expect(
        () => _snapshotSchema.decode(wire),
        throwsFormatExceptionNaming('"children"'),
      );
      expect(
        () => _snapshotSchema.decode(wire),
        throwsFormatExceptionNaming('index 0'),
      );
    });

    test('a duplicate field declaration fails at schema construction', () {
      expect(
        () => ViewValueSchema<_Report>((field) {
          final kind = field('kind', ViewValueKind.string, (r) => r.kind);
          field('kind', ViewValueKind.string, (r) => r.kind);
          return (fields) => _Report(kind: kind(fields));
        }).encode(const _Report(kind: 'dark')),
        throwsArgumentError,
      );
    });
  });

  group('ViewValueKind scalars', () {
    test('integer and boolean codecs are usable as operation payloads', () {
      expect(ViewValueKind.integer.encode(7), 7);
      expect(ViewValueKind.integer.decode(7), 7);
      expect(() => ViewValueKind.integer.decode('7'), throwsFormatException);
      expect(ViewValueKind.boolean.decode(true), isTrue);
      expect(() => ViewValueKind.boolean.decode(1), throwsFormatException);
      expect(ViewValueKind.string.decode('x'), 'x');
      expect(() => ViewValueKind.string.decode(1), throwsFormatException);
      expect(ViewValueKind.doubleNumber.decode(1.5), 1.5);
      expect(
        ViewValueKind.doubleNumber.decode(1),
        1.0,
        reason:
            'compiled JavaScript does not preserve the int/double '
            'distinction for whole numbers',
      );
      expect(
        () => ViewValueKind.doubleNumber.decode('1.5'),
        throwsFormatException,
      );
      expect(ViewValueKind.integer.orNull.decode(null), isNull);
      expect(ViewValueKind.integer.orNull.encode(null), isNull);
    });
  });

  group('schema-backed operations across the session seam', () {
    test('a schema composes into a ViewOperation and round-trips', () async {
      final operation = ViewOperation.noArgs(
        'schema.snapshot',
        encodeResult: _reportSchema.encode,
        decodeResult: _reportSchema.decode,
      );
      final transport = InMemoryViewTransportPair();
      final host = HostViewSession.connect(
        transport: transport.host,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
        operations: [
          operation.bind(
            (_) => const _Report(kind: 'dark', editorBackground: 7),
          ),
        ],
      );
      final view = await FlutterViewSession.connect(
        transport: transport.view,
        sessionId: 'session-1',
        bootstrapNonce: 'bootstrap-1',
      );

      final report = await operation.call(view, null);

      expect(report.kind, 'dark');
      expect(report.editorBackground, 7);
      await view.close();
      await host.closed;
    });

    test(
      'callThrough rides the structural operationCaller seam, so one '
      'shared declaration serves a session from another protocol copy',
      () async {
        final operation = ViewOperation<int, int>(
          name: 'schema.double',
          encodeArguments: ViewValueKind.integer.encode,
          decodeArguments: ViewValueKind.integer.decode,
          encodeResult: ViewValueKind.integer.encode,
          decodeResult: ViewValueKind.integer.decode,
        );
        final transport = InMemoryViewTransportPair();
        final host = HostViewSession.connect(
          transport: transport.host,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
          operations: [operation.bind((value) => value * 2)],
        );
        final view = await FlutterViewSession.connect(
          transport: transport.view,
          sessionId: 'session-1',
          bootstrapNonce: 'bootstrap-1',
        );

        // The seam is a plain function type: no nominal session type
        // crosses it, which is what lets a shared package's operation
        // declarations call through `package:flutter_vscode/view.dart`'s
        // session even though the two resolve distinct protocol copies.
        final caller = view.operationCaller;
        final result = await operation.callThrough(caller, 21);

        expect(result, 42);
        await view.close();
        await host.closed;
      },
    );
  });
}
