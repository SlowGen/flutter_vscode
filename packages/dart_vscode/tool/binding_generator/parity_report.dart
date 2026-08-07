/// Builds the generated API parity report from the coverage ledger.
///
/// The report is a Framework-Managed Artifact: it is derived mechanically
/// from `coverage.json`, byte-compared against regeneration in tests, and
/// never edited by hand.
library;

import 'parity_layer.dart';

/// Renders the parity burn-down for one coverage ledger and pinned IR.
String buildParityReport(
  Map<String, Object?> coverage,
  Map<String, Object?> inventory,
) {
  final summary = (coverage['summary']! as Map<Object?, Object?>)
      .cast<String, Object?>();
  final entries = (coverage['entries']! as List<Object?>)
      .cast<Map<Object?, Object?>>()
      .map((entry) => entry.cast<String, Object?>())
      .toList();

  final groups = <String, _GroupCounts>{};
  for (final entry in entries) {
    final group = _groupFor(entry['id']! as String);
    final counts = groups.putIfAbsent(group, _GroupCounts.new);
    final binding = (entry['binding']! as Map<Object?, Object?>)
        .cast<String, Object?>();
    switch (binding['status']) {
      case 'emitted':
        counts.emitted += 1;
      case 'excluded':
        if (entry['visibility'] == 'public') {
          counts.reviewedExcluded += 1;
        } else {
          counts.nonPublic += 1;
        }
      default:
        counts.pending += 1;
    }
  }

  final discovered = summary['discovered'];
  final emitted = summary['bindingsEmitted'];
  final pending = summary['bindingsPending'];
  final buffer = StringBuffer()
    ..writeln('# VS Code API Parity')
    ..writeln()
    ..writeln('<!-- GENERATED FILE - DO NOT EDIT. -->')
    ..writeln('<!-- Regenerate: dart tool/binding_generator/generate.dart')
    ..writeln('     --parity . -->')
    ..writeln()
    ..writeln('Typed parity is total by construction (ADR 0012, ADR 0013):')
    ..writeln('the one generated API artifact, exported as')
    ..writeln('`package:dart_vscode/dart_vscode.dart`, maps every public')
    ..writeln('declaration of the pinned API via Total Mapping Rules — the')
    ..writeln('Parity Layer substrate and the Dart-ergonomics surface in one')
    ..writeln('file, each with its own totality ledger gated by the parity')
    ..writeln('and dart-layer suites. A capability the generator cannot map')
    ..writeln('is a defect that fails the build (the vision rule,')
    ..writeln('mechanized).')
    ..writeln()
    ..writeln('Live coverage is measured on two axes (see CONTEXT.md:')
    ..writeln('API Family, Construct Class), both machine-derived and')
    ..writeln('enforced by the parity suite and the real Extension Host')
    ..writeln('gate.')
    ..writeln();
  final families = [
    for (final declaration
        in (inventory['declarations']! as List<Object?>)
            .cast<Map<Object?, Object?>>())
      if (declaration['kind'] == 'namespace') declaration['name']! as String,
  ]..sort();
  _writeWrapped(
    buffer,
    'Family axis (derived from the pinned IR): at least one '
    'representative member of every API namespace family executes '
    'against live VS Code in the real-host parity smoke, so a new '
    'family cannot be skipped silently. The '
    '${families.length} families: '
    '${families.map((family) => '`$family`').join(', ')}.',
  );
  buffer.writeln();
  final constructClasses = [...parityConstructClasses]..sort();
  _writeWrapped(
    buffer,
    'Construct-class axis (derived from the emitter constant): every '
    'Total Mapping Rule construct class has a rule-level unit case '
    'over synthetic IR, and every class without a recorded exemption '
    'carries a `cc:`-tagged probe in the same live gate. The '
    '${constructClasses.length} classes: '
    '${constructClasses.map((name) => '`$name`').join(', ')}.',
  );
  buffer
    ..writeln()
    ..writeln('Live-exempt construct classes, each with its recorded')
    ..writeln('reason:')
    ..writeln();
  final exemptions = parityLiveExemptions.keys.toList()..sort();
  for (final name in exemptions) {
    buffer.writeln('- `$name` — ${parityLiveExemptions[name]}');
  }
  buffer
    ..writeln()
    ..writeln('The table below is the behavioral-verification burn-down: a')
    ..writeln('`pending` row is public surface whose typed binding exists')
    ..writeln('but has not yet carried real-Extension-Host evidence through')
    ..writeln('the receipted capability fixtures. Generated')
    ..writeln('from the coverage ledger, regenerated and byte-compared by')
    ..writeln('the repository gates.')
    ..writeln()
    ..writeln(
      'Pinned inventory: $discovered declarations discovered; '
      '$emitted emitted and host-verified; '
      '${summary['bindingsExcluded']} excluded '
      '(reviewed or non-public); $pending pending.',
    )
    ..writeln()
    ..writeln(
      '| Container | Emitted | Reviewed excluded | Non-public | '
      'Pending |',
    )
    ..writeln('| --- | ---: | ---: | ---: | ---: |');
  final names = groups.keys.toList()..sort();
  for (final name in names) {
    final counts = groups[name]!;
    buffer.writeln(
      '| `$name` | ${counts.emitted} | '
      '${counts.reviewedExcluded} | ${counts.nonPublic} | '
      '${counts.pending} |',
    );
  }
  buffer
    ..writeln()
    ..writeln('Behavioral evidence enters through the receipted real-host')
    ..writeln('gates and capability fixtures; a `pending` entry leaves that')
    ..writeln('state only with executable real-host evidence. A new baseline')
    ..writeln('construct with no Total Mapping Rule blocks the release')
    ..writeln('(ADR 0008 as evolved by ADR 0012).');
  return buffer.toString();
}

void _writeWrapped(StringBuffer buffer, String text) {
  const width = 72;
  var line = StringBuffer();
  for (final word in text.split(' ')) {
    if (line.isNotEmpty && line.length + 1 + word.length > width) {
      buffer.writeln(line);
      line = StringBuffer();
    }
    if (line.isNotEmpty) {
      line.write(' ');
    }
    line.write(word);
  }
  if (line.isNotEmpty) {
    buffer.writeln(line);
  }
}

String _groupFor(String entryId) {
  const marker = 'vscode.';
  final start = entryId.indexOf(marker);
  if (start < 0) {
    return 'global';
  }
  final qualified = entryId.substring(start + marker.length);
  final segmentEnd = qualified.indexOf(RegExp('[.@/]'));
  final segment = segmentEnd < 0
      ? qualified
      : qualified.substring(0, segmentEnd);
  if (segment.isEmpty) {
    return 'vscode (root)';
  }
  final first = segment[0];
  final lowercaseInitial = first.toLowerCase() == first;
  return lowercaseInitial ? 'vscode.$segment' : 'vscode (root)';
}

class _GroupCounts {
  int emitted = 0;
  int reviewedExcluded = 0;
  int nonPublic = 0;
  int pending = 0;
}
