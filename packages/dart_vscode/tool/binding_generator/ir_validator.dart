/// The IR validation and canonicalization projection: every
/// structural, identity, type, and canonical-signature rule the
/// generator enforces against the pinned v1 inventory before any
/// emission happens.
library;

import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_vscode/src/contributions/json_values.dart';

import 'generator.dart';

part 'ir_validator/module.dart';
part 'ir_validator/ordering.dart';
part 'ir_validator/types.dart';
part 'ir_validator/shapes.dart';
part 'ir_validator/canonical.dart';
part 'ir_validator/values.dart';
