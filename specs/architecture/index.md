# Architecture

How `flutter_vscode` works and how its claims stay true. These documents
are the living authority extracted from the archived
[first-working-extension plan](../plans/archive/first-working-extension.md)
when it closed; each rule below names the code or gate that enforces it,
because this project's history shows that unenforced prose rots.

- [Host Execution](host-execution.md) — how Dart runs inside VS Code's
  Extension Host, including the Development reload carve-out and the
  `hostFetch` network path.
- [Binding Pipeline](binding-pipeline.md) — pinned multi-baseline
  inputs to the one Generated API Layer plus the runtime and
  host-exports modules, and every regeneration command.
- [Evidence Chain](evidence-chain.md) — receipts, gates, the exit-bar
  methodology, and what "verified" is allowed to mean.
- [View Protocol](view-protocol.md) — the versioned Host/Flutter View
  boundary: typed calls both ways, host events, cancellation, and the
  theme bridge.
- [Author Workflow](author-workflow.md) — create, build (and watch),
  doctor, test, package, and how the installed result is proven.

The shipped examples under `extensions/` are an architectural surface
of their own: real, installable extensions that consume the framework
only the way an Extension Author can — through the CLI and the
published package surface, never the repository's `lib/`, `tool/`, or
fixtures. They are excluded from the pub archive (`.pubignore`) and
proven in a pinned real Extension Host by
`scripts/test_coverage_extension.sh`.

Status rule inherited from the plans: a completion claim is valid only
while its named check is green at HEAD. The archived
first-working-extension plan's one-shot exit checker is retired -- its
claims are carried forward by the CI workflow's suite and gate steps,
which subsume every check it ran; later
closed plans carry their own validity checks (the parity suite, the
coverage-extension gate), and
the archived
[developer-experience plan](../plans/archive/developer-experience.md)
and the archived
[architecture-deepening plan](../plans/archive/architecture-deepening.md)
each hold while the fast suites and the three real-host gates —
including `scripts/test_breakpoints.sh` — are green at HEAD.
Forward work is tracked in [futures](../plans/futures.md); API
coverage is measured in the generated
[parity report](../../docs/reference/parity.md).
