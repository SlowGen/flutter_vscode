# Authoring DX Plan

Status: Implemented and verified — valid only while the fast suites
and the three real-host gates are green at HEAD
Date: 2026-07-26

Closes the three authored-surface gaps the coverage-treemap file
review identified: the untyped descriptor map, the host-side
command-registration ceremony, and the twice-written view-contract
codecs (plus the host/view duplication of assembled operations).
Everything an Extension Author owns should read like ordinary Dart.

Rules (inherited): exit bar frozen; reds are commits; no legacy or
compatibility surface — the branch is the product; discoveries to
[`futures.md`](futures.md).

## Exit bar

- [x] AD-1 Typed descriptor: `package:flutter_vscode/manifest.dart`
  ships const-constructible `ExtensionManifest`/`ExtensionCommand`
  types; `extension.dart` declares `const extension =
  ExtensionManifest(...)` with full analyzer completion and
  type-checking; the CLI parser consumes the typed form as data (AST
  over const constructor invocations — project code is still never
  executed) and the map form dies with the branch's no-compat rule
  (`extension.json` stays, it is already data). The scaffold emits
  the typed form; the coverage extension migrates. Check: a red
  parser suite over the typed form; cli_create/build/multi-baseline
  suites green; descriptor type errors surface in `dart analyze` of
  the project, proven by a test.
  Closed: `test/project_descriptor_test.dart` covers the happy parse
  to the exact downstream map (class defaults for `schemaVersion` and
  `commands` mirrored by the parser), actionable rejections
  (retired map literal, references/interpolation/calls/control flow,
  unknown/duplicate/positional/missing arguments, foreign imports),
  and the analyzer proof (`dart analyze` fails a scaffolded project
  whose descriptor mistypes `version`). Analyzability decision: the
  scaffold adds a minimal root `pubspec.yaml` (path dependency on the
  resolved flutter_vscode package root) whose only job is letting the
  author's analyzer resolve `package:flutter_vscode/manifest.dart`
  for completion and type-checking — the build never reads it and
  layout validation needed no changes. `apiTarget` is a required
  constructor argument, moving ADR 0011's no-silent-raise caveat from
  convention into the type; `publisher` and `activationEvents` stay
  required because the CLI never defaulted them. `ExtensionCommand`
  carries only `command`/`title` — the projection's optional fields
  (`category`, `enablement`, `shortTitle`, `icon`) went to futures.
  Suites at close: project_descriptor, cli_create, cli_build,
  cli_multi_baseline, cli_package, cli_modules, binding_evidence,
  plan_truth green; `flutter analyze` clean.
- [x] AD-2 Host command helper: a generated framework module gives
  authors `registerCommand(name, handler)` over the Generated API
  Layer — handler is ordinary Dart (`FutureOr<Object?>
  Function(List<Object?> arguments)`), the module owns
  toHostCallback/toHostPromise wrapping, JS conversion of arguments
  and results, and `context.subscriptions` registration. The
  coverage extension's `_registerCommand` helper and its remaining
  command-path interop tokens disappear. Check: a red template/module
  suite; the extension builds with the helper; interop-token count
  in `host/lib/extension.dart` recorded before/after.
  Closed (red 5521851, green aabc330, adoption 9b2c8d2): every
  project receives `host/lib/generated/host_commands.g.dart` from
  create and build. The interface deepened past the free function:
  `ExtensionCommands` holds the context/api seam once, so each call
  site is `commands.register(name, handler)` — the two ambient
  values every registration needs appear exactly once, and the
  method returns the native `Disposable` for early disposal while
  the subscription push owns the default lifetime. Handlers receive
  dartified arguments (up to eight; trailing nulls trimmed because
  compiled JavaScript cannot tell absent from undefined) and return
  protocol-safe data — null/bool/num/String/List/Map or a Future of
  one — jsified at the seam with an actionable failure for anything
  else. Proven by the five-case template suite (emitted==template,
  host-only build, fixture mirror) and a compiled dart2js/Node probe
  (dartified args, promise round trip, thrown-handler rejection,
  subscription count). Receipts: template + fixture instance joined
  all three contract copies, reconverged. Adoption moved all eight
  coverage commands onto the helper: interop tokens in
  `host/lib/extension.dart` 21 -> 14 matching lines (25 -> 17
  occurrences), the survivors real API values rather than command
  plumbing.
- [x] AD-3 Declare-once codecs: `view_protocol.dart` (still one
  self-contained file) gains a value-codec combinator so a contract
  type declares its fields once and derives encode + decode + the
  exact-schema guard from the same declaration; the shared contract
  rewrites onto it with a measured line drop, and the assembled
  `ViewOperation` consts move into the shared package so host and
  view import one declaration instead of maintaining twins. Check: a
  red codec unit suite (round-trips, missing/extra-key rejection,
  null handling); shared-contract tests green with the line delta
  recorded; protocol suites green unmodified.
  Closed (red ab53167, green f6a727c, contract home c3663b9,
  adoption f51882f): `ViewValueSchema` declares each field once —
  wire key, `ViewValueKind`, getter — inside a declaration callback
  whose returned constructor wiring rebuilds the type, deriving
  encode, decode, and the exact-schema guard; missing, extra, and
  wrong-typed keys throw `FormatException` naming the key, with list
  indexes and nested keys chained. Kinds compose (`orNull`, `listOf`,
  lazy `nested` for the recursive coverage tree) and scalars double
  as bare payload codecs. Moving the assembled operations required a
  protocol identity host and view can share, and Dart's nominal
  types forbid one across two library copies — so the verbatim copy
  now lands in `shared/lib/generated/`, the host's
  `view_protocol.g.dart` re-exports it (host + shared unify), and
  the view — whose session is
  `package:flutter_vscode/view.dart`'s distinct copy — calls
  through the structural `operationCaller`/`callThrough` function
  seam, which adds no capability that assembling a `ViewOperation`
  by name did not already grant. The shared contract rewrote onto
  schemas with the three operations declared once: shared 185 -> 188
  lines (+3 while absorbing the declarations that previously lived
  twice), host extension 327 -> 304, view main 430 -> 409, net
  942 -> 901. The 13-case schema suite is green; the frozen protocol
  suites (67 + 15) passed byte-unmodified; copies refreshed verbatim
  and the contract chain reconverged with the shared copy receipted
  as `generatedSharedViewProtocol`; the extension rebuilds and
  packages on the shared declarations.
- [x] AD-4 Final bar: coverage extension rebuilt and packaged on all
  three improvements; fast suites + analyze green; the real-host
  gates green at HEAD (host fixture, coverage extension,
  breakpoints).

## TDD Ledger

Tallies are recording-time values. Entries appended as items close.

1. **AD-1** (red 57e4b28, green df56f2f, migration 39422ae): the red
   `project_descriptor_test.dart` landed against the typed end state
   — 13 of its 16 cases failed on the map-era parser (the three that
   passed asserted literal-rule wording the old parser shared) —
   together with the consumer-suite moves (typed create
   expectations, the analyzable root pubspec, apiTarget rewrite
   patterns, the modules scaffold). Green: `lib/manifest.dart` plus
   the invocation-walking parser, the typed scaffold with its
   analyzability pubspec, and the contract chain reconverged in one
   `--contract` + fixture-rebuild pass; cli_create, cli_build,
   cli_multi_baseline, cli_package, cli_modules, binding_evidence,
   plan_truth, and the new descriptor suite all green with `flutter
   analyze` clean. The migration commit rebuilt the coverage
   extension on the typed form with a byte-identical generated
   `package.json`.
2. **AD-2** (red 5521851, green aabc330; adoption 9b2c8d2): the
   five-case suite `host_commands_template_test.dart` landed red
   against the promised end state — an `ExtensionCommands` template
   with an ordinary-Dart handler signature, byte-for-byte emission
   for host-only and view projects, a fixture mirror, and a compiled
   dart2js/Node probe proving dartified arguments and a promise
   round trip — over a committed empty placeholder template, and all
   five cases failed. Green filled the template, wired create/build
   emission, and joined the receipt closure in all three contract
   copies to convergence; every case passed without edits, alongside
   binding_evidence, cli_create, and cli_build. The adoption commit
   moved all eight coverage-extension commands onto the helper with
   the interop-token drop recorded (21 -> 14 lines, 25 -> 17
   occurrences).
3. **AD-3** (red ab53167, green f6a727c; contract home c3663b9,
   adoption f51882f): the 13-case `view_value_schema_test.dart`
   landed red against the promised combinator — schema round trips
   including the recursive tree, missing/extra/wrong-typed-key
   rejections naming the key, null handling, scalar payload kinds,
   and the structural `operationCaller`/`callThrough` seam — and
   failed to load, since none of the API existed and the receipted
   verbatim protocol copies rule out a placeholder inside
   `view_protocol.dart`. Green added the combinator and seam in the
   one self-contained file; all 13 cases passed and the frozen
   protocol suites (67 + 15) stayed byte-unmodified and green. The
   contract-home commit relocated the emitted verbatim copy into the
   shared package behind a host re-export (receipted, reconverged;
   cli_view and repository_gate repinned to the relocated copy), and
   the adoption commit rewrote the shared contract onto schemas with
   the three operations declared once (shared 185 -> 188, host
   327 -> 304, view 430 -> 409; shared suite 16 and view suite 7
   green; extension rebuilt and packaged).
4. **AD-4** (2026-07-26): the merged round rebuilt and packaged the
   coverage extension on all three improvements; the full fast suite
   is 554 green plus the known cli_watch contention flake (green
   standalone in 8s, as first recorded in the A-1 round) with analyze
   clean, and the three real-host gates
   exited 0 at HEAD (cold start 223ms; watcher push applied;
   breakpoint paused on the Dart line). The merge dropped one
   allowlist entry (restored red-green style with the suite), and the
   round also fixed the pre-existing doctor defect AD-1 surfaced:
   json descriptors now route through the json reader, proven by a
   new red-first doctor case.
