---
status: accepted
---

# Make the Minimum VS Code Version Explicit

Every Extension Project will declare a Project API Target in Dart-owned
configuration. The Binding Pipeline will expose the stable API surface for that
target and generate the matching `engines.vscode` declaration as a
Framework-Managed Artifact.

An Extension Author must explicitly raise the Project API Target before using
a capability introduced by a newer VS Code release. Framework upgrades will
not silently raise it. This makes compatibility failures visible at development
time and prevents routine tool upgrades from unexpectedly excluding Extension
Users with older VS Code installations.

---

Amended 2026-07-25: the CLI currently falls back to the pinned default
seed when a project descriptor omits `apiTarget`
(`lib/src/cli/baselines.dart`), so the no-silent-raise guarantee rests
on projects keeping the explicit key that `create` scaffolds. Making
the key required is the recorded hardening follow-up.

## Amendment (ADR 0014)

The per-project `apiTarget` this decision relied on no longer exists. A
`flutter_vscode` release ships one pinned VS Code baseline, so the
generated `engines.vscode` minimum follows the framework release a
project depends on. The no-silent-raise guarantee stands, but it is now
carried by the dependency constraint in the project's `pubspec.yaml` and
by the framework CHANGELOG rather than by a manifest field: a baseline
move is a breaking change and is released as one. See
[ADR 0014](0014-ship-one-vscode-baseline-per-release.md).
