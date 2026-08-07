# Agent-Assisted Development

How an Extension Author points a coding agent at an Extension Project: the
agent translates product intent into Dart-owned extension metadata, Host Dart
behavior, and optional Flutter UI without introducing an author-side Node or
TypeScript layer. The rules below keep the agent inside the author-owned
surface and the full CLI loop of the [quickstart](quickstart.md); the
[Generated Host API](../reference/generated-host-api.md) is its API ground
truth.

## Setup

The Dart-host workflow is currently unreleased, so activate it from a local
checkout:

```sh
dart pub global activate --source path /path/to/flutter_vscode
flutter_vscode create my_extension
cd my_extension
```

Point the agent at the project `AGENTS.md` and `agent-skills/`. If those files
are not present yet, copy the [consumer template](../templates/consumer-agents.md)
and the repository `skills/` tree.

## Working model

```text
intent -> edit author-owned Dart -> doctor -> build [--watch] -> test -> package
```

The generated layer is total: `vscode_dart_layer.g.dart` maps every public
declaration of the pinned baseline, so the agent never needs to check whether
a stable symbol is supported — a symbol absent from the parity report's
host-verified accounting is unverified, not unsupported. Start with the
[Generated Host API](../reference/generated-host-api.md). The agent must not
handwrite a shadow API or edit generated interop; if `flutter_vscode build`
fails on a construct the generator cannot map, that is a framework defect to
report — the [parity report](../reference/parity.md) states the rule — never
something to work around.

For a supported feature, the agent edits:

- `extension.dart` for metadata and contributions;
- `host/lib/**` for activation, commands, providers, events, and native VS Code
  object lifecycles;
- `shared/lib/**` for runtime-neutral values; and
- `views/**` for optional Flutter UI and typed, allowlisted host calls.

It then runs:

```sh
flutter_vscode doctor
flutter_vscode build
flutter_vscode test
```

`build --watch` keeps the rebuild running during longer editing sessions, and
`flutter_vscode package` validates the VSIX at the end. The agent must not
edit `package.json`, generated host bindings, the CommonJS bootstrap,
JavaScript bundles, source maps, or VSIX contents.

## Example prompts

> Add a contributed command named “Show Greeting,” register it in Host Dart,
> and return the selected editor language.

> Add an optional Flutter view. Keep provider logic in Host Dart, expose one
> allowlisted value operation to the view, and verify protocol cleanup when the
> panel closes.

> Register a tree data provider through the generated layer. If the build
> fails to map a construct it needs, report the generation failure as a
> framework defect instead of inventing bindings.

## Review checklist

1. `extension.dart` declares only manifest fields the typed
   `ExtensionManifest` supports; the VS Code baseline comes from the
   framework release, never from the descriptor (ADR 0014).
2. Host behavior works before any view opens and after a view closes.
3. Cross-runtime messages use typed protocol operations and value snapshots.
4. Host/shared dependency checks pass.
5. A second `flutter_vscode build` reproduces managed artifacts.
6. `flutter_vscode doctor` and `flutter_vscode test` pass.
7. `flutter_vscode package` validates the VSIX.
8. No author-owned `.js`, `.ts`, or `package.json` was added.
