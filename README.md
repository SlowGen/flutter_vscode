# flutter_vscode

Build VS Code extensions in Dart and Flutter. This repository is a pub workspace: one `dart pub get` at the root resolves every package, and `flutter analyze` covers the whole tree.

## Layout

| path | what it is |
|---|---|
| [`packages/dart_vscode`](packages/dart_vscode) | published, pure Dart: the generated VS Code API, the view protocol, and the Host Dart runtime |
| [`packages/flutter_vscode`](packages/flutter_vscode) | published: the CLI and the Flutter View runtime, built on `dart_vscode` |
| [`extensions/`](extensions/README.md) | the shipped example extensions — Coverage Treemap (Flutter View) and Pubspec Lens (Host-Only, native VS Code UI) — built only through the public CLI |
| [`docs/`](docs/index.md) | guides, reference, architecture, and ADRs |
| [`specs/`](specs/vision/vision.md) | vision, architecture notes, and plan history |
| [`skills/`](skills/README.md) | agent skills for extension authors — copied into an extension project as `agent-skills/` |
| `scripts/` | the per-gate real-host scripts the CI workflow runs as steps, plus `ci_gates.sh` to run the whole workflow locally |

## Build an extension

The full walkthrough is the [package README](packages/flutter_vscode/README.md); the [quickstart](docs/guides/quickstart.md) is the guided version. The short form:

```sh
dart pub global activate --source path \
  /path/to/flutter_vscode/packages/flutter_vscode

flutter_vscode create my_extension
cd my_extension
flutter_vscode build
```

Open the project in VS Code and press F5 to run it in an Extension Development Host. From there, by topic:

- [a Dart-only extension](packages/flutter_vscode/README.md#your-first-extension-dart-only) — the typed manifest, commands, providers, and the `doctor`/`build`/`test`/`package` loop
- [the VS Code API from Dart](packages/flutter_vscode/README.md#reaching-the-rest-of-the-vs-code-api) — every namespace, class, enum, and callback of the pinned baseline, typed; reference in the [Generated Host API](docs/reference/generated-host-api.md)
- [adding a Flutter View](packages/flutter_vscode/README.md#adding-a-flutter-view) — a Flutter web app in a webview panel, and [showing it from Host Dart](packages/flutter_vscode/README.md#showing-the-view-from-host-dart)
- [pub.dev packages](packages/flutter_vscode/README.md#using-pubdev-packages) — web-compatible Dart packages in `host/` and `shared/`, Flutter UI packages in views
- [debugging both sides](packages/flutter_vscode/README.md#debugging-the-flutter-view) — F5, terminal-launched development hosts, webview developer tools

## Working in this repository

You need a Flutter SDK carrying Dart `^3.12.0` (the floor every workspace package pins).

```sh
dart pub get                # resolves every workspace package
flutter analyze             # covers the whole tree
cd packages/dart_vscode && dart test              # the API package suite
cd packages/flutter_vscode && flutter test --exclude-tags gate  # fast suite
./scripts/ci_gates.sh       # the whole CI workflow locally: containers
                            # plus, on macOS, the five native desktop gates
```

CI ([`.github/workflows/test.yml`](.github/workflows/test.yml)) runs four jobs: analyze/format/publishability checks, every package's suite, the real-host gates against a pinned VS Code in containers, and a macOS desktop job that reruns five of those gates natively — four take `FLUTTER_VSCODE_GATE_NATIVE=1`, and the host gate runs through its dedicated native script. `ci_gates.sh` runs exactly those jobs locally — the ubuntu jobs in runner-like Docker containers (so it needs Docker), the macOS job natively when the host is a Mac.

(Plain `flutter test` in `packages/flutter_vscode` also runs the gate-tagged workflow test — the full Docker CI run — which is rarely what you want mid-loop.)

Each example package owns its own tests; run them in their directory.
