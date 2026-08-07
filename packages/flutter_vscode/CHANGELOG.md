
## Unreleased

- Stop reading binding inputs at build time: generation is a
  `dart_vscode` maintainer operation (ADR 0016). `build` emits only
  Project-Derived Artifacts — `package.json`, `host/bootstrap.cjs`, and
  the two identity-wiring host modules — validating the descriptor
  through `package:dart_vscode/contributions.dart`, and the published
  archive carries no generator, IR, or pinned inputs. **Breaking:**
  projects no longer receive `coverage.json` (the accounting lives in
  the maintainer coverage ledger and the published parity report), and
  the build receipt drops the generator and binding-input digests
  (`schemaVersion` 3), so existing projects rebuild once before
  packaging.
- Contribute views, view containers, and configuration from the typed
  manifest (the last author-visible gap the upstream review named).
  `ExtensionManifest` gains `views`, `viewsContainers`, and
  `configuration`, projected into `package.json` through the same
  pinned-schema pipeline as commands: two newly pinned VS Code sources
  (`viewsExtensionPoint.ts`, `configurationExtensionPoint.ts`) are
  extracted fail-closed by the importer -- schema literals normalized,
  runtime validator branches asserted verbatim -- and the generator
  byte-compares the projection against an independently reviewed copy
  before validating author data with the platform's own semantics. A
  whitespace-only container id fails the build because the pinned host
  errors on it; a whitespace-only container title does not, because the
  pinned host only warns. Pubspec Lens now declares its dependencies
  view and its `pubspecLens.registryUrl` setting itself, and its gate
  driver contributes nothing on its behalf -- the tree renders in a
  plain F5 session.
- Prove the pinned Extension Host on macOS: the same driver, contract
  verification, and pinned VS Code, natively with no container and no
  xvfb (`scripts/test_host_extension_native.sh`), plus a macOS CI job.
  Wire the breakpoint gate into CI and retire the archived
  round-5 exit checker. Assert the Content Security Policy the live
  webview was actually served -- which already differs from the emitted
  template: VS Code injects its CDN origins -- rather than only
  byte-comparing the template.
- Split the pure-Dart runtime into its own published package,
  `dart_vscode` (ADR 0015), and stop copying framework source into
  Extension Projects. The generated VS Code API, the Host/Flutter View
  protocol, `ExtensionCommands`, the Flutter View host module, and the
  Host Dart runtime are libraries there; a project now receives only the
  two generated files derived from itself -- its extension identifier,
  its collision-resistant global key, and the bindings tied to them.
  Roughly 2,850 lines of framework code stop being emitted, and Host Dart
  no longer pulls the Flutter SDK into its dependency graph.
  **Breaking:** host packages depend on `dart_vscode` and import
  `package:dart_vscode/...`; `flutter_vscode` requires `dart_vscode` at
  the same version.
- Adopt the conventional pub monorepo layout: the repository root is a
  non-published workspace root and the published packages live under
  `packages/`. Publishing the workspace root had broken
  `dart pub global activate`, the documented way to install the CLI.
- Ship one VS Code baseline per release (ADR 0014). `ExtensionManifest`
  loses `apiTarget`: the package version *is* the baseline, and an author
  who needs a different VS Code API depends on the `flutter_vscode`
  release that ships it rather than selecting one inside the package.
  Because every project now builds against the same baseline, the API
  layer is no longer copied into each project — it ships once as
  `package:flutter_vscode/vscode_dart.dart` and generated host modules
  import it from there, leaving each project with only the generated
  files derived from its own commands and views. The second pinned
  baseline and its inputs are removed; the tracked tree drops ~5.8 MB and
  every Extension Project drops 718 KB. **Breaking:** projects declaring
  `apiTarget` must remove it, and `engines.vscode` now moves with the
  framework release.
- Ship two example extensions under `extensions/`, each proven by its own
  real-host gate rather than a unit test. **Coverage Treemap** (Flutter
  View) paints `lcov.info` coverage into the editor, keeps a live
  status-bar percentage that runs `flutter test --coverage` on click, and
  renders a squarified treemap with `fl_chart` summary charts in a real
  webview, live-pushing fresh snapshots as coverage changes. **Pubspec
  Lens** (Host-Only — no webview at all) reads `pubspec.yaml` with
  `pub_semver` and `yaml`, and drives hovers, a constraint-bumping
  CodeLens, diagnostics, and a dependencies tree entirely on VS Code's
  native UI surface. Together they draw the framework's dividing line:
  native surfaces for lists, text, and annotations; a Flutter View only
  when you need custom drawing. Both are excluded from the pub archive.
- Judge a dependency pin by its lower bound, not by admission: Pubspec
  Lens now distinguishes a constraint that merely *trails* the latest
  release (CodeLens, no diagnostic — nothing is broken) from one that
  *excludes* it (CodeLens and an Information diagnostic — nothing will
  resolve to the latest until the constraint moves). A pin already at or
  above the latest version is silent, which also makes a downgrade
  suggestion structurally impossible for constraints sitting ahead of the
  registry.
- Type the extension descriptor: `extension.dart` declares
  `const extension = ExtensionManifest(...)` using
  `package:flutter_vscode/manifest.dart` (with `ExtensionCommand` for
  command contributions), the scaffold emits the typed form plus a
  root `pubspec.yaml` so the declaration analyzes with completion and
  type-checking in the author's editor, and the CLI parses the
  constant invocation as data — project code is never executed. The
  untyped map-literal descriptor is rejected with an actionable
  error; `extension.json` is unchanged.
- Authoring DX: every project receives a generated
  `host_commands.g.dart` whose `ExtensionCommands.register` takes an
  ordinary-Dart command handler (dartified arguments in,
  protocol-safe result out) and owns the interop seam; and
  `view_protocol.dart` gains `ViewValueSchema` declare-once codecs —
  fields declared a single time derive encode, decode, and an
  exact-schema guard naming failing keys, with recursion support.
  View-bearing builds emit the protocol copy into
  `shared/lib/generated/` (re-exported by the host module) so the
  shared package assembles each `ViewOperation` once for host and
  view, the view calling through the structural
  `operationCaller`/`callThrough` seam.

- Delete the legacy v0 pipeline: the `generate_vscode_extension`
  scaffolder, the annotation/source_gen builder surface and webview
  bridge runtime in `lib/`, `build.yaml`, `example/`,
  `tool/legacy-agent-skills/`, and the v0-era PRD are removed along
  with the `build`, `source_gen`, `build_runner`, and `build_test`
  dependencies; `flutter_vscode create` is the only scaffolder.

- One generated API artifact (ADR 0013): `vscode_dart.dart` carries
  the Parity Layer substrate and Dart-ergonomics surface; the
  walking-slice facade and binding-observation mechanism retire,
  substrate totality intact; judgment lives in framework
  modules (`FlutterViewHost`, `ViewShell`).

- Support plural pinned VS Code baselines: 1.130.0 ships beside the
  1.129.1 seed, the project descriptor's `apiTarget` selects among
  them, an unknown target fails with an error naming every pinned
  target, and `docs/guides/new-baseline.md` documents onboarding a
  new release.
- Add the Dart-owned `flutter_vscode create`, `build`, and `package` workflow.
- Generate a reviewed VS Code 1.129.1 host-binding slice from pinned inputs.
- Pin and project transitive contribution validators with exact JavaScript trim
  semantics.
- Add an optional typed Flutter View protocol with strict session cleanup.
- Verify source and installed VSIX extensions in a pinned real Extension Host.
- Map synchronous and asynchronous Host Dart failures back to exact Dart source
  frames and roll back partial activation registrations.
- Enforce fingerprinted VS Code baseline updates and executable binding evidence.
- Harden scaffolding and packaging with hover-first activation, pre-build
  analysis, XML validation, and framework/generator/input-bound build receipts.
- Exercise adversarial Flutter View frames, reload with pending work, measured
  shutdown counts, and an independent render observation in a real webview.
- Store canonical type-literal shapes in the pinned IR and recompute every
  registered shape hash on the Dart side, closing lossless-IR and
  opaque-hash gaps.
- Regenerate the durable Host Contract evidence artifact mechanically
  (`generate.dart --contract`); hand-edited evidence is no longer a
  supported workflow, and pin-manifest inputs must resolve inside their
  manifest directory.
- Publish a generated VS Code API parity burn-down
  (`docs/reference/parity.md`) treating missing Dart paths for public
  capabilities as defects.
- Label all legacy v0 webview/TypeScript surfaces (PRD, example, API
  mapping) as historical and remove the dead `bin/init.dart` scaffolder.
- Run analysis, the full gate, the publish dry run, and a cleanliness
  check in CI on pull requests.
- Ship the complete typed Parity Layer
  (`package:flutter_vscode/vscode_parity.dart`): a mechanically
  generated typed mapping of the entire pinned VS Code API (2,982
  declarations) produced only by Total Mapping Rules, rooted in the
  activation module object, with object-literal factories, module-rooted
  constructors, typed tuples, and a totality ledger; `build` emits it
  into every Extension Project and the real-host gate exercises it.
- Ship the mechanical Dart-ergonomics layer over the Parity Layer
  (`package:flutter_vscode/vscode_dart.dart`): a second generated,
  total, judgment-free rule set — ordinary `String`/`num`/`bool` at
  helper boundaries, `Future` from `JSPromise`, broadcast
  `onDidXStream` accessors beside `Event` members, `lit$` factories
  that include inherited interface members, and alias-named literal
  wrappers — entered with `VscodeApi(rawVscode).dart`, accounted for by
  a full totality ledger, and emitted by `build` into every Extension
  Project beside the parity layer.

## 0.1.0

- Add annotation-driven Dart and TypeScript generation for `@VSCodeController` and `@VSCodeCommand`.
- Add runtime bridge APIs for request/response communication between Flutter webview and VS Code host.
- Add scaffold CLI (`generate_vscode_extension`) with idempotent create-or-skip behavior for user-owned files.
- Add PRD traceability and message contract reference docs.
- Expand tests for runtime request lifecycle and scaffold idempotence.
