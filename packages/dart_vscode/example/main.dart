// A minimal VS Code extension host module written against dart_vscode.
//
// In a real Extension Project, `flutter_vscode build` generates the
// identity wiring (`host_exports.g.dart`) that publishes this lifecycle
// object to the Extension Host bootstrap; the author owns only what is
// shown here.

import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart' as vs;
import 'package:dart_vscode/host_commands.dart';
import 'package:dart_vscode/host_runtime.dart';

/// The Dart lifecycle object the generated bootstrap activates.
@JSExport()
class Extension {
  /// Called by VS Code when the extension activates.
  JSPromise<JSAny?> activate(JSObject rawContext, JSObject rawVscode) {
    final context = vs.ExtensionContext(rawContext);
    final api = vs.VscodeApi(rawVscode).dart;

    ExtensionCommands(context: context, api: api).register(
      'example.hello',
      (_) async => 'Hello from Dart'.toJS,
    );

    return toHostPromise(Future<JSAny?>.value());
  }

  /// Called by VS Code when the extension deactivates.
  JSPromise<JSAny?> deactivate() => toHostPromise(Future<JSAny?>.value());
}
