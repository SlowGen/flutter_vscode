# Code Quality and Dart Practices

## Analysis and Linting

- Use `very_good_analysis` and follow its rules.
- Follow Effective Dart guidance.

## Design Principles

- Keep the importer, binding generator, CLI orchestration, host interop, and
  cross-runtime protocol in separate modules.
- Keep Flutter View/browser adapters platform-specific and the protocol core
  transport-independent.
- Prefer deep typed interfaces over string-keyed maps and generic dispatchers. One carve-out: at JSON boundaries — the maintainer binding pipeline validating raw IR is the canonical case — string-keyed maps are the correct representation, and typed interfaces begin at the published API surface.

## Naming

- Use `VSCode*` for framework-owned VS Code adapters. Generated Parity Layer
  declarations preserve the upstream VS Code names (`Uri`, `Disposable`,
  `Commands`, and so on) so API diffs remain mechanically recognizable.
- Use `View*` for general cross-runtime protocol types. Role-specific session
  types may put the role first (`HostViewSession`, `FlutterViewSession`) when
  that reads more clearly at call sites.
- Use `*Generator` for generator classes.
- Use `*Element` naming for analyzer element types where applicable.

## Modern Dart

Prefer modern Dart patterns where they improve clarity:

- collection `if` and `for`
- cascade operator (`..`)
- records and pattern matching when appropriate
- `final` by default
- proper `async`/`await` usage with clear error handling

## JS Interop

Use `package:web` and `dart:js_interop`. Do not introduce `dart:js_util`.

## Related

- [Project Structure and Dependencies](project-structure.md)
- [Package Conventions and Documentation](package-conventions.md)
