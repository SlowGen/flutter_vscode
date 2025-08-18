const String compileShTemplate = '''
#!/bin/bash
dart run build_runner build --delete-conflicting-outputs
if [ -f web/index.html.temp ]; then
  mv web/index.html.temp web/index.html
fi
flutter build web --no-web-resources-cdn --csp --pwa-strategy none --no-tree-shake-icons
''';
