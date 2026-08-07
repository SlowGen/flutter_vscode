---
status: accepted
---

# Guarantee Stable APIs Only

The Stable API Contract will cover every stable Extension Capability in the
API Parity Baseline. Proposed VS Code APIs will not appear in the normal Parity
Layer or Idiomatic Facade and will not be required for 1.0.

The framework may later expose proposed APIs through an Experimental API Mode.
That mode must be explicitly enabled, pin its generated bindings to a compatible
VS Code Insiders build, and make clear that the resulting extension is outside
the normal compatibility and Marketplace publication guarantees. This keeps
ordinary Extension Projects publishable and reliable for Extension Users while
leaving a controlled path for experimentation.
