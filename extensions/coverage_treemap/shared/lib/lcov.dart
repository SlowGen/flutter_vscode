/// A pure-Dart lcov tracefile parser shared by Host Dart and the
/// treemap Flutter View.
library;

/// Line coverage for one instrumented source file.
final class LcovFile {
  LcovFile._(this.path, Map<int, int> lineHits, int? linesFound, int? linesHit)
    : lineHits = Map.unmodifiable(lineHits),
      linesFound = linesFound ?? lineHits.length,
      linesHit = linesHit ?? lineHits.values.where((hits) => hits > 0).length;

  /// Source path exactly as recorded by the `SF:` record.
  final String path;

  /// Execution counts per one-based source line from `DA:` records.
  final Map<int, int> lineHits;

  /// Instrumented line count (`LF:`, or derived from `DA:` records).
  final int linesFound;

  /// Executed line count (`LH:`, or derived from `DA:` records).
  final int linesHit;

  /// Covered fraction in [0, 1]; a file with no instrumented lines is 0.
  double get coverage => linesFound == 0 ? 0 : linesHit / linesFound;

  /// The final path segment.
  String get name => path.split('/').last;
}

/// One directory level of the aggregated coverage tree.
final class LcovDirectory {
  LcovDirectory._(this.name, this.directories, this.files);

  /// Directory name; the root's name is the empty string.
  final String name;

  /// Child directories, sorted by name.
  final List<LcovDirectory> directories;

  /// Files directly in this directory, sorted by name.
  final List<LcovFile> files;

  /// Instrumented lines in this subtree.
  int get linesFound =>
      files.fold(0, (sum, file) => sum + file.linesFound) +
      directories.fold(0, (sum, dir) => sum + dir.linesFound);

  /// Executed lines in this subtree.
  int get linesHit =>
      files.fold(0, (sum, file) => sum + file.linesHit) +
      directories.fold(0, (sum, dir) => sum + dir.linesHit);

  /// Covered fraction in [0, 1] for this subtree.
  double get coverage => linesFound == 0 ? 0 : linesHit / linesFound;
}

/// A parsed lcov tracefile.
final class LcovReport {
  LcovReport._(List<LcovFile> files) : files = List.unmodifiable(files);

  /// All file sections in record order.
  final List<LcovFile> files;

  /// Instrumented lines across the report.
  int get linesFound => files.fold(0, (sum, file) => sum + file.linesFound);

  /// Executed lines across the report.
  int get linesHit => files.fold(0, (sum, file) => sum + file.linesHit);

  /// Covered fraction in [0, 1]; an empty report is 0.
  double get coverage => linesFound == 0 ? 0 : linesHit / linesFound;

  /// The files grouped into a directory tree with rolled-up coverage.
  LcovDirectory get tree {
    final root = _MutableDirectory('');
    for (final file in files) {
      final segments = file.path.split('/');
      var node = root;
      for (final segment in segments.sublist(0, segments.length - 1)) {
        node = node.directories.putIfAbsent(
          segment,
          () => _MutableDirectory(segment),
        );
      }
      node.files.add(file);
    }
    return root.freeze();
  }
}

final class _MutableDirectory {
  _MutableDirectory(this.name);

  final String name;
  final Map<String, _MutableDirectory> directories = {};
  final List<LcovFile> files = [];

  LcovDirectory freeze() {
    final children = directories.values.map((dir) => dir.freeze()).toList()
      ..sort((left, right) => left.name.compareTo(right.name));
    final sortedFiles = [...files]
      ..sort((left, right) => left.name.compareTo(right.name));
    return LcovDirectory._(
      name,
      List.unmodifiable(children),
      List.unmodifiable(sortedFiles),
    );
  }
}

/// Parses lcov tracefile [content] into a structured report.
///
/// Consumes `SF`, `DA`, `LF`, `LH`, and `end_of_record`; every other
/// record kind is ignored. Malformed input fails with a
/// [FormatException] naming the offending line.
LcovReport parseLcov(String content) {
  final files = <LcovFile>[];
  String? path;
  Map<int, int>? lineHits;
  int? linesFound;
  int? linesHit;
  var lineNumber = 0;

  Never fail(String message) =>
      throw FormatException('lcov line $lineNumber: $message');

  for (final rawLine in content.split('\n')) {
    lineNumber += 1;
    final line = rawLine.trim();
    if (line.isEmpty) {
      continue;
    }
    if (line == 'end_of_record') {
      if (path == null) {
        fail('end_of_record outside a file section.');
      }
      files.add(LcovFile._(path, lineHits!, linesFound, linesHit));
      path = null;
      lineHits = null;
      linesFound = null;
      linesHit = null;
      continue;
    }
    final separator = line.indexOf(':');
    final kind = separator < 0 ? line : line.substring(0, separator);
    final payload = separator < 0 ? '' : line.substring(separator + 1);
    switch (kind) {
      case 'SF':
        if (path != null) {
          fail("SF before the previous section's end_of_record.");
        }
        if (payload.isEmpty) {
          fail('SF record has no path.');
        }
        path = payload;
        lineHits = {};
      case 'DA':
        if (path == null) {
          fail('DA record outside a file section.');
        }
        final parts = payload.split(',');
        final lineIndex = parts.isNotEmpty ? int.tryParse(parts[0]) : null;
        final hits = parts.length > 1 ? int.tryParse(parts[1]) : null;
        if (lineIndex == null || hits == null) {
          fail('malformed record "DA:$payload".');
        }
        lineHits![lineIndex] = hits;
      case 'LF':
        if (path == null) {
          fail('LF record outside a file section.');
        }
        linesFound =
            int.tryParse(payload) ?? fail('malformed record "LF:$payload".');
      case 'LH':
        if (path == null) {
          fail('LH record outside a file section.');
        }
        linesHit =
            int.tryParse(payload) ?? fail('malformed record "LH:$payload".');
      default:
        // Other lcov record kinds (TN, FN*, BR*) are not consumed.
        break;
    }
  }
  if (path != null) {
    lineNumber += 1;
    fail('file section "$path" has no end_of_record.');
  }
  return LcovReport._(files);
}
