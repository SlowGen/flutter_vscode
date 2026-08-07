# ADR 0014: Ship one VS Code baseline per release

Status: Accepted

## Context

The package pinned several VS Code baselines at once (1.129.1 and
1.130.0), and every Extension Project declared an `apiTarget` selecting
among them. `flutter_vscode build` then generated the complete API layer
for that target and wrote a 718 KB copy into the project's
`host/lib/generated/`.

Two costs followed. The repository carried a full set of pinned inputs
per baseline — an imported IR, the official `vscode.d.ts` and schema
sources, and a Semantic Override file — which is several megabytes per
baseline for a selector no shipped project used: all three in-tree
projects pinned 1.129.1, and 1.130.0 existed only for its own tests and
docs. And `apiTarget` threaded through eight CLI modules, the manifest
type, the project descriptor, the build receipt, packaging, and doctor.

The mechanism was also redundant. Pub already versions packages. A
selector inside a package that chooses among several bundled API
versions reimplements dependency resolution one level down.

## Decision

A `flutter_vscode` release ships exactly one pinned VS Code baseline,
named by `shippedApiTarget` in `lib/src/cli/baselines.dart`. Projects do
not select a baseline and `ExtensionManifest` has no `apiTarget` field.
An author who needs a different VS Code API depends on the
`flutter_vscode` release that ships it.

Because every project now builds against the same baseline, the API
layer is no longer copied into each project. It ships once as
`package:flutter_vscode/vscode_dart.dart`, and generated host modules
import it from there. Projects keep the generated files genuinely
derived from their own commands and views — `host_commands.g.dart`,
`vscode_runtime.g.dart`, `host_exports.g.dart`, and the view protocol.

## Consequences

The tracked tree drops by about 5.8 MB, and every Extension Project is
718 KB smaller with one fewer generated file its author does not own.
The `apiTarget` plumbing leaves eight modules.

The generated `engines.vscode` minimum now moves when a project upgrades
`flutter_vscode`. This amends ADR 0011, which made the minimum explicit
per project so a framework upgrade could never raise it silently: the
raise is still never silent, but it is now recorded in the project's
`pubspec.yaml` dependency constraint and the framework CHANGELOG rather
than in a manifest field. Moving the baseline is a breaking change for
consumers and is released as one.

It also amends ADR 0005, which exposed runtime boundaries in the project
layout: an Extension Project no longer holds an inspectable copy of the
API layer. The boundary is still visible — the host package declares
`flutter_vscode` as a dependency and imports the layer by package URI.

ADR 0008 blocks a release on unclassified API symbols by comparing an
incoming baseline against the previous one. With one baseline in the
tree, the upgrade round must keep the outgoing baseline's pinned inputs
in place while the delta is classified and remove them in the commit
that ships the new one. `docs/guides/new-baseline.md` records this.

---

Amended 2026-08-06: the baseline constant and the pipeline that moves
it now live in `package:dart_vscode`, per ADR 0016. The pin is
`vscodeApiVersion` in
`packages/dart_vscode/lib/src/contributions/vscode_api_version.dart`;
the API layer ships as `package:dart_vscode/dart_vscode.dart`; and the
project-derived files a build emits shrank to `vscode_runtime.g.dart`,
`host_exports.g.dart`, `host/bootstrap.cjs`, and `package.json`. The
decision itself — one pinned baseline per release, moved by ordinary
package versioning — stands unchanged.
