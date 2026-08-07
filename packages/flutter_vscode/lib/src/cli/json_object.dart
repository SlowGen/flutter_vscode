import 'dart:convert';
import 'dart:io';

/// Reads [file] as a JSON object, failing with an actionable description.
Future<Map<String, Object?>> readJsonObject(File file) async {
  return decodeJsonObject(await file.readAsString(), file.path);
}

/// Decodes [source] as a JSON object described by [description] in errors.
Map<String, Object?> decodeJsonObject(String source, String description) {
  final decoded = jsonDecode(source);
  if (decoded is! Map<Object?, Object?>) {
    throw FormatException('$description must contain a JSON object.');
  }
  return decoded.cast<String, Object?>();
}
