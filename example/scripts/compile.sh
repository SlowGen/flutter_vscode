#!/bin/bash

# Generate Dart code using build_runner
dart run build_runner build --delete-conflicting-outputs

# Compile TypeScript
tsc -p ./

# Build Flutter web
flutter build web --no-web-resources-cdn --csp --pwa-strategy none --no-tree-shake-icons

