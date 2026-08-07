# Host Execution

Host behavior is pure Dart compiled with `dart compile js` and loaded
in-process by VS Code's Node Extension Host. A framework-owned CommonJS
bootstrap imports `vscode`, installs the runtime shim, loads the Dart
bundle, and forwards `activate`/`deactivate`; the public lifecycle is
`activate(context, vscode)` with no test or environment branches in
shipped code — with one deliberate exception, the Development-mode
bundle watcher (see the reload carve-out below). Both halves are
enforced by `packages/flutter_vscode/tool/extension_host_test/bootstrap_lifecycle.test.cjs`.

Rules and their enforcement:

- **Native identity.** VS Code values (`Uri`, `Position`, `Range`,
  `MarkdownString`, `Hover`, documents) stay native JS objects with
  prototypes and identity intact; Dart-friendly builders lower to those
  objects and never JSON-copy them. Proven by the real-host identity and
  hover assertions in `packages/flutter_vscode/test/fixtures/host_extension/test/run.cjs`.
- **Namespaced globals.** Everything the bundle exports lives under
  `__flutterVscode.*` keyed by a hash of the extension identity, so two
  generated extensions cannot collide in one host. The namespace
  publishing is emitted from the bootstrap template in
  `packages/flutter_vscode/lib/src/cli/project_artifacts.dart` (extension-key derivation in
  `generator.dart`) and asserted by the generator suite's
  one-identity-hash test.
- **Activation rollback.** A rejected activation disposes every
  registration made during the attempt, reverse order, exactly once,
  leaving pre-existing subscriptions untouched
  (`bootstrap_lifecycle.test.cjs`).
- **Development reload carve-out.** The generated bootstrap's only
  mode branch: when `context.extensionMode` is
  `vscode.ExtensionMode.Development`, it watches the emitted
  `out/extension.dart.js` and reloads the window (debounced
  `workbench.action.reloadWindow`) when the bundle changes; the
  watcher is disposed through `context.subscriptions`. Emitted from
  the bootstrap template in `packages/flutter_vscode/lib/src/cli/project_artifacts.dart`;
  the lifecycle test enforces
  both sides — the bootstrap source must contain no test-injection
  hooks, and a Development host must request the reload after a
  bundle rewrite (`bootstrap_lifecycle.test.cjs`).
- **Network path.** `hostFetch` in the generated runtime is the
  supported way for Host Dart to reach the network: it binds the
  Extension Host's global WHATWG `fetch` (Node) with method, headers,
  and body support and returns a protocol-safe status+body snapshot
  (`HostFetchResponse`). Proven by a compiled-probe unit test against
  a local Node server (`packages/dart_vscode/test/binding_generator_cli_test.dart`) and by
  the packaged gate's live `hostFetchProbe` command.
- **Mapped failures.** Synchronous throws, rejected promises, and
  activation failures surface `host/lib/extension.dart:<line>:<column>`
  frames, never only `.dart.js` frames (real-host gate assertions).
- **Import boundary.** Host and shared Dart cannot import Flutter,
  browser-only libraries, or unsupported platform APIs; enforced by
  `packages/flutter_vscode/lib/src/cli/check_host_imports.dart` in the CLI build path and
  `test/host_import_guard_test.dart`. The build's sweep deliberately
  skips package `test/` directories — author tests may depend on
  `package:test` and never execute inside the Extension Host — proven
  red-green by "build ignores package test directories in the boundary
  check" in `test/cli_build_test.dart`.
- **Toolchain carve-out.** Extension authors never manage Node or npm.
  Maintainer tooling and CI may use pinned Node packages
  (`packages/dart_vscode/tool/binding_importer`, `packages/flutter_vscode/tool/extension_host_test`), which are never
  part of the author toolchain.
