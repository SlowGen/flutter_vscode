---
status: accepted
---

# Generate One API Layer

Context: ADR 0006 promised two generated API layers — a complete Parity
Layer and an Idiomatic Facade over it — and the walking-slice facade was
the reviewed, host-verified seed of the second layer. The owner's
deletion test dissolved that structure: the Dart-ergonomics layer is
generated from the same IR by the same total, judgment-free rules as
the Parity Layer, so shipping it *on top of* a separate substrate
artifact adds a file boundary with no information in it; and once a
total ergonomic layer exists for every declaration, the hand-reviewed
walking-slice facade has no remaining role that hand-written framework
modules and the evidence chain cannot serve better. Per-symbol reviewed
judgment was already rejected as unverifiable at scale (ADR 0012);
keeping a reviewed generated artifact alive for 53 members while 2,900
ship mechanically preserved ceremony, not safety.

Decision: generate exactly one API artifact.
`vscode_dart_layer.g.dart` is self-contained — the complete typed
Parity Layer substrate and the Dart-first ergonomic surface, with raw
escape hatches, in one file — exported as
`package:flutter_vscode/vscode_dart.dart` and emitted into every
Extension Project. The runtime and host-exports modules remain as
generated runtime plumbing, not API layers. Judgment-shaped ergonomics
live in hand-written framework modules in the
`FlutterViewHost`/`ViewShell` mold, never in a second generated layer.
Semantic Overrides remain the ADR 0008 release-gate classification for
baseline changes and do not shape the generated artifact.

Consequences: the walking-slice facade, its parity-slice sibling, and
the per-member binding-observation mechanism retire. Per-member
evidence follows the two-axis live-coverage model (API Family and
Construct Class representatives executed in a real Extension Host)
plus mechanical attribution to the one receipted Host Contract;
member-level live accounting via generated observation hooks is
tracked in `specs/plans/futures.md`. This supersedes the
generated-facade half of ADR 0006 — the Idiomatic Facade future is
now hand-written framework modules over the single layer — while ADR
0006's Parity Layer promise survives as the substrate inside the one
artifact, with its totality ledger intact.

## Amendment (ADR 0015)

The layer is no longer emitted into each Extension Project. It ships in the
pure-Dart `dart_vscode` package and projects import it, so a Host Dart
module keeps a Flutter-free dependency graph and no project carries a copy
that could drift. One generated layer still holds, in one place rather than
one per project. See
[ADR 0015](0015-ship-the-runtime-as-a-pure-dart-package.md).
