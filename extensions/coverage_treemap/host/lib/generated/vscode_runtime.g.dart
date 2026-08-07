// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: unnecessary_lambdas

import 'dart:js_interop';

import 'package:dart_vscode/host_runtime.dart';

@JS(
  '__flutterVscode.stackMappers.e_fd2880b059dc6684df43c2921c1e75f9b7b263154503300a7223562915d8051f',
)
external JSString _mapHostStack(JSString stack);

@JS(
  '__flutterVscode.callbackWrappers.e_fd2880b059dc6684df43c2921c1e75f9b7b263154503300a7223562915d8051f',
)
external JSFunction _wrapHostCallback(JSFunction callback);

/// Binds this extension's JavaScript globals into the framework runtime.
///
/// Only the two globals are per-extension; the code that uses them lives in
/// `package:dart_vscode/host_runtime.dart`.
void installGeneratedHostRuntime() => installHostRuntime(
  mapStack: (stack) => _mapHostStack(stack.toJS),
  wrapCallback: (callback) => _wrapHostCallback(callback),
);
