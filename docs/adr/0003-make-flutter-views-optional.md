---
status: accepted
---

# Make Flutter Views Optional

An Extension Project may contain zero or more Flutter Views. Host-Only
Extensions use the same Dart-authored VS Code platform without shipping Flutter
web assets, while Extension Authors can add Flutter Views when rich custom UI
justifies them. The CLI and package boundaries must therefore keep the host
runtime pure Dart and make Flutter integration an opt-in capability.

This avoids imposing webview size, startup work, and memory use on Extension
Users of commands, language tooling, debuggers, and other host-native features.
It also allows one extension to use multiple purpose-specific Flutter Views
without treating any single view as the extension itself.
