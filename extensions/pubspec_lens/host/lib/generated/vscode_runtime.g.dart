// GENERATED CODE - DO NOT MODIFY BY HAND.
// ignore_for_file: unnecessary_lambdas

import 'dart:js_interop';

import 'package:dart_vscode/host_runtime.dart';

@JS(
  '__flutterVscode.stackMappers.e_4fbd019c52aca486a55d74b06046d2dcf4344febda968c7d233827373f6214a7',
)
external JSString _mapHostStack(JSString stack);

@JS(
  '__flutterVscode.callbackWrappers.e_4fbd019c52aca486a55d74b06046d2dcf4344febda968c7d233827373f6214a7',
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
