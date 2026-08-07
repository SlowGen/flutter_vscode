---
name: flutter-vscode-extension-host
description: >-
  Implement activation, commands, providers, events, or lifecycle behavior in
  Host Dart for a flutter_vscode Extension Project.
---

# Implement Host Dart Behavior

Put Extension Host logic in `host/lib/**`. It runs in VS Code even when no
Flutter view exists.

Use the one generated API layer,
`package:dart_vscode/dart_vscode.dart`: mechanically generated
`dart:js_interop` bindings covering every public declaration of the pinned
VS Code API while preserving native VS Code objects. Wrap the activation
arguments with `ExtensionContext(rawContext)` and `VscodeApi(rawVscode)`.
Construct classes through module-rooted `new$` factories, interfaces and
options objects through `lit$` literal factories, or call
`VscodeApi(rawVscode).dart` for the Dart-first surface (`Future` returns,
`Stream` event accessors, plain `String`/`num`/`bool` boundaries). Do not
create a handwritten shadow binding, generic dispatcher, or inferred
`dynamic` fallback.

Pass command and provider callbacks through `toHostCallback` from
`host/lib/generated/vscode_runtime.g.dart` so failures keep Dart source
frames; return Dart futures to the host through `toHostPromise`; reach the
network from Host Dart only through `hostFetch`. Keep `main()` as scaffolded:
`registerHostExports(createJSInteropWrapper(...))` from
`host_exports.g.dart`.

Register VS Code-owned disposables in `ExtensionContext.subscriptions`
synchronously during `activate`. Give Dart-owned resources idempotent
cleanup and handle partial activation.

Keep Flutter, DOM, `package:web`, `dart:io`, isolates, and unsupported
platform libraries out of Host Dart. Put rich UI in `views/`; expose only
explicit, allowlisted value operations over the versioned view protocol.

After editing:

```sh
flutter_vscode build
```

Verify commands/providers before any view opens and again after every view
has closed.
