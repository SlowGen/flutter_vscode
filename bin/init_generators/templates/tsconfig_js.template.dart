const String tsconfigTemplate = '''
{
  "compilerOptions": {
    "module": "commonjs",
    "target": "ES2020",
    "outDir": "out",
    "lib": [
      "ES2020",
      "dom"
    ],
    "sourceMap": true,
    "rootDir": "src",
    "strict": true,
    "moduleResolution": "node",
    "types": ["node"]
  }
}
''';
