# Shipped Example Extensions

Real, installable VS Code extensions built with `flutter_vscode`. They are product surfaces: each one is expected to work, ship, and stay honest about what the framework can do.

## Guardrails

Every extension here consumes the framework the way an Extension Author would:

- scaffolded and built only with the `flutter_vscode` CLI (`create`/`build`/`package`);
- no imports from the repository's internals (`package:flutter_vscode/src/`), `tool/`, or test fixtures — only CLI-generated files and the published package surface (`package:dart_vscode/dart_vscode.dart` in hosts, `package:flutter_vscode/view.dart` in views);
- when an extension needs something the framework lacks, the gap is recorded (futures or a plan) and the framework change lands with its own tests first; the extension then consumes it like any author.

These directories are excluded from the pub package archive.

## coverage_treemap

Line coverage from `coverage/lcov.info` painted into the editor, a status-bar coverage percentage, and an interactive squarified coverage treemap rendered by a Flutter View.

Build and run it:

```sh
cd extensions/coverage_treemap
flutter_vscode build
```

Open `extensions/coverage_treemap` in VS Code and press F5 — or launch the Extension Development Host directly from a terminal against any project that has coverage data:

```sh
code --new-window \
  --extensionDevelopmentPath="$(pwd)/extensions/coverage_treemap" \
  /path/to/a/project/with/coverage
```

In the development host, open a workspace containing `coverage/lcov.info` (run `flutter test --coverage` in any Flutter project first), then:

- covered and uncovered lines are highlighted in the active editor;
- the status bar shows the overall percentage — click it (or run **Coverage: Run Tests with Coverage**) to run `flutter test --coverage` in a VS Code terminal and refresh everything from the new numbers, no external CLI session needed;
- **Coverage: Show Treemap** opens the Flutter treemap panel, which renders its summary charts with the pub.dev package `fl_chart` — Flutter-ecosystem code reuse running inside VS Code;
- **Coverage: Refresh** and **Coverage: Toggle Line Highlights** do what they say;
- editing or regenerating `lcov.info` refreshes automatically.

Note: the Dart extension's Testing-UI "Run with Coverage" feeds VS Code's native Test Coverage API and does not write `coverage/lcov.info`; use the status-bar action (or any `flutter test --coverage` run) to update this extension's data.

The real-host gate for this extension is `scripts/test_coverage_extension.sh`: it packages the VSIX, installs it into the pinned Extension Host — in Docker, and natively on macOS with `FLUTTER_VSCODE_GATE_NATIVE=1` — opens a workspace with a known tracefile, and asserts the parsed snapshot, that the Flutter View boots and serves the snapshot operation over the view protocol in a real webview, and that the view confirms a painted first frame (the signal an occluded or throttled webview never produces).

`flutter_vscode package` writes the installable VSIX under `build/`.

## pubspec_lens

Dependency intelligence for `pubspec.yaml`, delivered as a Host-Only Extension: no Flutter View, no webview — the whole UX rides VS Code's native UI surface, driven from plain Dart through the generated layer. Hover a dependency for the latest version and description; any pin whose lower bound trails the registry gets a CodeLens that rewrites the constraint through a `WorkspaceEdit`, and the pins that actually *block* the latest release also get an Information-severity diagnostic; a dependencies tree view lists direct dependencies with verdicts; a refresh command re-queries. The semantics come from the Dart team's own packages — `pub_semver` for constraint math and `yaml` for span-preserving parsing — and the registry is fetched with the generated runtime's `hostFetch`, with the base URL configurable so the real-host gate serves a deterministic fake pub.dev.

The dividing line the two examples draw together: use the native surface (trees, pickers, hovers, lenses, squiggles, status bar) when your UX is lists, text, and annotations; reach for a Flutter View only when you need custom drawing, like the treemap.

Build and run it:

```sh
cd extensions/pubspec_lens
flutter_vscode build
```

Open `extensions/pubspec_lens` in VS Code and press F5 — or launch the Extension Development Host from a terminal against any Dart project:

```sh
code --new-window \
  --extensionDevelopmentPath="$(pwd)/extensions/pubspec_lens" \
  /path/to/any/dart/project
```

In the development host, open `pubspec.yaml` (analysis runs on open and queries the registry — live pub.dev by default — so give the first pass a second or two). Any pin below the latest release is enough to see it work; age one to a previous major (say `http: ^0.13.0`) to see both tiers at once:

- a CodeLens above every trailing pin offers **Update to ^X.Y.Z**; clicking it rewrites the constraint through a `WorkspaceEdit`, so the edit lands in your buffer (the file goes dirty), never silently on disk;
- the pins that actually *block* the latest release — where the constraint excludes it, so `pub get` can never resolve to it — also get an Information-severity squiggle, and the Problems panel reads `http 1.6.0 is available (pinned ^0.13.0)`. Severity is Information by design: a newer release is advice, not a defect;
- a pin that merely trails the latest inside its caret (`http: ^1.5.0` when 1.6.0 is out) gets the lens but no squiggle — nothing is broken, so the Problems panel stays about real blockers;
- a pin already at the latest version is silent on every surface;
- hover a dependency name for the latest version, the verdict, and the package's pub.dev description;
- **Pubspec Lens: Refresh** clears the registry cache and re-analyzes — useful after hand-editing a constraint;
- offline, verdicts degrade to *unknown* with no diagnostic churn, and recover on the next refresh.

Constraints that sit *ahead* of the registry (a lagging mirror, a prerelease pin) are never "fixed" by a rewrite that walks them backwards: the comparison is against the constraint's lower bound, so there is nothing to suggest.

The real-host gate is `scripts/test_pubspec_lens.sh`: it packages the VSIX, installs it into the pinned Extension Host — in Docker, and natively on macOS with `FLUTTER_VSCODE_GATE_NATIVE=1` — serves a deterministic fake pub.dev from inside the host, and asserts the hover, the single diagnostic, a lens on each trailing pin (and none on the current one), both CodeLens edits, and the tree snapshot. The extension contributes its dependencies view and its registryUrl setting through the typed manifest, so the tree renders in a plain F5 session with no test driver involved.
