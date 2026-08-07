# Troubleshooting

Symptom-to-remedy entries for an Extension Author whose `flutter_vscode`
build, package, or Flutter View misbehaves. Each remedy names the real
command or diagnostic at HEAD so you can act on the failure instead of
guessing. Workflow context lives in the [quickstart](quickstart.md);
API-shape questions belong to the
[Generated Host API](../reference/generated-host-api.md).

## First, run `flutter_vscode doctor`

```sh
flutter_vscode doctor
```

`doctor` writes one `[ok]` or `[!!]` line per check — the Dart and Flutter
SDK probes, and inside an Extension Project the layout, the descriptor, and
whether this framework version carries its pinned VS Code baseline — then
exits nonzero if any check failed. Clear every `[!!]` line before chasing a
deeper cause.

## Build rejects `extension.dart`

Keep the descriptor as the restricted constant map emitted by `create`. Use
literal values only, retain `schemaVersion`, and remove unknown
fields. The CLI parses this file without executing project code so identical
source cannot produce environment-dependent manifests.

## A VS Code API symbol looks unsupported

The generated layer is total by construction:
`package:dart_vscode/dart_vscode.dart` maps every public declaration
of the pinned baseline, so no stable symbol is missing. The
[parity report](../reference/parity.md) records behavioral verification,
not availability — an entry still `pending` there is unverified, not
unsupported. Use the symbol through the generated
layer as usual. If generation itself fails on a construct it cannot map
(a `ParityGenerationException` naming the declaration), that is a framework
defect — report it rather than adding raw `dynamic` interop or a handwritten
binding. The [parity report](../reference/parity.md) states the rule and
tracks the verification burn-down.

## Host dependency boundary fails

The `HOST_IMPORT_BOUNDARY_VIOLATION` diagnostic names the offending import.
Move Flutter, `package:web`, DOM, I/O, isolate, or other unsupported platform
code into an optional view. Keep `shared/` runtime-neutral.

## Package reports stale artifacts

`STALE_BUILD_ARTIFACTS` means the Framework-Managed Artifacts no longer match
the sources. Run:

```sh
flutter_vscode build
flutter_vscode package
```

Do not repair `package.json`, the bootstrap, generated bindings, `out/`, or the
VSIX by hand.

## Flutter view is blank

Confirm `build` produced `out/views/<name>/`, then inspect the Extension Host
and webview developer consoles for CSP or protocol diagnostics. The view must
use private `acquireVsCodeApi` access, webview-safe asset URLs, and the
version-2 session/nonce handshake — the view sends a `ready` frame with its
bootstrap session and nonce, and the host answers `readyAck` with the active
nonce. `ViewShell.connect` performs that handshake for you.
