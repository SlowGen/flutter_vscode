---
status: accepted
---

# Generate Bindings Deterministically

The Binding Pipeline will parse a pinned official VS Code API definition into a
canonical intermediate representation and mechanically generate Dart bindings,
host interop, idiomatic transformations, contribution models, and a coverage
ledger. The release pipeline will not use LLM inference, probabilistic mapping,
or undocumented heuristics; identical inputs and generator versions must
produce identical output.

This makes VS Code upgrades reviewable as source and generated diffs, allows CI
to detect every new or changed symbol, and prevents incorrect inferred bindings
from becoming runtime failures for Extension Users.
