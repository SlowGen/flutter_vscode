/// The one generated VS Code API layer, self-contained.
///
/// Pure Dart: this package is `dart:js_interop` only, so a Host Dart module
/// compiled with `dart compile js` never pulls the Flutter SDK into its
/// dependency graph.
///
/// A single mechanically generated artifact carries the complete typed
/// Parity Layer substrate (ADR 0012, Total Mapping Rules) and the
/// Dart-ergonomics layer over it (developer-experience D-2) — a total,
/// judgment-free rule set, not a hand-reviewed facade. Helper boundaries
/// take ordinary `String`/`num`/`bool`, `JSPromise` returns become
/// `Future`s, `Event` members gain broadcast `Stream` accessors (`onDidX`
/// gains `onDidXStream`), and `lit$` factories flatten inherited interface
/// members. Wrap the raw activation module with `VscodeApi(rawVscode)` for
/// the parity surface, or enter the ergonomic layer with
/// `VscodeApi(rawVscode).dart`; every `XDart` type wraps and implements
/// its parity type `X`, so dart-layer values flow anywhere the parity
/// surface is expected.
library;

export 'src/generated/vscode_dart_layer.g.dart';
