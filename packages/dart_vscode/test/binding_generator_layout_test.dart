/// Structural pin for the binding-pipeline layout: the IR
/// validation/canonicalization projection, the coverage ledger, the
/// pinned-projection byte-compares, and the maintainer leaf validators
/// live in sibling modules under `tool/binding_generator/`, leaving
/// `generator.dart` the entangled walking-slice orchestration band; the
/// author-data admission mirrors live in `lib/src/contributions/` where
/// the published package owns them. The behavior pins are the existing
/// byte-compare suites; this suite pins only the promised layout.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import 'package:test/test.dart';

/// Expected top-level declarations per sibling module, matched textually
/// against the module source so an absent file or a jailed declaration
/// fails with the missing name.
const _expectedModuleDeclarations = <String, List<String>>{
  'tool/binding_generator/ir_validator.dart': [
    'void validateInputSchemaVersion(',
    'void validateIrModule(',
    'Map<String, Object?> validateIrSource(',
    'void validateIrDeclarationKeys(',
    'void validateIrDeclarationOrder(',
    'void validateIrDeclarationIdentity(',
    'List<List<String?>> irInheritedTypeParameterScopes(',
    'void validateIrDeclarationTypes(',
    'void validateIrOverloadOrdinals(',
    'void validateIrTypeLiteralGraph(',
    'void validateIrExactKeys(',
    'String computeDeclarationFingerprint(',
    'Object? _canonicalizeIrType(',
  ],
  'tool/binding_generator/coverage_ledger.dart': [
    'String emitCoverageLedger(',
  ],
  'tool/binding_generator/manifest_projection.dart': [
    'String validateManifestSchema(',
    'String validateManifestValidator(',
    'String validateCommandsContributionSchema(',
    'String validateViewsContributionSchemas(',
    'String validateConfigurationContributionSchema(',
  ],
  // The author-data admission mirrors live in the published contributions
  // library so the flutter_vscode CLI can admit descriptors without any
  // maintainer tooling; the IR-side byte-compares above cross-check them.
  'lib/src/contributions/projections.dart': [
    'List<Map<String, Object?>> projectCommands(',
    'Map<String, Object?> projectViewsContainers(',
    'Map<String, Object?> projectViews(',
    'Map<String, Object?> projectConfiguration(',
    'void validateProjectDescriptor(',
    'bool isStrictSemanticVersion(',
  ],
  'lib/src/contributions/manifest_projection.dart': [
    'final class ManifestProjection {',
  ],
  'lib/src/contributions/ecmascript_whitespace.dart': [
    'bool isEcmaScriptFalsyOrWhitespace(',
    'bool isEcmaScriptTrimWhitespaceCodePoint(',
  ],
  'lib/src/contributions/json_values.dart': [
    'List<Object?> objectList(',
    'Map<String, Object?> objectMap(',
    'String string(',
    'String nonEmptyString(',
    'String extensionIdentifierComponent(',
    'String nonWhitespaceString(',
  ],
  'tool/binding_generator/validators.dart': [
    'String sha256Digest(',
    'int integerOrDefault(',
  ],
};

void main() {
  for (final entry in _expectedModuleDeclarations.entries) {
    test('${entry.key} exists and owns its promised declarations', () {
      final file = File(entry.key);
      expect(
        file.existsSync(),
        isTrue,
        reason: '${entry.key} must exist where the layout promises it.',
      );
      // A module may be several files: the entry plus the parts it declares.
      // Ownership is about which module holds a declaration, not which file.
      final source = _moduleSource(file);
      for (final declaration in entry.value) {
        expect(
          source,
          contains(declaration),
          reason:
              '${entry.key} must declare `$declaration...` at the '
              'top level.',
        );
      }
    });
  }

  test('validators.dart is maintainer scalars, not a pass-through', () {
    // After the contributions split this module briefly re-exported the
    // shared JSON coercion helpers; every tool module now imports
    // `json_values.dart` (and the whitespace lowering) directly, so the
    // deletion test holds: removing the re-exports makes nothing reappear.
    final source = File(
      'tool/binding_generator/validators.dart',
    ).readAsStringSync();
    expect(
      RegExp('^export ', multiLine: true).hasMatch(source),
      isFalse,
      reason: 'validators.dart must not re-export the contributions helpers',
    );
    expect(
      source,
      isNot(contains('int integer(')),
      reason: 'integer() was dead code kept alive by this suite',
    );
  });

  test('generator.dart keeps only the entangled walking-slice band', () {
    final lineCount = File(
      'tool/binding_generator/generator.dart',
    ).readAsLinesSync().length;
    expect(
      lineCount,
      lessThan(2500),
      reason:
          'generator.dart must shrink to the orchestration plus '
          'walking-slice band once the projections, ledger, validators, '
          'and templates move to sibling modules.',
    );
  });
}

/// The full source of a module: its entry file and every part it declares.
String _moduleSource(File entry) {
  final source = entry.readAsStringSync();
  final parts = RegExp(
    "^part '([^']+)';",
    multiLine: true,
  ).allMatches(source).map((match) => match.group(1)!);
  return [
    source,
    for (final part in parts)
      File(p.join(entry.parent.path, part)).readAsStringSync(),
  ].join('\n');
}
