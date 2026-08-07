# Testing and Error Handling

## Error Handling

- Give CLI, generation, and protocol failures stable codes plus the offending
  source path/value and an actionable next step.
- Fail closed when pinned schemas or declarations drift.
- Preserve Dart messages and stack frames across host promise boundaries.
- Use structured protocol errors; do not leak arbitrary exception objects.

CLI diagnostics use `CODE: actionable message` on standard error. Treat codes
such as `INVALID_PROJECT_NAME`, `UNSAFE_PROJECT_LAYOUT`, and
`UNSAFE_PACKAGE_OUTPUT` as the machine-readable contract; message wording may
be clarified without changing the code.

The pinned VS Code manifest inputs type-check extension identity fields but do
not provide a safe output-file grammar. As an additional framework safety
constraint, `name` and `publisher` use lower-kebab components
(`^[a-z0-9][a-z0-9-]*$`). The packager separately verifies that the normalized
VSIX path remains beneath `build/`.

## Testing

- Use red-green-refactor for each public seam.
- Unit-test canonical import, generation, and protocol validation.
- Regenerate twice and byte-compare managed artifacts.
- Exercise activation, commands, providers, events, identity, promises, and
  cleanup in a pinned real Extension Host.
- Install the packaged VSIX in an isolated profile and exercise it through a
  separate test extension.
- For Flutter Views, test handshake, allowlisting, errors, close/reload, late
  frames, rendered output, and zero pending/subscription counts.

## Related

- [Contributing Index](../contributing/index.md)
- [Code Generation Rules](code-generation.md)
