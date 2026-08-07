---
status: accepted
---

# Provide Parity and Idiomatic API Layers

Extension Authors will normally use an Idiomatic Facade with Dart futures,
streams, nullability, collections, cancellation, named parameters, and typed
resource lifetimes. A complete Parity Layer beneath it will map every stable
symbol in the API Parity Baseline and remain available when a curated Dart shape
does not yet exist.

The Parity Layer prevents ergonomics work from delaying VS Code coverage; the
Idiomatic Facade prevents full coverage from feeling like TypeScript syntax
transliterated into Dart. Both are generated and share the same host interop.

---

Amended 2026-07-25: the generated-facade half of this decision is
superseded by ADR 0013. One generated API artifact now carries the
Parity Layer substrate and a total, mechanical Dart-ergonomics surface;
the Idiomatic Facade role passes to hand-written framework modules over
that single layer, not a second generated layer.
