import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:test/test.dart';

import '../tool/binding_generator/generator.dart';

part 'binding_generator/schema_admission.dart';
part 'binding_generator/override_review.dart';
part 'binding_generator/host_contract.dart';
part 'binding_generator/ir_structure.dart';
part 'binding_generator/strategy_drift.dart';
part 'binding_generator/canonical_identity.dart';
part 'binding_generator/generics.dart';
part 'binding_generator/visibility.dart';
part 'binding_generator/project_contributions.dart';
part 'binding_generator/emission_outputs.dart';
part 'binding_generator/fixtures.dart';
part 'binding_generator/mutations.dart';

void main() {
  registerSchemaAdmissionTests();
  registerOverrideReviewTests();
  registerHostContractTests();
  registerIrStructureTests();
  registerStrategyDriftTests();
  registerCanonicalIdentityTests();
  registerGenericsTests();
  registerVisibilityTests();
  registerProjectContributionsTests();
  registerEmissionOutputsTests();
}
