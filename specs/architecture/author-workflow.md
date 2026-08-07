# Author Workflow

A Flutter/Dart developer ships an extension without npm, TypeScript, or
manual file copying:

```sh
dart pub global activate flutter_vscode   # path activation during development
flutter_vscode create my_extension        # host/, views/, shared/ layout
flutter_vscode doctor                     # toolchain + project checks
flutter_vscode build                      # or: build --watch
flutter_vscode test                       # shared/host/view suites
flutter_vscode package                    # installable VSIX
```

- `create` writes an analyzable project immediately (the Generated API
  Layer exists before the first build); a host-only extension simply has no
  `views/`. Extension metadata and contributions are Dart-owned in
  `extension.dart` — a single const Dart literal map parsed as data,
  never executed (`packages/flutter_vscode/lib/src/cli/project_descriptor.dart`).
  `extension.json` is the alternate form; `build` errors when both
  exist.
- `build` generates every Framework-Managed Artifact — `package.json`,
  bootstrap, launch configuration, host bundle, source maps, the
  runtime and host-exports modules, the one Generated API Layer
  (`vscode_dart_layer.g.dart`: the complete typed Parity Layer
  substrate plus the Dart-ergonomics surface, every project), and,
  for view-bearing projects, the Flutter View host
  module (`flutter_view_host.g.dart`) — enforces the host import
  boundary (deliberately skipping package `test/` directories: author
  tests may depend on `package:test` and never execute in the
  Extension Host), and reports malformed Dart with filename/line/column
  and remediation (no internal stacks, no exit 255). The build targets
  the one VS Code baseline this framework release pins (ADR 0014); a
  project never selects one. Generated activation registers providers
  synchronously so lazy activation cannot race a first query. Flutter
  Views boot through `runFlutterView` from
  `package:flutter_vscode/view.dart`, which prepares the webview
  runtime before `runApp` ([View Protocol](view-protocol.md)).
- `build --watch` rebuilds on host, shared, view, and descriptor
  changes with debounced scheduling that ignores generated output, so
  a rebuild cannot retrigger itself; Development-mode hosts reload the
  window when the emitted bundle changes
  ([Host Execution](host-execution.md)).
- `doctor` checks the Dart and Flutter toolchains, the project layout,
  the descriptor, and pinned-input availability for the declared API
  target, printing `[ok]`/`[!!]` lines and exiting nonzero on any
  failure; `test` discovers and runs `shared/test`, `host/test`, and
  per-view suites, aggregating failures.
- `package` validates `extension.vsixmanifest` and
  `[Content_Types].xml` as real XML (declarations required, XML
  1.0-forbidden characters rejected) before emitting a VSIX, and
  refuses stale artifacts via build receipts that fingerprint the
  framework, generator, and pinned API inputs.

Proven end to end by `test/cli_*` suites and
`./scripts/test_packaged_extension.sh`, which stages the framework from
`dart pub publish`'s own archive listing, installs both fixture VSIXes
in a pinned VS Code, and asserts the inactive-start → `onLanguage`
activation → single-hover-first flow before any extension command.
Publication readiness is `dart pub publish --dry-run --ignore-warnings`;
publishing itself remains out of scope.

