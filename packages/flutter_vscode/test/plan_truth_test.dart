import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../dart_vscode/tool/binding_generator/contract.dart'
    as contract_writer;

import 'support/repository.dart';

/// The archived plan's frozen bytes. Changing the archive requires
/// consciously updating this pin in the same commit with a reason.
const archivedPlanSha256 =
    '5145a0510e31237bade67b22dce3ec7c9ee3b435f1eff822665b08ba47be0ad8';

/// The plan may cite a 64-hex digest only if a machine can vouch for it:
/// either it matches current tree state or its context says it is history.
///
/// This ratchet exists because all four hardening rounds rotted the same
/// way — digests recorded as prose while the tree moved on.
void main() {
  final planPath = repoPath('specs/plans/archive/first-working-extension.md');
  final planLines = File(planPath).readAsLinesSync();
  final plan = planLines.join('\n');

  test('the archived plan is frozen history', () {
    expect(
      sha256.convert(File(planPath).readAsBytesSync()).toString(),
      archivedPlanSha256,
      reason:
          'The archive is a frozen historical record; edits to it are '
          'forbidden by design. If a change is genuinely intended, update '
          'archivedPlanSha256 in the same commit and say why.',
    );
  });

  test('every full digest in the plan is current or marked historical', () {
    const contractArtifact = '../../${contract_writer.contractArtifactPath}';
    final currentDigests = <String>{
      for (final artifact in [
        contractArtifact,
        '../dart_vscode/tool/bindings/ir/vscode-1.129.1.json',
      ])
        sha256.convert(File(artifact).readAsBytesSync()).toString(),
      for (final machineSource in [
        '../dart_vscode/tool/bindings/overrides/vscode-1.129.1.json',
        '../dart_vscode/tool/bindings/inputs/vscode/1.129.1/pins.json',
        '../dart_vscode/tool/bindings/coverage-ledger.json',
      ])
        ...RegExp('[0-9a-f]{64}')
            .allMatches(File(machineSource).readAsStringSync())
            .map((match) => match.group(0)!),
    };
    const historicalMarkers = [
      'historical',
      'superseded',
      'recording time',
      'closure time',
    ];

    final violations = <String>[];
    for (var index = 0; index < planLines.length; index += 1) {
      for (final match in RegExp('[0-9a-f]{64}').allMatches(planLines[index])) {
        final digest = match.group(0)!;
        if (currentDigests.contains(digest)) {
          continue;
        }
        final contextStart = index - 3 < 0 ? 0 : index - 3;
        final contextEnd = index + 4 > planLines.length
            ? planLines.length
            : index + 4;
        final context = planLines
            .sublist(contextStart, contextEnd)
            .join('\n')
            .toLowerCase();
        if (historicalMarkers.any(context.contains)) {
          continue;
        }
        violations.add('line ${index + 1}: $digest');
      }
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Each digest must match current tree state or sit within three '
          'lines of a historical marker '
          '(${historicalMarkers.join(', ')}). Stale digests: $violations',
    );
  });

  test('the plan does not contradict its own exit state', () {
    expect(
      plan,
      isNot(contains('exit item remains open')),
      reason: 'A closed exit item may not also be described as open.',
    );
    expect(
      plan,
      isNot(contains('every red and green landed as its own commit')),
      reason:
          'The chronology header may claim only what git corroborates: '
          'per-item commits exist for ledger entries 1, 5, and 6, while '
          'entries 2, 3, and 4 used uncommitted discrimination mutations.',
    );
  });

  test('active plans do not claim completion over unchecked items', () {
    final planFiles = Directory(
      repoPath('specs/plans'),
    ).listSync().whereType<File>().where((file) => file.path.endsWith('.md'));
    for (final file in planFiles) {
      final text = file.readAsStringSync();
      final status = text
          .split('\n')
          .firstWhere((line) => line.startsWith('Status:'), orElse: () => '');
      if (status.contains('Implemented and verified')) {
        expect(
          text,
          isNot(contains('- [ ]')),
          reason: '${file.path} claims completion with unchecked items',
        );
      }
      if (text.contains('- [x]') && status.contains('In progress')) {
        final unchecked = '- [ ]'.allMatches(text).isNotEmpty;
        expect(
          unchecked,
          isTrue,
          reason:
              '${file.path} says In progress but every item is checked '
              '— update the status line',
        );
      }
    }
  });

  test('a completion status requires a fully checked plan', () {
    final status = planLines.firstWhere(
      (line) => line.startsWith('Status:'),
      orElse: () => '',
    );
    if (status.contains('Implemented and verified')) {
      expect(
        plan,
        isNot(contains('- [ ]')),
        reason:
            'The status line may not claim completion while any '
            'checklist item anywhere in the plan is unchecked.',
      );
    }
  });
}
