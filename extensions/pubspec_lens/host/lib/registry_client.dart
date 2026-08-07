/// The host-side registry client: `hostFetch` over the Extension
/// Host's global `fetch`, an in-memory cache, and graceful offline
/// degradation.
library;

import 'package:dart_vscode/host_runtime.dart';
import 'package:pubspec_lens_shared/registry.dart';

/// The signature of the network seam, matching the generated
/// [hostFetch] runtime helper.
typedef RegistryFetch = Future<HostFetchResponse> Function(String url);

/// Fetches pub package metadata with an in-memory cache.
///
/// The degradation contract: any failure — network error, non-2xx
/// status, unparsable body — returns null and caches nothing, so
/// callers fall back to the unknown verdict (no diagnostics churn
/// while offline) and the next refresh retries. Successes stay
/// cached until [clearCache].
final class RegistryClient {
  /// Creates a client over the [_fetch] seam; production code uses
  /// the default generated [hostFetch].
  RegistryClient({this._fetch = _hostFetch});

  final RegistryFetch _fetch;
  final RegistryCache _cache = RegistryCache();

  static Future<HostFetchResponse> _hostFetch(String url) => hostFetch(url);

  /// Returns [baseUrl]'s answer for [packageName], or null on any
  /// failure (see the class contract).
  Future<PackageInfo?> fetchPackageInfo(
    String baseUrl,
    String packageName,
  ) async {
    final cached = _cache[packageName];
    if (cached != null) {
      return cached;
    }
    try {
      final response = await _fetch(packageInfoUrl(baseUrl, packageName));
      if (!response.ok) {
        return null;
      }
      final info = parsePackageInfo(response.body);
      _cache.store(packageName, info);
      return info;
    } on Object {
      return null;
    }
  }

  /// Forgets every cached answer so the next analysis re-queries.
  void clearCache() => _cache.clear();
}
