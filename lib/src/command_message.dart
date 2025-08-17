import 'dart:js_interop';
import 'dart:js_interop_unsafe';

class CommandMessage {
  CommandMessage({
    required this.command,
    required this.params,
    required this.requestId,
    this.error,
    this.result,
  });

  factory CommandMessage.fromJsObject(JSObject jsObject) {
    try {
      final command = jsObject['command'].isDefinedAndNotNull
          ? (jsObject['command']! as JSString).toDart
          : '';
      final params = jsObject['params'].isDefinedAndNotNull
          ? (jsObject['params']! as JSArray).toDart
          : <dynamic>[];
      final requestId = jsObject['requestId'].isDefinedAndNotNull
          ? (jsObject['requestId']! as JSString).toDart
          : '';

      return CommandMessage(
        command: command,
        params: params,
        requestId: requestId,
      );
    } catch (e) {
      print('inside CommandMessage factory');
    }
    throw Error();
  }

  final String command;
  final List<dynamic> params;
  final String? requestId;
  final String? error;
  final dynamic result;
}

extension JSCommandMessage on CommandMessage {
  JSObject toJsCommandMessage() {
    final jsObject = JSObject();
    jsObject.setProperty('command'.toJS, command.toJS);
    jsObject.setProperty('params'.toJS, params.toJSArray);
    jsObject.setProperty('requestId'.toJS, requestId?.toJS);
    return jsObject;
  }
}

extension ListDynamicToArray on List<dynamic> {
  JSArray get toJSArray {
    final jsArray = JSArray();
    for (final item in this) {
      if (item is String) {
        jsArray.add(item.toJS);
      } else if (item is int) {
        jsArray.add(item.toJS);
      } else if (item is double) {
        jsArray.add(item.toJS);
      } else if (item is bool) {
        jsArray.add(item.toJS);
      } else if (item is List<dynamic>) {
        jsArray.add(item.toJSArray);
      } else if (item is Map<String, dynamic>) {
        jsArray.add(item.toJSObject);
      } else {
        jsArray.add(null);
      }
    }
    return jsArray;
  }
}

extension MapStringDynamicToObject on Map<String, dynamic> {
  JSObject get toJSObject {
    final jsObject = JSObject();
    for (final entry in entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is String) {
        jsObject.setProperty(key.toJS, value.toJS);
      } else if (value is int) {
        jsObject.setProperty(key.toJS, value.toJS);
      } else if (value is double) {
        jsObject.setProperty(key.toJS, value.toJS);
      } else if (value is bool) {
        jsObject.setProperty(key.toJS, value.toJS);
      } else if (value is List<dynamic>) {
        jsObject.setProperty(key.toJS, value.toJSArray);
      } else if (value is Map<String, dynamic>) {
        jsObject.setProperty(key.toJS, value.toJSObject);
      } else {
        jsObject.setProperty(key.toJS, null);
      }
    }
    return jsObject;
  }
}
