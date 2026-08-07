/// A deterministic contribution-processing failure with a stable
/// machine-readable [code].
final class ContributionException implements Exception {
  /// Creates a contribution-processing failure.
  const ContributionException(this.code, this.message);

  /// Stable diagnostic code.
  final String code;

  /// Actionable diagnostic text.
  final String message;

  @override
  String toString() => '$code: $message';
}
