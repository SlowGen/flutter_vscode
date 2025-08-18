#!/usr/bin/env dart

import 'dart:io';

import './init_generators/scripts/index.dart';

void main(List<String> arguments) async {
  print('Initializing Flutter VS Code extension...');

  final currentDir = Directory.current;

  // Check if this is a Flutter project
  final pubspecFile = File('${currentDir.path}/pubspec.yaml');
  if (!pubspecFile.existsSync()) {
    print('Error: No pubspec.yaml found.');
    print('Please run this script from the root of a Flutter project,');
    print('Or create one using "flutter create my_project".');
    exit(1);
  }
  try {
    setupTypescript(currentDir);
    setupWeb(currentDir);
    await setupShell(currentDir);
    updateGitignore();
    createExample(currentDir);
  } catch (e) {
    print('Failed to complete setup: $e');
    exit(1);
  }

  try {
    print('Installing dependencies...');
    await Process.run('npm', ['install']);
  } catch (e) {
    print('Failed to install dependencies: $e');
    exit(1);
  }

  print('Flutter VS Code extension scaffolding complete!');
  print('Next steps:');
  print('1. Define your VS Code controllers using ');
  print('@VSCodeController and @VSCodeCommand annotations');
  print('2. Run "npm run compile" to build everything');
  print(
    'or open VS Code and press F5 to run the extension in development mode',
  );
}
