# VS Code API Parity

<!-- GENERATED FILE - DO NOT EDIT. -->
<!-- Regenerate: dart tool/binding_generator/generate.dart
     --parity . -->

Typed parity is total by construction (ADR 0012, ADR 0013):
the one generated API artifact, exported as
`package:dart_vscode/dart_vscode.dart`, maps every public
declaration of the pinned API via Total Mapping Rules — the
Parity Layer substrate and the Dart-ergonomics surface in one
file, each with its own totality ledger gated by the parity
and dart-layer suites. A capability the generator cannot map
is a defect that fails the build (the vision rule,
mechanized).

Live coverage is measured on two axes (see CONTEXT.md:
API Family, Construct Class), both machine-derived and
enforced by the parity suite and the real Extension Host
gate.

Family axis (derived from the pinned IR): at least one representative
member of every API namespace family executes against live VS Code in
the real-host parity smoke, so a new family cannot be skipped silently.
The 16 families: `authentication`, `chat`, `commands`, `comments`,
`debug`, `env`, `extensions`, `l10n`, `languages`, `lm`, `notebooks`,
`scm`, `tasks`, `tests`, `window`, `workspace`.

Construct-class axis (derived from the emitter constant): every Total
Mapping Rule construct class has a rule-level unit case over synthetic
IR, and every class without a recorded exemption carries a `cc:`-tagged
probe in the same live gate. The 23 classes: `array`, `call-signature`,
`declared-constructor`, `default-constructor`, `external-setter`,
`function-type`, `index-signature`, `intersection`, `mixed-union`,
`narrowing`, `numeric-enum`, `object-literal-factory`,
`optional-member`, `overload-set`, `promise-thenable`,
`readonly-property`, `reserved-name`, `rest-parameter`,
`stable-typedef`, `string-literal-union`, `tuple`, `type-literal`,
`underscore-name`.

Live-exempt construct classes, each with its recorded
reason:

- `readonly-property` — the rule is the absence of a setter, provable only at compile time
- `string-literal-union` — zero occurrences in the pinned baseline; rule proven on synthetic IR
- `underscore-name` — the only baseline sites are deprecated internal fields with no stable behavior to observe

The table below is the behavioral-verification burn-down: a
`pending` row is public surface whose typed binding exists
but has not yet carried real-Extension-Host evidence through
the receipted capability fixtures. Generated
from the coverage ledger, regenerated and byte-compared by
the repository gates.

Pinned inventory: 2982 declarations discovered; 53 emitted and host-verified; 17 excluded (reviewed or non-public); 2912 pending.

| Container | Emitted | Reviewed excluded | Non-public | Pending |
| --- | ---: | ---: | ---: | ---: |
| `global` | 1 | 0 | 0 | 0 |
| `vscode (root)` | 43 | 6 | 10 | 2603 |
| `vscode.authentication` | 0 | 0 | 0 | 11 |
| `vscode.chat` | 0 | 0 | 0 | 2 |
| `vscode.commands` | 3 | 0 | 0 | 2 |
| `vscode.comments` | 0 | 0 | 0 | 2 |
| `vscode.debug` | 0 | 0 | 0 | 19 |
| `vscode.env` | 0 | 0 | 0 | 22 |
| `vscode.extensions` | 0 | 0 | 0 | 4 |
| `vscode.l10n` | 0 | 0 | 0 | 12 |
| `vscode.languages` | 2 | 0 | 0 | 41 |
| `vscode.lm` | 0 | 0 | 0 | 8 |
| `vscode.notebooks` | 0 | 0 | 0 | 4 |
| `vscode.scm` | 0 | 0 | 0 | 3 |
| `vscode.tasks` | 0 | 0 | 0 | 9 |
| `vscode.tests` | 0 | 0 | 0 | 2 |
| `vscode.version` | 0 | 0 | 0 | 1 |
| `vscode.window` | 2 | 1 | 0 | 94 |
| `vscode.workspace` | 2 | 0 | 0 | 73 |

Behavioral evidence enters through the receipted real-host
gates and capability fixtures; a `pending` entry leaves that
state only with executable real-host evidence. A new baseline
construct with no Total Mapping Rule blocks the release
(ADR 0008 as evolved by ADR 0012).
