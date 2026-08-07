# Generated Host API

New Extension Projects use direct generated Dart bindings inside VS Code's
Extension Host. One generated artifact carries the whole API surface:
`package:dart_vscode/dart_vscode.dart` (exported from the package as
`package:dart_vscode/dart_vscode.dart`) maps every public declaration of
the pinned VS Code API (ADR 0012, Total Mapping Rules) and layers Dart-first
ergonomics over that substrate in the same file. There is no separate parity
artifact and no hand-reviewed facade; the artifact is total by construction
(ADR 0013).

Start in `host/lib/extension.dart`. The scaffold demonstrates the supported
lifecycle shape: `activate` receives the native extension context and VS Code
module, wraps them with the generated extension types, and places
registrations in `context.subscriptions` synchronously — providers register
before `activate`'s future is returned, so lazy activation cannot race a
first query:

```dart
import 'dart:js_interop';

import 'package:dart_vscode/dart_vscode.dart';
import 'package:my_extension_host/generated/host_exports.g.dart';
import 'package:my_extension_host/generated/vscode_runtime.g.dart';

@JSExport()
class _Extension {
  JSPromise<JSAny?> activate(JSObject rawContext, JSObject rawVscode) {
    final context = ExtensionContext(rawContext);
    final vscode = VscodeApi(rawVscode);

    final hello = (() => 'Hello from Dart'.toJS).toJS;
    context.subscriptions.toDart.add(
      JSAnon_ffa2e03c40a2(
        vscode.commands.registerCommand(
          'my-extension.hello',
          toHostCallback(hello),
        ),
      ),
    );
    return Future<JSAny?>.value(null).toJS;
  }

  JSPromise<JSAny?> deactivate() => Future<JSAny?>.value(null).toJS;
}

void main() => registerHostExports(createJSInteropWrapper(_Extension()));
```

Every identifier above is generated into the project: `ExtensionContext`,
`VscodeApi`, and the `JSAnon_*` stable typedef for anonymous shapes come from
`vscode_dart_layer.g.dart`; `toHostCallback` comes from the runtime module;
`registerHostExports` from the host-exports module.

## Commands as ordinary Dart

For command registration, `package:dart_vscode/host_commands.dart` erases
the interop ceremony above. `ExtensionCommands` holds the context/api seam
once; each `register` call takes a command name and an ordinary-Dart
handler — dartified `List<Object?>` arguments in, a protocol-safe value
(`null`, `bool`, `num`, `String`, or a `List`/`Map` of those, or a `Future`
of one) out. The module owns argument dartification, result conversion,
`toHostCallback`/`toHostPromise` stack mapping, and the
`context.subscriptions` push, and returns the native registration for
callers that dispose early:

```dart
final commands = ExtensionCommands(
  context: context,
  api: vscode.dart,
);
commands.register('my-extension.hello', (arguments) async => 'Hello');
```

## One artifact, two surfaces

`VscodeApi(rawVscode)` wraps the raw activation module with the substrate
surface: typed extension types over native JS objects, produced entirely by
Total Mapping Rules. Conventions: classes construct through module-rooted
`new$` (statics live on the same `XCtor` object); enums are `int` typedefs
with values on `api.<EnumName>`; interfaces and anonymous shapes are created
with `lit$` object-literal factories; JS `undefined` and `null` both surface
as Dart `null`; unions erase to their least upper bound with typed
`isInstance`/`cast` narrowing helpers.

```dart
final api = VscodeApi(rawVscode);
final uri = api.Uri.file('/tmp/notes.md');
final position = api.Position.new$(0.toJS, 0.toJS);
final registration = api.languages.registerHoverProvider(
  DocumentFilter.lit$(language: 'markdown'.toJS),
  HoverProvider.lit$(provideHover: toHostCallback(myProvider)),
);
```

`VscodeApi(rawVscode).dart` enters the Dart-ergonomics surface of the same
artifact: helper boundaries take ordinary `String`/`num`/`bool`, `JSPromise`
returns become `Future`s, `Event` members gain broadcast `Stream` accessors
(`onDidX` gains `onDidXStream`), and `lit$` factories flatten inherited
interface members. Every `XDart` type wraps and implements its substrate
type `X`, so ergonomic values flow anywhere the substrate surface is
expected, and the raw escape hatches stay one step away: `$js` on any
`XDart` value returns its substrate wrapper, and the substrate types wrap
plain `JSObject`s.

## Runtime, host exports, and framework modules

Two generated modules beside the API artifact are runtime plumbing, not API
layers:

- `vscode_runtime.g.dart` — `toHostPromise` (Dart `Future` to a host
  `JSPromise` with mapped Dart stacks on rejection), `toHostCallback`
  (wraps a callback so thrown Dart errors surface `extension.dart` frames),
  and `hostFetch` (the supported Host Dart network path over the Extension
  Host's WHATWG `fetch`).
- `host_exports.g.dart` — `registerHostExports`, publishing the lifecycle
  object under the extension's collision-resistant namespace for the
  framework-owned bootstrap.

Judgment-shaped helpers live in hand-written framework modules, not in the
generated artifact: view-bearing projects receive `flutter_view_host.g.dart`
with `FlutterViewHost.open` (panel creation, CSP-correct HTML, session
wiring, disposal), and the view side composes `ViewShell` from
`package:flutter_vscode/view.dart`.

## Coverage accounting

The [parity report](parity.md) carries the exact pinned accounting. Each host-attributed entry cites the repository's durable
Host Contract artifact. For this slice, one real Extension Host Contract
mechanically attributes 53 reviewed binding IDs after its native behavior
checks pass; it does not mean the package has 53 independent behavioral
contracts. The artifact keeps the exact IDs and hashes of the executable
repository test sources. If a capability's mapping cannot be derived from
the pinned upstream sources, extend the framework's pinned inputs and
reviewed Semantic Overrides (the ADR 0008 classification gate). Do not add
`dynamic`, handwritten interop, or an inferred binding to an Extension
Project. Live coverage is measured on two axes — API Family and Construct
Class — in the generated [parity report](parity.md).
