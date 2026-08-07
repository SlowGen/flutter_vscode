import 'dart:convert';
import 'dart:io';

/// Reads [path] as a string-keyed JSON object.
///
/// The one test-side JSON reader: five suites previously carried private
/// byte-identical copies of this body.
Map<String, Object?> readJsonObject(String path) {
  return (jsonDecode(File(path).readAsStringSync()) as Map<Object?, Object?>)
      .cast<String, Object?>();
}
