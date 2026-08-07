/// The coverage ledger projection: the deterministic
/// `coverage.json` accounting of every discovered declaration
/// through the discovery, semantics, binding, and host stages.
library;

import 'dart:convert';

import 'package:dart_vscode/src/contributions/json_values.dart';

import 'validators.dart';

/// Emits the deterministic coverage ledger, `coverage.json`.
String emitCoverageLedger({
  required String inventoryVersion,
  required String inputSha256,
  required String manifestSchemaSha256,
  required String manifestValidatorSha256,
  required String commandsContributionSchemaSha256,
  required String viewsContributionSchemaSha256,
  required String configurationContributionSchemaSha256,
  required Map<String, Map<String, Object?>> declarationsById,
  required Map<String, Object?> entries,
  required Map<String, String> strategiesById,
  required Map<String, Map<String, Object?>> hostContracts,
  required Map<String, String> hostContractsById,
}) {
  var semanticsReviewed = 0;
  var semanticsExcluded = 0;
  var bindingsEmitted = 0;
  var bindingsExcluded = 0;
  var hostVerified = 0;
  var hostNotApplicable = 0;
  var sourceOccurrences = 0;
  var publicLogicalEntries = 0;
  var reviewedExcludedTargets = 0;
  final ledgerEntries = <Map<String, Object?>>[];
  final ids = declarationsById.keys.toList()..sort();

  for (final id in ids) {
    final declaration = declarationsById[id]!;
    final occurrenceCount = integerOrDefault(
      declaration['occurrenceCount'],
      defaultValue: 1,
      path: 'inventory declaration $id.occurrenceCount',
    );
    sourceOccurrences += occurrenceCount;
    final strategy = strategiesById[id];
    final visibility = string(
      declaration['visibility'] ?? 'public',
      'inventory declaration $id.visibility',
    );
    final excludedByVisibility = visibility != 'public';
    final excludedByOverride = strategy == 'reviewedExcluded';
    if (!excludedByVisibility) {
      publicLogicalEntries += 1;
    }
    if (excludedByOverride) {
      reviewedExcludedTargets += 1;
    }

    final semantics = excludedByVisibility || excludedByOverride
        ? 'excluded'
        : strategy == null
        ? 'pending'
        : 'reviewed';
    final binding = excludedByVisibility || excludedByOverride
        ? 'excluded'
        : strategy == null
        ? 'pending'
        : 'emitted';
    final host = excludedByVisibility || excludedByOverride
        ? 'notApplicable'
        : strategy == null
        ? 'pending'
        : 'verified';

    if (semantics == 'reviewed') {
      semanticsReviewed += 1;
    } else if (semantics == 'excluded') {
      semanticsExcluded += 1;
    }
    if (binding == 'emitted') {
      bindingsEmitted += 1;
    } else if (binding == 'excluded') {
      bindingsExcluded += 1;
    }
    if (host == 'verified') {
      hostVerified += 1;
    } else if (host == 'notApplicable') {
      hostNotApplicable += 1;
    }

    final exclusionReason = excludedByOverride
        ? string(
            objectMap(entries[id], 'overrides.entries.$id')['reason'],
            'overrides.entries.$id.reason',
          )
        : null;
    ledgerEntries.add({
      'id': id,
      'kind': string(declaration['kind'], 'inventory declaration $id.kind'),
      'visibility': visibility,
      'occurrenceCount': occurrenceCount,
      'selected': strategy != null,
      'discovery': <String, Object?>{'status': 'discovered'},
      'semantics': <String, Object?>{
        'status': semantics,
        if (excludedByVisibility) 'basis': 'visibility',
        if (strategy != null && !excludedByVisibility)
          'basis': 'semanticOverride',
        if (strategy != null && !excludedByVisibility) 'strategy': strategy,
        'reason': ?exclusionReason,
      },
      'binding': <String, Object?>{
        'status': binding,
        if (binding == 'emitted')
          'artifacts': <String>[
            'packages/dart_vscode/lib/src/generated/vscode_dart_layer.g.dart',
          ],
      },
      'host': <String, Object?>{
        'status': host,
        if (host == 'verified') 'contract': hostContractsById[id],
      },
    });
  }

  final discovered = declarationsById.length;
  final semanticsPending = discovered - semanticsReviewed - semanticsExcluded;
  final bindingsPending = discovered - bindingsEmitted - bindingsExcluded;
  final hostPending = discovered - hostVerified - hostNotApplicable;
  final implementedTargets = semanticsReviewed;
  final ledger = <String, Object?>{
    'schemaVersion': 1,
    'source': <String, Object?>{
      'vscodeVersion': inventoryVersion,
      'inputSha256': inputSha256,
      'manifestSchemaSha256': manifestSchemaSha256,
      'manifestValidatorSha256': manifestValidatorSha256,
      'commandsContributionSchemaSha256': commandsContributionSchemaSha256,
      'viewsContributionSchemaSha256': viewsContributionSchemaSha256,
      'configurationContributionSchemaSha256':
          configurationContributionSchemaSha256,
    },
    'hostContracts': hostContracts,
    'hostEvidence': <String, Object?>{
      'kind': 'mechanicalAttribution',
      'meaning':
          '$hostVerified reviewed binding IDs cite one real Extension '
          'Host Contract whose receipted gate passed its surrounding native '
          'behavior; the retired per-member observation mechanism no longer '
          'contributes evidence.',
      'independentBehavioralContracts': false,
    },
    'scope': <String, Object?>{
      'name': 'checkpoint4FlutterViewSlice',
      'fullApiParity':
          semanticsPending == 0 && bindingsPending == 0 && hostPending == 0,
      'selectedTargets': strategiesById.length,
      'implementedTargets': implementedTargets,
      'reviewedExcludedTargets': reviewedExcludedTargets,
    },
    'inventory': <String, Object?>{
      'logicalEntries': discovered,
      'sourceOccurrences': sourceOccurrences,
      'publicLogicalEntries': publicLogicalEntries,
      'nonPublicLogicalEntries': discovered - publicLogicalEntries,
    },
    'exclusions': <String, Object?>{
      'reviewedSemanticOverrides': reviewedExcludedTargets,
      'nonPublicVisibility': discovered - publicLogicalEntries,
    },
    'summary': <String, Object?>{
      'discovered': discovered,
      'semanticsReviewed': semanticsReviewed,
      'semanticsExcluded': semanticsExcluded,
      'semanticsPending': semanticsPending,
      'bindingsEmitted': bindingsEmitted,
      'bindingsExcluded': bindingsExcluded,
      'bindingsPending': bindingsPending,
      'hostVerified': hostVerified,
      'hostNotApplicable': hostNotApplicable,
      'hostPending': hostPending,
    },
    'entries': ledgerEntries,
  };
  const encoder = JsonEncoder.withIndent('  ');
  return '${encoder.convert(ledger)}\n';
}
