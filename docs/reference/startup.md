# Flutter View Startup

Flutter-web weight is the first objection evaluators raise against
Flutter Views. This page answers it with a measured number instead of
an argument.

## What is measured

The real-host gates measure **webview load to first rendered frame**:
the wall-clock from the instant Host Dart assigns the webview's HTML
(`viewColdStartMs` starts) to the instant the host's render observer
confirms the Flutter View painted its expected content inside the real
webview. That span covers the CSP document parse, `flutter_bootstrap`
and `main.dart.js` load, engine initialization with local CanvasKit,
first frame, and the DOM render observation itself.

Every run of `scripts/test_host_extension.sh` and
`scripts/test_packaged_extension.sh` asserts the measurement is
present and sane (`0 < viewColdStartMs < 60000`) and prints it:

```text
[host-test] Flutter View cold start (webview load to first rendered frame): NNNms
```

The gate output is the authority; the numbers below are recorded
values from specific runs, in the repository's recording-time
convention.

## Recorded values

Recorded 2026-07-24, pinned VS Code 1.129.1, Linux/xvfb in Docker on
an Apple-silicon host:

- Extension Development flow (`test_host_extension.sh`): **284ms**
- Installed VSIX flow (`test_packaged_extension.sh`): **315ms**

The fixture view is a small Flutter app built with the CLI's
webview-safe flags (`--csp`, `--no-web-resources-cdn`,
`--pwa-strategy none`) and local CanvasKit; cold start on developer
hardware outside a container is typically faster. Numbers grow with
app size — measure your own extension by watching the same log line
in the gates, or instrument your host the same way the fixture does.

## Deferred evaluations

Wasm (`skwasm`) builds and deferred loading are candidates if the
number regresses on real extensions; they are tracked in the
developer-experience plan (D-6) rather than adopted speculatively
while cold start stays in the low hundreds of milliseconds.
