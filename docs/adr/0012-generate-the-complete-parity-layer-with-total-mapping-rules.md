---
status: accepted
---

# Generate the Complete Parity Layer with Total Mapping Rules

The Parity Layer will cover the entire API Parity Baseline in one mechanical
generation pass, produced exclusively by Total Mapping Rules: judgment-free,
deterministic rules that map each class of TypeScript construct to
`dart:js_interop` code for every occurrence. The strategy is erasure at the
`external` boundary (the `package:web` precedent: unions erase to their least
upper bound in the JS type hierarchy) combined with generated Precision
Helpers (the ScalablyTyped precedent adapted to extension types): per-
overload `@JS`-renamed members, typed tuple access, object-literal `lit$`
factories for interfaces and type literals, module-rooted constructors
including defaults for ctor-less classes, call-signature helpers, derived
stable typedefs for anonymous shapes, `isInstance`/`cast` narrowing on
every class object (via `prototype.isPrototypeOf`, since the platform
offers no constructor-rooted `instanceOf`), and zero-cost typed wrappers
for string-literal unions (a proven rule; the pinned baseline contains
no such unions). (A sixth-audit amendment recorded two of these families
as unshipped; the parity-runtime round shipped them and this text again
describes reality.) A construct with no Total
Mapping Rule fails generation with an actionable error; nothing is
approximated, guessed, or resolved by review. Semantic Overrides no longer
participate in the Parity Layer and apply only to the Idiomatic Facade.

This supersedes the walking-slice model in which every emitted symbol
required a reviewed Semantic Override and real-host evidence before emission.
Per-symbol review does not scale to 2,972 declarations and — as five
hardening rounds demonstrated — reviewed judgment is precisely the ingredient
that resists mechanical verification. Research across ecosystems
(`specs/research/js-to-dart-mapping.md`) established that total rules exist
for every construct in the pinned baseline: the two flagged gaps are the
platform-wide `undefined`/`null` conflation (mapped to `T?` and documented —
no ecosystem can distinguish them) and intersection types (six occurrences in
the baseline, covered by a deterministic implements-both encoding; any future
shape it cannot express fails generation).

ADR 0008's release gate evolves accordingly: a release is blocked when a new
baseline introduces a construct with no Total Mapping Rule, and the block is
lifted only by adding a rule — never a per-symbol judgment. Behavioral
verification (real Extension Host evidence) and Idiomatic Facade coverage
move from emission gates to measured burn-downs. The trade-off is accepted
deliberately: the erased boundary is less precise than hand-reviewed
signatures, but it is total, immediately available for every capability,
recovers precision through generated helpers, and keeps the pipeline free of
the judgment calls that undermined verifiability.

---

Amended 2026-07-25: the Parity Layer no longer ships as a standalone
artifact. Per ADR 0013 it is the substrate inside the one generated API
artifact (`vscode_dart_layer.g.dart`), with its totality ledger
(`tool/bindings/parity-ledger.json`) intact and still gated. Everything
else here — Total Mapping Rules, erasure with Precision Helpers, and
the evolved ADR 0008 release gate — stands unchanged.

Amended 2026-07-25 (release-gate precision): the two gates compose
rather than replace each other. Per-symbol reviewed classification
survives at baseline import — a candidate baseline with a new or
changed public symbol is rejected until its Semantic Override entry
lands (ADR 0008 as amended) — while the no-Total-Mapping-Rule block
described here applies at layer generation: a construct no rule can
consume fails the build regardless of classification.
