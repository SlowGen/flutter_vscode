/// Deterministic Dart binding generation from a pinned VS Code API inventory.
library;

import 'package:dart_vscode/src/contributions/ecmascript_whitespace.dart';
import 'package:dart_vscode/src/contributions/exception.dart';
import 'package:dart_vscode/src/contributions/json_values.dart';

import 'coverage_ledger.dart';
import 'ir_validator.dart';
import 'manifest_projection.dart';
import 'validators.dart';

export 'ir_validator.dart' show computeDeclarationFingerprint;

part 'generator/core.dart';
part 'generator/slice_validation.dart';
part 'generator/strategy_matching.dart';
part 'generator/type_predicates.dart';
part 'generator/override_review.dart';
