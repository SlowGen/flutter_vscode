---
status: accepted
---

# Require No Author-Managed Node Toolchain

The supported Author Toolchain is Flutter/Dart, VS Code, and the
`flutter_vscode` CLI. The CLI will compile host Dart to JavaScript, generate the
host bootstrap and extension manifest, build Flutter assets, and package the
extension without asking Extension Authors to install Node, run npm, compile
TypeScript, or maintain JavaScript build configuration. VS Code's own Extension
Host may execute generated JavaScript, but that runtime is not part of the
Author Toolchain.

This makes Dart-Only Authoring a complete workflow rather than a source-language
claim. It also commits the framework to owning packaging, diagnostics, and
upgrades instead of delegating those responsibilities to an npm toolchain.
