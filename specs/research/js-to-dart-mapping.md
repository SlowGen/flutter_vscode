# Mechanical JS/TS-to-Dart Mapping: Prior Art and Total Rules

**Research question:** How are existing JavaScript/TypeScript libraries mechanically mapped to
typed Dart in the wild, and which techniques give TOTAL, judgment-free mapping rules that a
full-parity generator for `vscode.d.ts` (~2,972 public declarations) can adopt on top of
`dart:js_interop` extension types?

**Method note:** Findings below derive from a deep-research run in which 24 claims survived
3-vote adversarial verification (all cited claims were confirmed 3-0 against primary sources:
project repositories, generator source code, and official Dart documentation). One claim
("no legacy interop library works under Wasm") was refuted 0-3 and is deliberately not relied
on here. Date of research: 2026-07-22.

---

## Executive summary

Two proven, fully mechanical totality strategies exist in the wild. **Erasure** is what the
Dart team's own `package:web` generator uses: unions collapse to the least upper bound in the
JS type hierarchy, WebIDL enums become `typedef X = String`, callbacks become
`typedef X = JSFunction` — total and judgment-free, at the cost of type precision.
**Expansion/fabrication** is what Scala.js's ScalablyTyped uses to convert *all* of
DefinitelyTyped mechanically: unions become generated trait hierarchies, string literals
become sealed traits backed by `asInstanceOf` casts (a deliberate type-level "lie"), and
overload sets are fully duplicated with suffix-renamed variants — total *and* precise.
Google's archived `js_facade_gen` (the `package:js`-era TS-to-Dart generator) is the cautionary
precedent: wherever it lacked a total rule it reached for user flags (`--trust-js-types`,
`--explicit-static`), default assumptions, or an admittedly "arbitrary" intersection rule.
`dart:js_interop` extension types support a hybrid of the two proven strategies (erasure at the
`external` boundary plus generated non-external precision helpers), and a 100%-mechanical
mapping of `vscode.d.ts` is achievable at the type level — with exactly two flagged semantic
gaps where no judgment-free total rule was found in any ecosystem: distinguishing JS
`undefined` from `null` on read, and a proven member-merge rule for intersection types.

---

## Prior art surveyed

| Generator | Source → Target | Era / status | Overall strategy |
|---|---|---|---|
| `js_facade_gen` (Google) | arbitrary `.d.ts` → `package:js` facades | archived Dec 2022 (pre-extension-types) | merge + erase, with judgment flags [^jfg] |
| `package:web` generator | WebIDL + MDN → `dart:js_interop` extension types | current, Dart team | total erasure [^web] |
| ScalablyTyped | all of DefinitelyTyped → Scala.js | current | total expansion/fabrication [^st] |
| `dart:js_interop` itself | — (platform constraint set) | current, blessed; legacy interop deprecated Dart 3.7 [^past] | defines which encodings are expressible [^usage][^jstypes][^api] |

`js_facade_gen` is confirmed as a real, Google-published mechanical generator for arbitrary
TypeScript declaration files — but it targets the legacy `package:js` annotation model, not
extension types, and it is archived. Its per-construct rules are documented below because they
are the only direct TS→Dart precedent; its *failure* points are as instructive as its rules.

---

## Decision table, construct by construct

### 1. Untagged union types (e.g. `string | Uri`)

| Candidate encoding | Used by | Tradeoffs |
|---|---|---|
| **LUB erasure in the JS type hierarchy** — every interface erases to `JSObject`; a union of two interfaces → `JSObject`; mixed unions climb to `JSAny` | `package:web` (documented rule, implemented in `type_union.dart` over a fixed supertype map, `?? JSAny` fallback → total) [^web] | Judgment-free and total; loses all member access at the union site; callers must cast |
| Common-supertype erasure with `dynamic /* A\|B */` comment fallback | `js_facade_gen` (`MergedType.toSimpleTypeNode`: "For union types find a Dart type that satisfies all the types"; `findCommonType` often returns null → `dynamic`) [^jfg] | Total-ish but weak — frequently degrades to `dynamic`; legacy era |
| **Synthetic trait hierarchy** — rewrite `type BlobPart = BufferSource \| Blob \| String` into `_BlobPart \| String` with generated traits `Blob extends _BlobPart`, etc. | ScalablyTyped (for "long" unions whose members are all declared in the same library) [^st] | Precise and mechanical; generates synthetic types; conditioned on same-library membership |
| Sealed Dart wrapper classes | **No surveyed generator uses this** for a full-parity JS binding layer | Allocation and identity cost at the boundary; unproven |

**Hard platform constraint:** Dart `is`/`as` checks involving interop types are officially
unreliable — runtime representations differ between dart2js and dart2wasm, and the docs say to
"almost always avoid `is` checks" on interop types. Any union *narrowing* must therefore go
through JS-side helpers: `isA<T>()` (Dart 3.4+), `typeofEquals`, `instanceOfString`.
`identical` is likewise compiler-dependent. [^jstypes][^api]

**Recommended mechanical rule (total: YES):** adopt `package:web`'s LUB-erasure as the
`external` signature type (the exact same fixed-supertype-map algorithm transfers directly),
and — because extension types may contain non-external members [^past-caps] — additionally
generate per-member narrowing/creation helpers (`bool get isString => value.isA<JSString>()`,
`Uri get asUri => value as Uri`-style accessors built on `isA<T>`) to recover ScalablyTyped-like
precision without violating the no-`is` constraint. Both halves are syntax-directed from the IR.

### 2. Overload sets

| Candidate encoding | Used by | Tradeoffs |
|---|---|---|
| **Merge all overloads into one Dart signature**, parameters beyond the shortest overload made optional (`MergedMember`/`MergedParameter`/`MergedType`) | `js_facade_gen` — chosen "because Dart lacks method overloads" [^jfg-merge] | One member per name; per-overload typings destroyed (parameter types union-erased); silent widening |
| **Full duplication with rename**: every overload emitted as its own method, disambiguated variants like `getContext_2d`, `getContext_webgl` (suffix derived from literal-type arguments) | ScalablyTyped — "All the overloads are duplicated … because default parameters in Scala don't work in the presence of overloads" [^st] | Precise; more members; synthesized names |

**Enabler in modern Dart:** unlike `package:js` (which could not rename instance members or hold
non-external members), `dart:js_interop` extension types support `@JS('originalName')` on a
differently-named Dart member — the docs' own example is exactly the overload pattern:
`@JS('push') external int pushString(JSString string);` [^past-caps][^usage]

**Recommended mechanical rule (total: YES):** rename-with-suffix expansion. Emit one Dart
member per TS overload, all bound to the JS name via `@JS('name')`, disambiguated by a
deterministic suffix (declaration-order index, e.g. `createQuickPick`, `createQuickPick$2` — an
index is judgment-free where ScalablyTyped's literal-derived names are only *usually*
derivable). Optionally also emit `js_facade_gen`-style merged convenience signatures as
non-external members, but the parity layer itself should be the expansion.

### 3. String-literal union types (`'left' | 'right'`)

| Candidate encoding | Used by | Tradeoffs |
|---|---|---|
| **Erase to `String`** — `typedef ShadowRootMode = String;` (no Dart enum) | `package:web` for WebIDL enums, the closest analogue [^web-erase] | Total; zero compile-time safety |
| **Sealed trait per literal + cast** — each literal becomes a sealed trait; values produced by `"-moz-initial".asInstanceOf[\`-moz-initial\`]`; the docs call it "a neat lie to fool scalac" | ScalablyTyped [^st-lit] | Total, zero runtime cost, full type-level precision over runtime strings |
| Dart `enum` with to/from-string mapping | no surveyed generator | Requires conversion at every boundary crossing; enum can't BE the JS string |

**Recommended mechanical rule (total: YES):** the Dart analogue of ScalablyTyped's encoding is
directly expressible and stays judgment-free: emit an extension type over `String` (or
`JSString` in generic positions) with one generated `static const`-style accessor per literal —
type-level precision, runtime representation is the string itself. Plain
`typedef X = String` (the `package:web` rule) is the acceptable fallback and equally total.

### 4. Structural / anonymous object types (type literals, options bags)

- **Blessed reading rule:** emit an extension type wrapping `JSObject` with typed external
  getters — the exact rule `package:web` applies to every WebIDL interface and dictionary
  ("extension types that wrap and implement `JSObject`", inheritance via `implements`, mixin
  and partial members folded into the including type). [^web-iface]
- **Blessed creation rule:** the object-literal constructor — an external constructor with
  *only named parameters* whose names match the JS property names:
  `external Options({int a, int b});` produces `{a: 0, b: 1}`, with deterministic
  omitted-argument semantics (`Options(a: 0)` → `{a: 0}`). [^usage-lit]
- **Constraint:** external interop *methods* can only take positional/optional-positional
  arguments; named parameters are reserved exclusively for object-literal constructors. So a TS
  options-bag parameter must be encoded as a generated options extension type + literal
  constructor, never as Dart named method parameters. [^usage]
- **Historical contrast:** `js_facade_gen` had *no* judgment-free rule here — structural typing
  was gated behind the user-decided `--trust-js-types` flag, which emitted `@anonymous` on
  classes lacking constructors/statics and explicitly traded away DDC runtime checking. [^jfg-flags]
  Extension types dissolve this whole problem: they are erased, prototype-check-free wrappers by
  construction, so the flag's dilemma no longer exists.

**Recommended mechanical rule (total: YES, with one syntactic edge):** every TS type literal /
anonymous object type gets a synthesized, deterministically named extension type over
`JSObject`; read members as external getters, create via object-literal constructor.
*Edge:* JS property names that are not valid Dart identifiers cannot be Dart named parameters
(constructor position cannot be `@JS`-renamed the way members can). The mechanical fallback is a
generated non-external factory using `dart:js_interop_unsafe` `setProperty` — a two-branch but
still judgment-free rule. Likely rare-to-absent in `vscode.d.ts`; needs a census (see open
questions).

### 5. Index signatures (`[key: string]: T`)

Only two external operators are allowed on interop extension types: `[]` and `[]=` — everything
else is expressible solely through utility functions. [^usage]

**Recommended mechanical rule (total: YES):** map each TS index signature to
`external T operator [](String key);` / `external void operator []=(String key, T value);`
typed per the signature (or `dart:js_interop_unsafe` `getProperty`/`setProperty` where the value
type is not interop-compatible). No other operator-based encoding is blessed, so there is no
choice to make — which is what makes the rule total.

### 6. Static-vs-instance member split

`js_facade_gen` did **not** have a purely mechanical rule: it applied a *default assumption*
that properties on the anonymous types of top-level variable declarations are static (injecting
the `static` keyword during merge), disabled by `--explicit-static` — the same input produced
different output depending on a human-chosen flag. [^jfg-flags]

**Recommended mechanical rule (total: YES for vscode.d.ts's constructs):** take staticness
directly from the TS declaration form — `static` members of classes are static, namespace
members are static (or members of a singleton accessor extension type), instance members are
instance. The heuristic in `js_facade_gen` existed only for the *variable-typed-by-anonymous-
type* merging pattern; for that pattern the judgment-free encoding is an extension type over the
variable's value with *instance* members, accessed through a generated top-level getter — no
assumption required.

### 7. Callbacks / function types

| Candidate encoding | Used by | Tradeoffs |
|---|---|---|
| **Erase to `JSFunction`** — `typedef MutationCallback = JSFunction;` | `package:web` (callbacks *and* callback interfaces) [^web-erase] | Total; signature information destroyed |
| Typed signatures via `Function.toJS` wrappers | blessed by the platform, with a hard restriction: every value crossing the boundary "must be a compatible interop type or a primitive" — enforced at compile time [^jstypes] | Total *because* the restriction is checkable: the parity mapper already maps every TS type to an interop type, so mapped callback signatures always satisfy it |

**Recommended mechanical rule (total: YES):** parity signature type is `JSFunction`
(package:web precedent, safest across the `external` boundary), plus a generated `typedef` and
non-external convenience adapter per TS function type whose Dart signature uses the mapped
interop types and converts via `.toJS`. The `toJS` restriction is not a gap for a parity
generator — it is satisfied by construction, since the generator never emits non-interop types
in callback positions.

### 8. `Thenable<T>` / `Promise<T>`

The SDK ships blessed, total bidirectional conversions: `JSPromiseToFuture` (`.toDart`),
`FutureOfJSAnyToJSPromise` / `FutureOfVoidToJSPromise` (`.toJS`), defined for every
`JSPromise<T extends JSAny?>` / `Future<T extends JSAny?>` — i.e., for everything the parity
mapping produces. [^api]

**Recommended mechanical rule (total: YES):** `Promise<T>` and `Thenable<T>` →
`JSPromise<mapped(T)>`; expose `Future` via `.toDart` in non-external helpers. Known
deterministic caveats, not judgment points: `.toDart` throws `NullRejectionException` on
null/undefined rejection; Dart→JS rejection wraps the error in a JS `Error`;
`Future<void>.toJS` yields a raw `JSPromise`. `Thenable → JSPromise` is this project's own
(sound) extension of the documented rule: `.toDart` works through `.then`, which any thenable
has, and `.toJS` produces a real `Promise`, which satisfies `Thenable`.

### 9. Optional members, `readonly`, getters/setters — and the `undefined` vs `null` gap ⚠️

Type-level mapping is total: `T | undefined` and optional (`?:`) members map to `mapped(T)?`;
`readonly` maps to an external getter with no setter; TS getter/setter pairs map directly.

**FLAGGED — no judgment-free total rule exists anywhere for the semantics:** both JS `null`
and JS `undefined` are mapped to Dart `null` by the compilers, and there is "no
platform-consistent way to provide `undefined` to interop members or distinguish between JS
`null` and `undefined` values" — the SDK's `isUndefined`/`isNull` helpers throw on dart2wasm.
Behavior even differs between backends when a Dart `null` flows back into JS (dart2js preserves
undefined-ness; Wasm produces `null`). [^jstypes] A parity layer therefore *cannot*
mechanically distinguish an absent optional property from one explicitly set to `null` on
read. `JSObject.hasProperty` can probe existence (the JS `in` operator), but that is a separate
check, not a value read. **Recommended rule:** conflate both to `T?`, document the conflation
in generated doc comments, and emit `has<Name>` existence probes only where `vscode.d.ts`
semantics demonstrably distinguish the two. This is one of the two genuine totality gaps.

### 10. Intersection types (`A & B`) ⚠️

**FLAGGED — no proven total rule found in any surveyed ecosystem:**

- `js_facade_gen` "arbitrarily pick[s] the first type of the intersection type" and discards the
  rest, with the authors' own unresolved `TODO(jacobr): re-evaluate this logic`. [^jfg-merge]
- ScalablyTyped's docs show intersection fallbacks reduced to *comments* for inexpandable
  generic mappings (e.g. `Partial<T>`). [^st]

A candidate Dart encoding does exist and can be made deterministic — synthesize an extension
type that `implements` both operands' extension types (the same composition mechanism
`package:web` uses for interface inheritance and mixin folding [^web-iface]), with a fixed
member-conflict resolution order — but **no generator in the wild has demonstrated it**, so it
cannot be claimed as proven-total prior art. Mitigation: intersections are expected to be rare
or absent in `vscode.d.ts` (census required); if absent, the generator can make unsupported
intersections a *hard generation error* (actionable failure, per project rules) rather than an
arbitrary pick, keeping the shipped mapping judgment-free.

### 11. Generics over JS types

`dart:js_interop` generics are bounded by `JSAny?`. `package:web`'s mechanical companion rule:
prefer Dart primitives (`String`, `int`) in ordinary positions, but any primitive-typedef'd type
appearing in a *generic* position (inside `JSArray`/`JSPromise`, the generic types it carries
through) is swapped back to its JS equivalent (`JSString`, `JSNumber`) to respect the bound. [^web]

**Recommended mechanical rule (total for the observed forms):** carry TS generics through as
Dart generics with `T extends JSAny?` bounds; apply the primitive/generic-position swap exactly
as `package:web` does. **Under-evidenced:** general TS generics with non-interop constraints,
F-bounded cases, and default type arguments had no surviving claims — the `vscode.d.ts` census
must enumerate which generic shapes actually occur (see open questions).

### 12. Classes, interfaces, inheritance, mixin-like structures

`package:web`'s rule transfers wholesale: one extension type per interface, wrapping and
implementing `JSObject`; inheritance via `implements` between extension types; partial-
interface/mixin members folded into the including type with no separate declaration. [^web-iface]
Total: YES.

### 13. Constructs with no surviving evidence (unrated)

Tuple types, conditional types, mapped types, and template-literal types produced no verified
claims in this research run. If the `vscode.d.ts` IR contains any of them, the safe total
policy is: erase to the LUB (tuples → `JSArray<LUB(members)>`) or fail generation loudly —
never silently guess.

---

## Platform constraints ledger (what `dart:js_interop` rules out / blesses)

| Constraint | Consequence for the generator | Source |
|---|---|---|
| Legacy interop (`package:js`, `dart:js`, `dart:js_util`) deprecated as of Dart 3.7 (Feb 2025) | Target `dart:js_interop` + `dart:js_interop_unsafe` only; `js_facade_gen`-era encodings are not adoptable as-is | [^past] |
| One abstraction for both backends: the same declarations must work compiled to JS *and* Wasm | Only dual-backend-valid encodings; no backend-specific tricks | [^api] |
| JS types carry static guarantees only; `is`/`as`/`identical` unreliable across backends | Union narrowing via `isA<T>()`/`typeofEquals`/`instanceOfString`, never Dart `is` | [^jstypes][^api] |
| `null`/`undefined` both read as Dart `null`; no platform-consistent distinction; divergent round-trip behavior | Optionality conflation is unavoidable (gap #9) | [^jstypes] |
| External methods: positional/optional-positional params only; named params exclusively in object-literal constructors | Options bags → generated literal-constructor extension types | [^usage] |
| Only `[]`/`[]=` external operators | Index signatures have exactly one encoding | [^usage] |
| `Function.toJS`: boundary values must be interop types or primitives (compile-enforced) | Callback adapter signatures use mapped interop types — satisfied by construction | [^jstypes] |
| Extension types may rename members via `@JS('name')` and contain non-external members | Enables overload rename-with-suffix and union-narrowing helpers — the two pillars of the hybrid strategy | [^past-caps][^usage] |
| Blessed conversions: `JSPromise.toDart`, `Future.toJS` (incl. `void`) | Promise/Thenable rule is total | [^api] |

---

## Verdict: can the vscode.d.ts mapping be 100% mechanical?

**Yes at the type level, with two flagged semantic gaps and one syntactic edge.**

- Every construct in sections 1–8, 11–12 has a judgment-free total rule proven in the wild
  (package:web's erasure rules, ScalablyTyped's expansion rules) and expressible in
  `dart:js_interop` extension types. The recommended hybrid: **erasure at the `external`
  boundary, generated non-external precision helpers on top.**
- **Gap 1 — `undefined` vs `null` on read:** no ecosystem has a platform-consistent rule;
  conflate to `T?` and document (mechanical, but semantically lossy by necessity).
- **Gap 2 — intersection types:** every surveyed generator punted (arbitrary-first pick with a
  TODO, or comment fallback); a deterministic `implements`-both encoding is plausible but
  unproven. Prefer hard generation error if the census finds none in `vscode.d.ts`.
- **Edge — non-identifier property names** in object-literal constructor position: mechanical
  `setProperty`-factory fallback exists; two-branch rule, still judgment-free.
- Where no rule exists (tuples/conditional/mapped types, if present), fail generation with an
  actionable error rather than heuristically approximating — this keeps the "NO inference,
  judgment, or heuristics" contract intact, in the spirit of ADR-0008's
  block-on-unclassified-symbols gate.

---

## Sources

[^jfg]: `js_facade_gen` README and `lib/main.ts` — https://github.com/dart-archive/js_facade_gen (archived; "Generates `package:js` JavaScript interop facades for arbitrary TypeScript libraries").
[^jfg-flags]: `js_facade_gen` README, `--trust-js-types` and `--explicit-static` flags; `lib/merge.ts` `normalizeSourceFile` static-keyword injection — https://github.com/dart-archive/js_facade_gen
[^jfg-merge]: `js_facade_gen` `lib/merge.ts` (`MergedMember`, `MergedParameter`, `MergedType`, intersection "Arbitrarily pick the first type … TODO(jacobr): re-evaluate this logic") and `lib/declaration.ts` `visitMergingOverloads` — https://github.com/dart-archive/js_facade_gen/blob/master/lib/merge.ts
[^web]: dart-lang/web `web_generator/README.md` translation conventions; `js_interop_gen/lib/src/type_union.dart`, `elements.dart`, `js_type_supertypes.dart` — https://github.com/dart-lang/web ("Union types are computed by picking the least upper bound of the types in the JS type hierarchy, where every interface is equivalent to `JSObject`").
[^web-iface]: dart-lang/web `web_generator/README.md` — "Interfaces are emitted as extension types that wrap and implement `JSObject` … inheritance … using `implements` … Members of partial interfaces, partial mixins, and mixins are added to the interfaces that include them."
[^web-erase]: dart-lang/web `web_generator/README.md` — "Enums are typedef'd to `String`. Callbacks and callback interfaces are typedef'd to `JSFunction`." Confirmed in emitted `lib/src/dom/dom.dart` (`typedef ShadowRootMode = String;`, `typedef MutationCallback = JSFunction;`).
[^st]: ScalablyTyped encoding documentation — https://scalablytyped.org/docs/encoding (union trait rewriting; overload duplication: "All the overloads are duplicated … because default parameters in Scala don't work in the presence of overloads"; `getContext_2d` example).
[^st-lit]: ScalablyTyped encoding documentation, "Whatsup with strings?" — sealed trait per literal, `"-moz-initial".asInstanceOf[...]`, "A neat lie to fool `scalac`" — https://scalablytyped.org/docs/encoding
[^jstypes]: Dart official docs, JS types — https://dart.dev/interop/js-interop/js-types (runtime-type divergence and `is`-check prohibition; `isA`/`typeofEquals`/`instanceOfString`; null/undefined conflation and backend divergence; `Function.toJS` boundary restriction).
[^usage]: Dart official docs, interop usage — https://dart.dev/interop/js-interop/usage (positional-only external methods; object-literal constructors with named params matching property names; `[]`/`[]=` as the only external operators; `@JS('name')` member renaming).
[^usage-lit]: https://dart.dev/interop/js-interop/usage — object literal constructor example (`external Options({int a, int b});` → `{a: 0, b: 1}`).
[^api]: `dart:js_interop` API reference — https://api.dart.dev/stable/latest/dart-js_interop/index.html (dual-backend abstraction; static-guarantees-only warning; `JSPromiseToFuture`, `FutureOfJSAnyToJSPromise`, `FutureOfVoidToJSPromise`; confirmed against Dart SDK 3.12.2 `lib/js_interop/js_interop.dart`).
[^past]: Dart official docs, past JS interop — https://dart.dev/interop/js-interop/past-js-interop ("Previous iterations of JS interop for Dart are considered legacy and are deprecated as of Dart 3.7 (Feb 2025)"), corroborated by the Dart 3.7.0 changelog.
[^past-caps]: https://dart.dev/interop/js-interop/past-js-interop — "'package:js' types could not rename instance members or have non-external members"; renaming + non-external members demonstrated at https://dart.dev/interop/js-interop/usage (`@JS('push') external int pushString(...)`).

---

## Open questions

1. **VS Code precedent (research angle 5, no surviving evidence):** did any ecosystem
   (Kotlin/Dukat, Scala/ScalablyTyped, ReScript, F#/ts2fable, Haxe, Nim) mechanically translate
   the *full* `vscode.d.ts`, and what did they punt on? ScalablyTyped almost certainly processed
   it as part of DefinitelyTyped, but no verified claim about its `vscode` output survived.
2. **Kotlin's Dukat/karakum rules (angle 3, partial coverage):** their union/overload/
   anonymous-type encodings and documented failure modes were not verified in this run and would
   be a useful third proof point alongside package:web and ScalablyTyped.
3. **vscode.d.ts construct census:** does the IR actually contain intersection types, tuples,
   conditional/mapped/template-literal types, non-identifier property names, or F-bounded
   generics? Each flagged gap above is moot if the construct never occurs — and a hard
   generation error is then the correct total rule.
4. **Union-helper totality:** can `isA<T>`-based narrowing helpers be generated totally for
   unions whose members are typedefs, generics, or other unions (e.g. `Thenable<T> | T`), given
   `isA`'s documented type-argument restrictions?
