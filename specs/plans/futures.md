# Futures

Deferred work and the discovery inbox: findings made during a frozen
round land here instead of growing that round's exit bar. Items graduate
into a named plan under `specs/plans/` with their own machine-checked
exit bar; nothing here blocks a round's closure or commits to a
sequence or schedule. Rough dependency order below.

## Product

- **Marketplace publishing** (owner's account required): publish
  Coverage Treemap under a real publisher ID — the single biggest
  visibility step available; bundle the release-prep items (`upgrade`,
  support policy, docs-from-executable-behavior) at the same
  milestone.
- **More real extensions**: one outside the repository (the Dart-only
  sibling shipped as pubspec_lens) — the engine for idiomatic
  helpers, behavioral evidence, and protocol discoveries alike.

- **Idiomatic helpers** over the Generated API Layer: per ADR 0013
  the reviewed, judgment-shaped surface grows as hand-written
  framework modules in the `FlutterViewHost`/`ViewShell` mold (with
  their own tests), not as a second generated facade; candidates
  graduate here as real extensions surface the need — a broader
  options-to-named-parameters surface remains the largest known one.
- **Behavioral evidence grows through real extensions**: each new
  extension exercises more API families in real hosts; the two-axis
  live coverage (API Family × Construct Class) is the measured floor.
  No dedicated per-member instrument is planned — extensions produce
  better evidence than observation hooks did.
- Runtime semantics for the View protocol: handles and backpressure
  (cancellation, host-to-view requests, and event streams shipped in
  the archived developer-experience round's D-4; disposal is now
  per-request).
- The `create` scaffold's hello command still demonstrates raw
  `toHostCallback`; adopting the generated `ExtensionCommands` helper
  there (and in the README snippet that mirrors it) is a cheap DX
  follow-up from the authoring-dx round.
- Generated-file ownership and repair (doctor detects; repair is the
  follow-up). The v0-removal round deleted the legacy pipeline;
  `test/v0_removal_test.dart` keeps it deleted.
- Desktop platform proof beyond macOS: the macOS gate landed
  (`scripts/test_host_extension_native.sh` plus the CI desktop job);
  Windows is next — its drivers need their own path and launch
  handling. Remote-host and multi-extension hardening remain backlog
  behind it.
- Platform reach: Web Extension Host before 1.0 (ADR 0009).

- Optional command-contribution fields in the typed manifest: the
  generator's projection still validates `category`, `enablement`,
  `shortTitle`, and `icon`, but `ExtensionCommand` carries only
  `command` and `title` — extend the type (and its parser mirror in
  `lib/src/cli/project_descriptor.dart`) when a real extension needs
  one of the optional fields.

## Engineering debt (from the audits)

- Windows real-host gate: no gate proves the platform a real share of
  Extension Authors develop on. The native-mode gate scripts are
  already platform-agnostic bash-plus-node and the harness resolves
  the win32 VS Code build; a `windows-latest` job needs bash-via-git
  (or a PowerShell port of the thin scripts) and one person with a
  Windows machine to run the matrix once before trusting it in CI —
  shipping the job unexecuted would be green-by-hope.

(Resolved on the project-hardening branch: the live-webview CSP is now
asserted from the served document by the fixture's render observation,
and gate cache policy was decided rather than unified — the attesting
gates keep invocation-scoped caches because the Host Contract records
`cachePolicy: freshInvocationScoped`, while the example-extension
gates honor `FLUTTER_VSCODE_TEST_CACHE`.)
