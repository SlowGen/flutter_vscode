# Contributing

This section covers contributor expectations and documentation navigation.

## Contents

- [Agent Guidelines](../agent-guidelines/index.md)
- [Code Quality and Dart Practices](../agent-guidelines/code-quality.md)
- [Testing and Error Handling](../agent-guidelines/testing-and-errors.md)

## Contribution Checklist

- Run analysis with project lint rules.
- Add or update tests when behavior changes.
- Keep generated and runtime contracts aligned.
- Update documentation links when structure changes.

## Local Validation

Install Flutter and Docker, and ensure the Docker daemon is running. Before
submitting changes, run:

```sh
flutter analyze
./scripts/ci_gates.sh
```

`ci_gates.sh` runs the repository's own CI workflow locally: every job on
the platform it declares -- the analyze/format/publish checks, every
package's suite under the standard `dart test`/`flutter test` runners, and
each real-host gate (the pinned Node-based binding importer, the source
Extension Host fixture, an installed VSIX, both shipped extensions, and
the breakpoint gate) in Docker against pinned VS Code.

## Related

- [Project README](../../README.md)
- [Documentation Index](../index.md)
