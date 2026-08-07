# `flutter_vscode` Vision

## Vision

`flutter_vscode` will be the shortest trustworthy path from a Flutter idea to a
real-world VS Code extension. Extension authors build the UI, behavior,
contributions, and VS Code integrations in Dart and Flutter. The package owns
the platform boundary: host bindings, code generation, messaging, webview-safe
assets, scaffolding, builds, testing, and packaging.

100% Dart and Flutter authoring is a non-negotiable product boundary. Every
public VS Code capability needed to build a real extension—including native
lifecycles, events, providers, and rich values—must be reachable through the
tools and libraries in this repository. If it is not, that is a framework bug
to fix, not a reason to require user-authored TypeScript. Any JavaScript or
TypeScript required by the VS Code host is generated implementation detail.

## Who It Serves

The primary users are Flutter and Dart teams building complete editor products:
dashboards, inspectors, wizards, data viewers, language tooling, debuggers, and
companion extensions. They should not need expertise in TypeScript, Node,
webview security, or VS Code's JavaScript object model to ship reliable tools.

## Product Promise

- **Dart and Flutter end to end:** consumer-owned extension code is written in
  Dart and Flutter; host-side JavaScript or TypeScript is generated and managed.
- **Complete VS Code reach:** the public extension API, contribution points,
  callbacks, events, providers, and host lifecycles have typed Dart access.
- **One generated layer of integration:** a single mechanically generated
  artifact covers every public capability immediately, carrying both the typed
  substrate and the Dart-first ergonomic surface; judgment-shaped helpers grow
  as hand-written framework modules beside it, never as a second generated
  facade (ADR 0013).
- **A known-good path:** one scaffold, build, debug, test, package, and upgrade
  workflow works from a clean Flutter project through a released extension.
- **Agent-ready by design:** portable guidance helps coding agents translate
  intent into correct Dart APIs and verify the resulting extension behavior.

## Architecture Direction

Host Dart talks to VS Code through generated `dart:js_interop` bindings so
native objects keep their identity, prototypes, callbacks, and lifecycles. All
cross-runtime communication between Host Dart and a Flutter View shares one
versioned protocol supporting requests, responses, errors, cancellation, and
disposal. Generated bootstrap and transport code remain framework-owned
implementation details rather than consumer authoring surfaces.

Rich VS Code values and lifecycles receive explicit Dart models, codecs,
proxies, and ownership rules. Generator, Dart runtime, transport, generated host
runtime, platform bridge, and scaffold remain separate and independently
testable. Documentation, examples, templates, and agent skills are shipped
product surfaces and must agree with executable behavior.

## Scope and Boundaries

The scope is the full public VS Code extension platform required by real-world
extensions: commands and contributions, windows and workspaces, filesystems,
trees, terminals, tasks, authentication, language and debug APIs, events,
providers, and Flutter-powered webviews.

The project is not a generic web-app wrapper, backend platform, opinionated UI
kit, or automatic migration tool for existing extensions. The framework may
generate and maintain host-side JavaScript or TypeScript, but extension authors
must not need to write or repair it.

## Success Looks Like

- A Flutter developer can scaffold, build, launch, and ship a production
  extension without writing TypeScript or repairing generated host glue.
- API parity is total by construction — a public capability the generator
  cannot map fails the build; behavioral verification and Idiomatic Facade
  coverage are tracked as measured burn-downs against supported VS Code
  releases.
- The Parity Layer and the Idiomatic Facade behave consistently across calls,
  events, callbacks, providers, rich values, errors, cancellation, and
  disposal.
- Tests prove the real chain: scaffold, generation, host compilation, Flutter
  web build, artifact validation, and Extension Host round-trips.
- Real extensions demonstrate that the framework's secure defaults, diagnostics,
  contracts, documentation, and upgrade path hold outside toy examples.
