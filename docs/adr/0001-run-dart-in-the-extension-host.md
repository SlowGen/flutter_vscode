---
status: accepted
---

# Run Dart in the VS Code Extension Host

VS Code must activate extensions and invoke callbacks even when no Flutter
webview exists. A pure-Dart host entrypoint will therefore compile to JavaScript
and run in-process inside the VS Code Extension Host, while Flutter remains a
separate Dart runtime in the webview. A generated bootstrap will load the host
bundle, direct JS interop will expose VS Code inside host Dart, and the versioned
protocol will be reserved for communication that actually crosses runtimes.

This preserves Dart-Only Authoring without forcing live VS Code objects through
a webview protocol. Keeping all Dart in the webview cannot satisfy activation
and provider lifecycles; a Dart sidecar would retain the rich-RPC problem while
adding native packaging, process management, remote-host, and web-host costs.
