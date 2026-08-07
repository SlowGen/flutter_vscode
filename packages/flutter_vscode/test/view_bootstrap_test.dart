import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_vscode/view.dart';

void main() {
  test('VM bootstrap fails instead of falling back to a normal browser', () {
    expect(
      VSCodeViewBootstrap.acquire,
      throwsA(
        isA<UnsupportedError>().having(
          (error) => error.message,
          'message',
          contains('VS Code webview'),
        ),
      ),
    );
  });
}
