---
status: accepted
---

# Create Dedicated Extension Projects

The canonical starting point is `flutter_vscode create <name>`, which creates a
dedicated Extension Project containing host Dart, optional Flutter Views,
shared Dart code, contributions, and framework-managed workflows. Existing
Flutter code is reused through shared packages; adopting an arbitrary existing
project is a secondary `init` or migration workflow rather than the structure
that defines the product.

Owning the project shape gives the framework deterministic builds, clean
artifacts, reliable upgrades, and enforceable runtime boundaries. It also keeps
unrelated application assets and dependencies out of the extension delivered
to Extension Users.
