/// Contribution semantics of the pinned VS Code baseline.
///
/// Validates Extension Project descriptors with the exact admission
/// semantics of the pinned platform and projects them into `package.json`
/// manifest form. Tooling such as the `flutter_vscode` CLI builds on this
/// library; extension authors normally never call it directly.
library;

export 'src/contributions/exception.dart' show ContributionException;
export 'src/contributions/manifest_projection.dart' show ManifestProjection;
export 'src/contributions/vscode_api_version.dart' show vscodeApiVersion;
