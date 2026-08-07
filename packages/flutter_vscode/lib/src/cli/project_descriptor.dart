import 'dart:io';

import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';

/// The one library an extension descriptor may import.
const _manifestLibrary = 'package:flutter_vscode/manifest.dart';

/// The actionable declaration every descriptor error points back to.
const _guidance =
    'Declare a single top-level '
    'const extension = ExtensionManifest(...) using the types from '
    "'$_manifestLibrary'; the CLI parses it as data and never executes "
    'project code.';

/// The literal-value rules shared by every argument position.
const _literalRules =
    'extension.dart manifest values must be constant '
    'literals; references, interpolation, function calls, and collection '
    'control flow are not supported.';

/// Reads the deliberately restricted Dart-owned extension descriptor.
///
/// The descriptor declares `const extension = ExtensionManifest(...)` using
/// the types from `package:flutter_vscode/manifest.dart`, so Extension
/// Authors get analyzer completion and type-checking — but the CLI parses
/// the constant invocation as data. Project code is never loaded or
/// executed.
///
/// This is a parse, not an admission: the returned map carries exactly the
/// arguments the author wrote, in the order they wrote them. Presence,
/// defaults, unknown-field rejection, and every platform semantic belong
/// to `ManifestProjection` in `package:dart_vscode/contributions.dart`,
/// where the JSON descriptor path is admitted by the same rules.
///
/// Every parse failure is a [CliException] with code
/// `INVALID_PROJECT_DATA`.
Future<Map<String, Object?>> readProjectDescriptor(File descriptor) async {
  final result = parseString(
    content: await descriptor.readAsString(),
    path: descriptor.path,
    throwIfDiagnostics: false,
  );
  if (result.errors.isNotEmpty) {
    throw _parseFailure(
      'extension.dart contains a Dart syntax error. $_guidance',
    );
  }
  for (final directive in result.unit.directives) {
    if (directive is! ImportDirective ||
        directive.prefix != null ||
        directive.deferredKeyword != null ||
        directive.uri.stringValue != _manifestLibrary) {
      throw _parseFailure(
        "extension.dart may import only '$_manifestLibrary'. $_guidance",
      );
    }
  }
  if (result.unit.declarations.length != 1) {
    throw _parseFailure(
      'extension.dart must contain exactly one declaration. $_guidance',
    );
  }

  final declaration = result.unit.declarations.single;
  if (declaration is! TopLevelVariableDeclaration ||
      declaration.augmentKeyword != null ||
      declaration.externalKeyword != null ||
      declaration.metadata.isNotEmpty ||
      !declaration.variables.isConst ||
      declaration.variables.metadata.isNotEmpty ||
      declaration.variables.variables.length != 1) {
    throw _parseFailure(
      'extension.dart must declare one const value named extension. '
      '$_guidance',
    );
  }
  final variable = declaration.variables.variables.single;
  final initializer = variable.initializer;
  if (variable.name.lexeme != 'extension' || initializer == null) {
    throw _parseFailure(
      'extension.dart must declare one const value named extension. '
      '$_guidance',
    );
  }
  if (initializer is SetOrMapLiteral) {
    throw _parseFailure(
      'extension.dart declares the retired map-literal descriptor. '
      '$_guidance',
    );
  }
  final manifest = _asConstInvocation(initializer);
  if (manifest == null || manifest.typeName != 'ExtensionManifest') {
    throw _parseFailure(
      'extension.dart must initialize extension with '
      'ExtensionManifest(...). $_guidance',
    );
  }
  return _readInvocation(manifest);
}

CliException _parseFailure(String message) =>
    CliException(message, code: 'INVALID_PROJECT_DATA');

/// One const type invocation read as data: the type's name plus its
/// argument list.
final class _ConstInvocation {
  const _ConstInvocation(this.typeName, this.arguments);

  final String typeName;
  final ArgumentList arguments;
}

/// Returns [expression] as a const type invocation when it invokes an
/// uppercase-initial name without a target, prefix, type arguments, or
/// named constructor.
///
/// Which type names are meaningful is an admission fact: the projection
/// rejects shapes the platform would reject, so the parse carries any
/// well-formed invocation through as the map of its named arguments.
_ConstInvocation? _asConstInvocation(Expression expression) {
  return switch (expression) {
    MethodInvocation(
      target: null,
      typeArguments: null,
      :final methodName,
      :final argumentList,
    )
        when methodName.name.startsWith(RegExp('[A-Z]')) =>
      _ConstInvocation(methodName.name, argumentList),
    InstanceCreationExpression(:final constructorName, :final argumentList)
        when constructorName.type.importPrefix == null &&
            constructorName.type.typeArguments == null &&
            constructorName.name == null =>
      _ConstInvocation(constructorName.type.name.lexeme, argumentList),
    _ => null,
  };
}

/// Reads one const invocation into the map of its named arguments, in the
/// order the author wrote them.
Map<String, Object?> _readInvocation(_ConstInvocation invocation) {
  final values = <String, Object?>{};
  for (final argument in invocation.arguments.arguments) {
    if (argument is! NamedExpression) {
      throw _parseFailure(
        '${invocation.typeName} arguments must all be named, found the '
        'positional argument $argument.',
      );
    }
    final name = argument.name.label.name;
    if (values.containsKey(name)) {
      throw _parseFailure(
        '${invocation.typeName} passes the duplicate argument "$name".',
      );
    }
    values[name] = _readValue(argument.expression);
  }
  return values;
}

Object? _readValue(Expression expression) {
  final invocation = _asConstInvocation(expression);
  if (invocation != null) {
    return _readInvocation(invocation);
  }
  return switch (expression) {
    SimpleStringLiteral() => expression.value,
    AdjacentStrings() => _readAdjacentStrings(expression),
    BooleanLiteral() => expression.value,
    IntegerLiteral() when expression.value != null => expression.value,
    DoubleLiteral() => expression.value,
    NullLiteral() => null,
    ListLiteral() => _readList(expression),
    SetOrMapLiteral() => _readMap(expression),
    _ => throw _parseFailure(_literalRules),
  };
}

Map<String, Object?> _readMap(SetOrMapLiteral literal) {
  final values = <String, Object?>{};
  for (final element in literal.elements) {
    if (element is! MapLiteralEntry) {
      throw _parseFailure(_literalRules);
    }
    final key = element.key;
    if (key is! SimpleStringLiteral) {
      throw _parseFailure(
        'extension.dart map keys must be simple string literals. '
        '$_literalRules',
      );
    }
    if (values.containsKey(key.value)) {
      throw _parseFailure(
        'extension.dart declares the duplicate map key "${key.value}".',
      );
    }
    values[key.value] = _readValue(element.value);
  }
  return values;
}

String _readAdjacentStrings(AdjacentStrings literal) {
  final parts = StringBuffer();
  for (final part in literal.strings) {
    if (part is! SimpleStringLiteral) {
      throw _parseFailure(_literalRules);
    }
    parts.write(part.value);
  }
  return parts.toString();
}

List<Object?> _readList(ListLiteral literal) {
  final values = <Object?>[];
  for (final element in literal.elements) {
    if (element is! Expression) {
      throw _parseFailure(_literalRules);
    }
    values.add(_readValue(element));
  }
  return values;
}
