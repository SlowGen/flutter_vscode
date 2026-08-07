---
status: accepted
---

# Expose Runtime Boundaries in the Project Layout

Every Extension Project will visibly separate pure host Dart, optional Flutter
Views, and shared Dart packages. The CLI will operate on the project as one
unit, but source location and dependency rules will make it clear which runtime
executes each entrypoint.

This adds directories to the starter project but prevents Flutter and browser
dependencies from leaking into the Extension Host, makes lifecycle behavior
predictable, and gives diagnostics and debugging an unambiguous runtime context.
