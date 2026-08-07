# VS Code Integration Rules

## Host Dart

- Compile pure Dart to JavaScript and run it in-process in VS Code's Node
  Extension Host.
- Access `vscode` only through mechanically generated `dart:js_interop`
  bindings from pinned official inputs and reviewed Semantic Overrides.
- Preserve native host objects; do not serialize `Uri`, documents, positions,
  providers, events, or disposables into DTOs.
- Activation, providers, and commands must not depend on a Flutter View.

## Flutter Views

- Keep each view in a separate Flutter web runtime.
- Use `package:web` and `dart:js_interop`; never add `dart:js_util`.
- Keep `acquireVsCodeApi` private to the web adapter.
- Use webview-safe resource URIs and a restrictive CSP with no broad default
  source.
- Send only schema-validated value snapshots over the versioned protocol.
- Bind every frame to a session and active nonce, and allowlist operations.
- Close/reload must fail pending work, cancel listeners, rotate session state,
  and ignore late frames.

## Related

- [Architecture Index](../architecture/index.md)
- [Code Generation Rules](code-generation.md)
