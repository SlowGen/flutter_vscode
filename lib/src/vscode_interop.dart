import 'dart:async';
import 'dart:js_interop';

import 'package:flutter_vscode/src/command_message.dart';
import 'package:web/web.dart';

// this is supplied by vscode in order to securely access their api
@JS()
external VSCodeApi? acquireVsCodeApi();

extension type VSCodeApi(JSObject _) implements JSObject {
  external void postMessage(JSObject message);
}

class WebviewMessageHandler {
  WebviewMessageHandler() {
    try {
      _vscodeApi = acquireVsCodeApi();
      // Defer the message listener setup to ensure window is initialized
      Future.microtask(_setupMessageListener);
    } catch (e) {
      print('missing vscode: $e');
    }
  }
  late final VSCodeApi? _vscodeApi;
  void Function(CommandMessage)? _onMessage;

  void messageHandler(MessageEvent event) {
    try {
      final data = event.data;
      if (data.isDefinedAndNotNull) {
        try {
          final message = CommandMessage.fromJsObject(data! as JSObject);
          _onMessage?.call(message);
        } on Exception catch (e) {
          // unexpected message coming through
          print('Error parsing message: $e');
        }
      }
    } on Exception catch (e) {
      print('receive message failed: $e');
    }
  }

  void _setupMessageListener() {
    print('setup listener method');
    try {
      // Only attempt to add event listener if window is available
      if (window.isDefinedAndNotNull) {
        window.addEventListener('message', messageHandler.toJS);
        print('listener method setup');
      } else {
        print('window is not available yet');
      }
    } catch (e) {
      print('Error setting up message listener: $e');
    }
  }

  // This is a callback, not a property, so a method is more appropriate.
  // ignore: use_setters_to_change_properties
  void setMessageHandler(void Function(CommandMessage) handler) {
    _onMessage = handler;
  }

  void dispose() {
    try {
      if (window.isDefinedAndNotNull) {
        window.removeEventListener('message', messageHandler.toJS);
      }
    } catch (e) {
      print('Error removing event listener: $e');
    }
  }

  void postMessage(CommandMessage message) {
    final api = _vscodeApi;
    final vscodeApi = api;
    if (vscodeApi case null) {
      print('VSCode API is not available, cannot send message');
      return;
    }

    print('sending message: $message');

    try {
      final jsMessage = message.toJsCommandMessage();

      if (jsMessage.isDefinedAndNotNull) {
        vscodeApi.postMessage(jsMessage);
      }
    } catch (e) {
      print('Error sending message: $e');
    }
  }
}
