# flutter_vscode

Shared language for the people, projects, and product promises in the
`flutter_vscode` ecosystem.

## People

**Extension Author**:
A developer who builds and maintains a VS Code extension with `flutter_vscode`.
_Avoid_: Consumer, package user, user

**Extension User**:
A person who installs or operates an extension produced with `flutter_vscode`.
_Avoid_: End user, consumer, user

## Product

**Extension Project**:
A Dart codebase that produces an installable VS Code extension and may include
zero or more Flutter Views.
_Avoid_: Flutter app, consumer project

**Flutter View**:
A Flutter web application hosted as one user interface within an Extension
Project.
_Avoid_: Flutter app, webview

**Host-Only Extension**:
An Extension Project that provides VS Code capabilities without a Flutter View.
_Avoid_: Headless extension, non-Flutter extension

**Extension Capability**:
One part of the VS Code extension platform exposed to an Extension Author,
including APIs, contributions, events, providers, and lifecycles.
_Avoid_: Command, API call

**Dart-Only Authoring**:
The product contract that Extension Authors write and maintain only Dart and
Flutter code, even when the resulting extension contains other generated code.
_Avoid_: Dart-only artifact, TypeScript-free artifact

**Author Toolchain**:
The tools an Extension Author installs and invokes directly: Flutter/Dart, VS
Code, and the `flutter_vscode` CLI.
_Avoid_: Build internals, host runtime

**Framework-Managed Artifact**:
Build or configuration output created, validated, and upgraded by
`flutter_vscode`; Extension Authors may inspect it but do not edit it.
_Avoid_: Scaffold file, user file

**Project-Derived Artifact**:
The only generated code an Extension Project receives: files whose contents
come from that project itself, such as its extension identifier and the
collision-resistant key its JavaScript globals are named for. Framework
code is never one of these — it ships in a package and is imported.
_Avoid_: Generated code, framework code, emitted module

**API Parity Baseline**:
The pinned stable VS Code release whose public Extension Capabilities must all
have a classified Dart representation.
_Avoid_: Latest API, full API

**Generated API Layer**:
The one mechanically generated Dart artifact that Extension Authors use:
the complete typed Parity Layer substrate and the Dart-first ergonomic
surface in a single self-contained file. It ships as
`package:dart_vscode/dart_vscode.dart` and is imported, never copied into
an Extension Project (ADR 0015).
_Avoid_: Idiomatic Facade, binding layers, wrapper API, per-project copy

**Parity Layer**:
The complete, mechanically generated typed substrate of an API Parity
Baseline, carried inside the Generated API Layer rather than shipped as
a separate artifact.
_Avoid_: Raw API, low-level API, standalone parity artifact

**Framework Module**:
A hand-written, judgment-shaped Dart module the framework ships over
the Generated API Layer, in the `FlutterViewHost`/`ViewShell` mold;
the home for curated ergonomics that a total mechanical rule cannot
express.
_Avoid_: Idiomatic Facade, second generated layer, helper library

**Binding Pipeline**:
The deterministic transformation from pinned VS Code API sources into the
Generated API Layer, runtime and host-exports modules, manifest
contributions, and coverage ledger.
_Avoid_: Translation model, inference step

**Total Mapping Rule**:
A judgment-free, deterministic rule that maps one Construct Class to Dart
interop code for every occurrence in the API Parity Baseline; a construct
with no Total Mapping Rule fails generation rather than being
approximated.
_Avoid_: Heuristic, best-effort mapping, special case

**Construct Class**:
One category of TypeScript construct that a Total Mapping Rule consumes,
such as tuples, intersection types, index signatures, overload sets, rest
parameters, string-literal unions, call signatures, or anonymous object
shapes. Live coverage is measured on two axes: every API family and every
Construct Class must have an executed representative in a real Extension
Host.
_Avoid_: Rule family, shape, edge case

**API Family**:
One VS Code namespace (such as `window`, `workspace`, or `languages`)
together with the capabilities it groups; the unit of family-level live
coverage.
_Avoid_: Module, area, category

**Precision Helper**:
A generated Dart member that restores type precision over an erased interop
boundary, such as typed narrowing for unions, typed literal values, or typed
tuple access.
_Avoid_: Convenience wrapper, sugar

**Semantic Override**:
A reviewed, versioned classification that resolves an API mapping question
not derivable from the pinned upstream sources while keeping the Binding
Pipeline deterministic. The Generated API Layer uses none — it is produced
entirely by Total Mapping Rules; Semantic Overrides remain the release-gate
classification for baseline changes (ADR 0008).
_Avoid_: Manual binding, exception, guess

**Host Target**:
An Extension Host environment in which an Extension Project is built and
verified to run, such as a local or remote Node Extension Host or the Web
Extension Host.
_Avoid_: Platform, deployment target

**Stable API Contract**:
The product guarantee that every stable Extension Capability in the API Parity
Baseline has a supported Dart representation.
_Avoid_: Full API including proposals, latest API

**Experimental API Mode**:
An explicit opt-in mode for proposed VS Code APIs, pinned to a compatible
Insiders build and outside normal compatibility and Marketplace guarantees.
_Avoid_: Proposed API support, preview flag

**Shipped API Baseline**:
The single API Parity Baseline whose generated API a given `flutter_vscode`
release carries. An Extension Author chooses it by depending on that release,
never by declaring a target, and it fixes the managed extension compatibility
declaration (ADR 0014).
_Avoid_: Project API Target, apiTarget, per-project baseline, latest VS Code
