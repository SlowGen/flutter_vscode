/// Pure-Dart analysis of `pubspec.yaml` source text.
///
/// [parsePubspec] reads `dependencies` and `dev_dependencies` into
/// [PubspecDependency] models carrying zero-based source spans (for
/// diagnostics, hovers, CodeLens placement, and text edits) and
/// constraints parsed with `pub_semver`. [verdictFor] compares one
/// dependency against the registry's latest version. Only hosted
/// dependencies get registry verdicts; sdk, path, and git dependencies
/// are skipped by design.
library;

import 'package:pub_semver/pub_semver.dart';
import 'package:yaml/yaml.dart';

/// Where a dependency's code comes from.
enum DependencySource {
  /// A pub registry package (`name: ^1.2.3`, `name:`, or a `hosted:`
  /// map with a `version:`).
  hosted,

  /// An SDK dependency (`sdk: flutter`).
  sdk,

  /// A local path dependency.
  path,

  /// A git dependency (URL shorthand or map form).
  git,

  /// Any other shape this first cut does not classify.
  unknown,
}

/// A zero-based source extent, aligned with VS Code positions.
final class SpanLocation {
  /// Creates an extent from zero-based line/column bounds.
  const SpanLocation({
    required this.startLine,
    required this.startColumn,
    required this.endLine,
    required this.endColumn,
  });

  /// Zero-based first line.
  final int startLine;

  /// Zero-based first column.
  final int startColumn;

  /// Zero-based line just past the extent's last character.
  final int endLine;

  /// Zero-based column just past the extent's last character.
  final int endColumn;
}

/// One entry of `dependencies` or `dev_dependencies`.
final class PubspecDependency {
  /// Creates a parsed dependency entry.
  const PubspecDependency({
    required this.name,
    required this.isDev,
    required this.source,
    required this.nameSpan,
    this.constraintText,
    this.constraint,
    this.constraintSpan,
  });

  /// The package name as written.
  final String name;

  /// Whether the entry sits under `dev_dependencies`.
  final bool isDev;

  /// The dependency's source classification.
  final DependencySource source;

  /// The extent of the package name key.
  final SpanLocation nameSpan;

  /// The constraint exactly as written, or null for a bare `name:`
  /// entry or a non-scalar shape.
  final String? constraintText;

  /// The parsed constraint; [VersionConstraint.any] for a bare entry,
  /// null when [constraintText] does not parse.
  final VersionConstraint? constraint;

  /// The extent of the written constraint scalar, replaceable by a
  /// text edit; null when nothing was written.
  final SpanLocation? constraintSpan;

  /// Whether this dependency resolves against a pub registry.
  bool get isHosted => source == DependencySource.hosted;
}

/// The outcome of comparing one dependency against the registry.
enum VerdictKind {
  /// Nothing to suggest: the constraint's lower bound already sits at
  /// or above the latest version.
  current,

  /// The constraint admits the latest version, but its lower bound
  /// trails it — advice, not a blocker.
  behind,

  /// The latest version falls outside the written constraint, so
  /// nothing will resolve to it until the constraint moves.
  outdated,

  /// No registry answer, or the constraint does not parse.
  unknown,

  /// Not a hosted dependency; never compared.
  skipped,
}

/// A per-dependency verdict with the data behind it.
final class Verdict {
  const Verdict._(this.kind, this.latest, this.suggestedConstraint);

  /// What the comparison concluded.
  final VerdictKind kind;

  /// The registry's latest version, when one was available.
  final Version? latest;

  /// The `^latest` constraint to write when [kind] is
  /// [VerdictKind.behind] or [VerdictKind.outdated]; null otherwise.
  final String? suggestedConstraint;
}

/// Compares [dependency] against the registry's [latest] version.
///
/// Non-hosted dependencies are [VerdictKind.skipped]; a null [latest]
/// (offline, unknown package) or an unparsable constraint is
/// [VerdictKind.unknown].
///
/// Otherwise the comparison point is the constraint's lower bound, not
/// merely whether the latest version is admitted: a bound at or above
/// [latest] is [VerdictKind.current] with nothing to suggest, and a
/// trailing bound carries a `^latest` suggestion — [VerdictKind.behind]
/// when the constraint still admits the latest version,
/// [VerdictKind.outdated] when it excludes it.
///
/// Reading the bound rather than testing admission is what keeps a pin
/// *ahead* of the registry (a lagging mirror, a prerelease pin) from
/// being "fixed" by a rewrite that walks it backwards.
Verdict verdictFor(PubspecDependency dependency, Version? latest) {
  if (!dependency.isHosted) {
    return const Verdict._(VerdictKind.skipped, null, null);
  }
  final constraint = dependency.constraint;
  if (latest == null || constraint == null) {
    return Verdict._(VerdictKind.unknown, latest, null);
  }
  final lowerBound = _lowerBoundOf(constraint);
  if (lowerBound != null && lowerBound >= latest) {
    return Verdict._(VerdictKind.current, latest, null);
  }
  final kind = constraint.allows(latest)
      ? VerdictKind.behind
      : VerdictKind.outdated;
  return Verdict._(kind, latest, '^$latest');
}

/// The lowest version [constraint] could resolve to, or null when it
/// has no lower bound (`any`, a bare `name:` entry, or a shape this
/// first cut does not decompose).
Version? _lowerBoundOf(VersionConstraint constraint) => switch (constraint) {
  // Version implements VersionRange with `min` returning itself, so
  // exact pins land here too.
  VersionRange(:final min) => min,
  // The union's ranges are sorted, so the first carries the lowest
  // bound.
  VersionUnion(:final ranges) => ranges.firstOrNull?.min,
  _ => null,
};

/// Parses [source] as `pubspec.yaml` and returns its direct
/// dependencies in declaration order (`dependencies` first, then
/// `dev_dependencies`).
///
/// Throws an actionable [FormatException] when the document is not
/// valid YAML, when its root is not a map, or when a dependency
/// section is not a map of package names.
List<PubspecDependency> parsePubspec(String source) {
  YamlNode root;
  try {
    root = loadYamlNode(source, sourceUrl: Uri.parse('pubspec.yaml'));
  } on YamlException catch (error) {
    final span = error.span;
    final position = span == null
        ? ''
        : ' at line ${span.start.line + 1}, column ${span.start.column + 1}';
    throw FormatException(
      'pubspec.yaml is not valid YAML$position: ${error.message}. '
      'Fix the syntax and analyze again.',
    );
  }
  if (root is YamlScalar && root.value == null) {
    return const [];
  }
  if (root is! YamlMap) {
    throw const FormatException(
      'pubspec.yaml must be a YAML map at its root, like '
      '"name: my_package" followed by a dependencies section.',
    );
  }
  return [
    ..._readSection(root, 'dependencies', isDev: false),
    ..._readSection(root, 'dev_dependencies', isDev: true),
  ];
}

List<PubspecDependency> _readSection(
  YamlMap root,
  String section, {
  required bool isDev,
}) {
  final node = root.nodes.entries
      .where((entry) => (entry.key as YamlNode?)?.value == section)
      .map((entry) => entry.value)
      .firstOrNull;
  if (node == null || (node is YamlScalar && node.value == null)) {
    return const [];
  }
  if (node is! YamlMap) {
    throw FormatException(
      'pubspec.yaml "$section" must be a map of package names to '
      'constraints, found ${node.value.runtimeType} at '
      'line ${node.span.start.line + 1}.',
    );
  }
  final dependencies = <PubspecDependency>[];
  for (final entry in node.nodes.entries) {
    final key = entry.key as YamlNode;
    dependencies.add(
      _readDependency(
        name: '${key.value}',
        nameSpan: _location(key),
        value: entry.value,
        isDev: isDev,
      ),
    );
  }
  return dependencies;
}

PubspecDependency _readDependency({
  required String name,
  required SpanLocation nameSpan,
  required YamlNode value,
  required bool isDev,
}) {
  if (value is YamlScalar) {
    if (value.value == null) {
      // A bare `name:` entry means any version from the registry.
      return PubspecDependency(
        name: name,
        isDev: isDev,
        source: DependencySource.hosted,
        nameSpan: nameSpan,
        constraint: VersionConstraint.any,
      );
    }
    return _hostedDependency(
      name: name,
      isDev: isDev,
      nameSpan: nameSpan,
      constraintNode: value,
    );
  }
  if (value is YamlMap) {
    final keys = {
      for (final key in value.nodes.keys) '${(key as YamlNode).value}',
    };
    if (keys.contains('sdk')) {
      return _unhostedDependency(name, isDev, nameSpan, DependencySource.sdk);
    }
    if (keys.contains('path')) {
      return _unhostedDependency(name, isDev, nameSpan, DependencySource.path);
    }
    if (keys.contains('git')) {
      return _unhostedDependency(name, isDev, nameSpan, DependencySource.git);
    }
    final version = value.nodes.entries
        .where((entry) => (entry.key as YamlNode?)?.value == 'version')
        .map((entry) => entry.value)
        .firstOrNull;
    if (version is YamlScalar && version.value != null) {
      return _hostedDependency(
        name: name,
        isDev: isDev,
        nameSpan: nameSpan,
        constraintNode: version,
      );
    }
  }
  return _unhostedDependency(name, isDev, nameSpan, DependencySource.unknown);
}

PubspecDependency _hostedDependency({
  required String name,
  required bool isDev,
  required SpanLocation nameSpan,
  required YamlScalar constraintNode,
}) {
  final text = '${constraintNode.value}';
  VersionConstraint? constraint;
  try {
    constraint = VersionConstraint.parse(text);
  } on FormatException {
    // An unparsable constraint (an in-progress edit, a typo) stays a
    // hosted dependency with an unknown verdict rather than an error.
    constraint = null;
  }
  return PubspecDependency(
    name: name,
    isDev: isDev,
    source: DependencySource.hosted,
    nameSpan: nameSpan,
    constraintText: text,
    constraint: constraint,
    constraintSpan: _location(constraintNode),
  );
}

PubspecDependency _unhostedDependency(
  String name,
  bool isDev,
  SpanLocation nameSpan,
  DependencySource source,
) {
  return PubspecDependency(
    name: name,
    isDev: isDev,
    source: source,
    nameSpan: nameSpan,
  );
}

SpanLocation _location(YamlNode node) {
  final span = node.span;
  return SpanLocation(
    startLine: span.start.line,
    startColumn: span.start.column,
    endLine: span.end.line,
    endColumn: span.end.column,
  );
}
