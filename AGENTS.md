# AGENTS Index

This file is the root index for AI and contributor documentation.

## Canonical File Naming

- Use `AGENTS.md` (uppercase) as the only canonical root agent-instruction file.

## Shared Agent Layout

- `CLAUDE.md` and `GEMINI.md` import the shared rules from `AGENTS.md`.
- Keep project skills in `.claude/skills/`; `.agents/skills` points there.

## Quick Navigation

- [Project Vision](specs/vision/vision.md)
- [Architecture (living)](specs/architecture/index.md)
- [Futures (deferred-work inbox)](specs/plans/futures.md)
- [Archived Plans](specs/plans/archive/)
- [Domain Language](CONTEXT.md)
- [Architecture Decisions](docs/adr/)
- [Documentation Root](docs/index.md)
- [Agent Guidelines](docs/agent-guidelines/index.md)
- [Architecture](docs/architecture/index.md)
- [Guides](docs/guides/index.md)
- [Reference](docs/reference/index.md)
- [Contributing](docs/contributing/index.md)

## Root Project Documents

- [README](README.md)
- [dart_vscode CHANGELOG](packages/dart_vscode/CHANGELOG.md)
- [flutter_vscode CHANGELOG](packages/flutter_vscode/CHANGELOG.md)

## Mandatory Baseline Rules

- Project type is a pub workspace monorepo publishing two packages: `dart_vscode`, the pure-Dart typed VS Code API and extension runtime, and `flutter_vscode`, the CLI and Flutter View runtime for building VS Code extensions in Dart.
- Keep the binding pipeline, runtime modules, and platform-conditional view implementations separated.
- Use `very_good_analysis` and follow Effective Dart conventions.
- Prefer `package:web` and `dart:js_interop`; do not add `dart:js_util`.
- For generation errors, provide actionable user-facing failures.
- Keep documentation and examples aligned with API behavior.

## Extension Author Toolkit

Extension authors (not package contributors) use:

- [Agent-Assisted Development](docs/guides/agent-assisted-development.md)
- [Generated Host API](docs/reference/generated-host-api.md)
- [Extension Author AGENTS.md template](docs/templates/consumer-agents.md)
- Skills in [`skills/`](skills/) — copy into an extension project as `agent-skills/`
  when they are not already present

For full detail, follow the linked topic pages under `docs/agent-guidelines/`.
