/// The one VS Code baseline this `dart_vscode` release ships.
///
/// The package version *is* the baseline: the generated API layer, the
/// contribution semantics, and the manifest `engines.vscode` pin all move
/// together when the maintainer imports newer pinned inputs, regenerates,
/// and publishes. An extension that needs an older VS Code API depends on
/// the `dart_vscode` release that shipped it — ordinary package versioning
/// rather than a selector inside the package.
const vscodeApiVersion = '1.129.1';
