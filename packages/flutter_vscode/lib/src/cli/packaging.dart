import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:dart_vscode/contributions.dart';
import 'package:flutter_vscode/src/cli/baselines.dart';
import 'package:flutter_vscode/src/cli/build_inputs.dart';
import 'package:flutter_vscode/src/cli/build_receipt.dart';
import 'package:flutter_vscode/src/cli/cli_exception.dart';
import 'package:flutter_vscode/src/cli/json_object.dart';
import 'package:flutter_vscode/src/cli/project_descriptor.dart';
import 'package:flutter_vscode/src/cli/project_layout.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// Assembles the Extension Project at [root] into an installable VSIX.
Future<void> packageProject(Directory root) async {
  validateProjectLayout(root);
  final dartDescriptor = File(p.join(root.path, 'extension.dart'));
  final jsonDescriptor = File(p.join(root.path, 'extension.json'));
  if (!dartDescriptor.existsSync() && !jsonDescriptor.existsSync()) {
    throw const CliException(
      'Run package from an Extension Project containing extension.dart.',
      code: 'PACKAGE_NOT_EXTENSION_PROJECT',
      exitCode: 64,
    );
  }
  // Parsing the descriptor still validates it; packaging reads no field
  // from it now that the baseline comes from the framework release.
  if (dartDescriptor.existsSync()) {
    await readProjectDescriptor(dartDescriptor);
  } else {
    await readJsonObject(jsonDescriptor);
  }
  final views = discoverViews(root);
  validateFlutterViewLayout(root, views);
  final packagedViewFiles = viewOutputFiles(root, views);
  final packageRoot = await resolvePackageRoot();
  final frameworkDigest = await frameworkSha256(packageRoot);
  final receiptProblems = await validateBuildReceipt(
    projectRoot: root,
    apiTarget: vscodeApiVersion,
    frameworkSha256: frameworkDigest,
    inputPaths: buildInputPaths(root, views),
    artifactPaths: managedArtifactPaths(root),
  );
  if (receiptProblems.isNotEmpty) {
    throw CliException(
      'Framework-Managed Artifacts are stale or malformed:\n'
      '${receiptProblems.map((problem) => '- $problem').join('\n')}\n'
      'Run flutter_vscode build before packaging.',
      code: 'STALE_BUILD_ARTIFACTS',
    );
  }
  final manifestFile = File(p.join(root.path, 'package.json'));
  final artifacts = <String, File>{
    'extension/package.json': manifestFile,
    'extension/out/bootstrap.cjs': File(
      p.join(root.path, 'out', 'bootstrap.cjs'),
    ),
    'extension/out/extension.dart.js': File(
      p.join(root.path, 'out', 'extension.dart.js'),
    ),
    'extension/out/extension.dart.js.map': File(
      p.join(root.path, 'out', 'extension.dart.js.map'),
    ),
    for (final file in packagedViewFiles)
      'extension/${relativeProjectPath(root, file)}': file,
  };
  final missing = [
    for (final entry in artifacts.entries)
      if (!entry.value.existsSync()) entry.key,
  ];
  if (missing.isNotEmpty) {
    throw CliException(
      'Build artifacts are missing (${missing.join(', ')}). '
      'Run flutter_vscode build first.',
      code: 'MISSING_BUILD_ARTIFACTS',
    );
  }

  final manifest = await readJsonObject(manifestFile);
  final name = _manifestIdentifierComponent(manifest, 'name');
  final version = _manifestString(manifest, 'version');
  final publisher = _manifestIdentifierComponent(manifest, 'publisher');
  final displayName = _manifestXmlText(manifest, 'displayName');
  final description = _manifestXmlText(manifest, 'description');
  final buildRoot = p.normalize(p.absolute(p.join(root.path, 'build')));
  final outputPath = p.normalize(p.join(buildRoot, '$name-$version.vsix'));
  if (!p.isWithin(buildRoot, outputPath)) {
    throw CliException(
      'Normalized VSIX output $outputPath escapes the managed build '
      'directory $buildRoot. Use a safe extension name and semantic version, '
      'then run flutter_vscode build again.',
      code: 'UNSAFE_PACKAGE_OUTPUT',
    );
  }
  validateRealProjectPaths(
    root,
    [
      p
          .relative(outputPath, from: p.absolute(root.path))
          .split(p.separator)
          .join('/'),
    ],
    allowFinalFile: true,
  );
  final engines = manifest['engines'];
  if (engines is! Map<Object?, Object?> || engines['vscode'] is! String) {
    throw const CliException(
      'Generated package.json has no engines.vscode value.',
      code: 'INVALID_MANAGED_MANIFEST',
    );
  }
  final vscodeVersion = engines['vscode']! as String;
  final contentTypes = contentTypesForParts([
    'extension.vsixmanifest',
    ...artifacts.keys,
  ]);
  final vsixManifest =
      '''
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011">
  <Metadata>
    <Identity Language="en-US" Id="${_xml(name)}" Version="${_xml(version)}" Publisher="${_xml(publisher)}" />
    <DisplayName>${_xml(displayName)}</DisplayName>
    <Description xml:space="preserve">${_xml(description)}</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="${_xml(vscodeVersion)}" />
      <Property Id="Microsoft.VisualStudio.Services.Content.Pricing" Value="Free" />
    </Properties>
    <Categories>Other</Categories>
  </Metadata>
  <Installation>
    <InstallationTarget Id="Microsoft.VisualStudio.Code" />
  </Installation>
  <Dependencies />
  <Assets>
    <Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true" />
  </Assets>
</PackageManifest>
'''
          .trimLeft();

  final contents = <String, List<int>>{
    '[Content_Types].xml': utf8.encode(contentTypes),
    'extension.vsixmanifest': utf8.encode(vsixManifest),
    for (final entry in artifacts.entries)
      entry.key: await entry.value.readAsBytes(),
  };
  final archive = Archive();
  for (final path in contents.keys.toList()..sort()) {
    final bytes = contents[path]!;
    final file = ArchiveFile.noCompress(path, bytes.length, bytes)
      ..mode = 0x1a4;
    archive.addFile(file);
  }
  final bytes = ZipEncoder().encode(
    archive,
    modified: DateTime.utc(1980),
  );
  validateAssembledVsix(bytes, contents);
  final output = File(outputPath);
  await output.parent.create(recursive: true);
  await output.writeAsBytes(bytes, flush: true);
  stdout.writeln('Packaged ${output.path}');
}

/// Projects the OPC `[Content_Types].xml` part for [partPaths].
String contentTypesForParts(List<String> partPaths) {
  final defaults = <String, String>{
    'vsixmanifest': 'text/xml',
    'json': 'application/json',
    'cjs': 'application/javascript',
    'js': 'application/javascript',
    'map': 'application/json',
  };
  final extraDefaults = <String, String>{};
  final overrides = <String, String>{};
  for (final path in partPaths.toSet().toList()..sort()) {
    final extension = p.posix
        .extension(path)
        .replaceFirst('.', '')
        .toLowerCase();
    if (extension.isEmpty) {
      final basename = p.posix.basename(path);
      overrides[_opcPartName(
        path,
      )] = basename == 'NOTICES' || basename == '.last_build_id'
          ? 'text/plain'
          : 'application/octet-stream';
      continue;
    }
    if (!defaults.containsKey(extension)) {
      extraDefaults[extension] = _contentTypeForExtension(extension);
    }
  }

  final output = StringBuffer()
    ..writeln('<?xml version="1.0" encoding="utf-8"?>')
    ..writeln(
      '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">',
    );
  for (final entry in defaults.entries) {
    output.writeln(
      '  <Default Extension="${_xml(entry.key)}" '
      'ContentType="${_xml(entry.value)}" />',
    );
  }
  for (final extension in extraDefaults.keys.toList()..sort()) {
    output.writeln(
      '  <Default Extension="${_xml(extension)}" '
      'ContentType="${_xml(extraDefaults[extension]!)}" />',
    );
  }
  for (final partName in overrides.keys.toList()..sort()) {
    output.writeln(
      '  <Override PartName="${_xml(partName)}" '
      'ContentType="${_xml(overrides[partName]!)}" />',
    );
  }
  output.writeln('</Types>');
  return output.toString();
}

String _contentTypeForExtension(String extension) => switch (extension) {
  'bin' || 'data' || 'frag' || 'symbols' => 'application/octet-stream',
  'css' => 'text/css',
  'gif' => 'image/gif',
  'gz' => 'application/gzip',
  'htm' || 'html' => 'text/html',
  'ico' => 'image/x-icon',
  'jpeg' || 'jpg' => 'image/jpeg',
  'mjs' => 'application/javascript',
  'otf' => 'font/otf',
  'png' => 'image/png',
  'svg' => 'image/svg+xml',
  'ttf' => 'font/ttf',
  'txt' || 'md' => 'text/plain',
  'wasm' => 'application/wasm',
  'webmanifest' => 'application/manifest+json',
  'webp' => 'image/webp',
  'woff' => 'font/woff',
  'woff2' => 'font/woff2',
  'xml' => 'application/xml',
  _ => 'application/octet-stream',
};

String _opcPartName(String path) =>
    '/${p.posix.split(path).map(Uri.encodeComponent).join('/')}';

/// Verifies [bytes] decode to exactly [expectedContents]: stored entries
/// only, exact bytes and permissions, and well-formed XML 1.0 manifests.
void validateAssembledVsix(
  List<int> bytes,
  Map<String, List<int>> expectedContents,
) {
  late final Archive decoded;
  try {
    decoded = ZipDecoder().decodeBytes(bytes, verify: true);
  } on ArchiveException catch (error) {
    throw CliException(
      'Assembled VSIX is not a valid ZIP archive: $error',
      code: 'INVALID_VSIX',
    );
  }
  final expectedPaths = expectedContents.keys.toList()..sort();
  final actualPaths = decoded.map((entry) => entry.name).toList();
  if (!_listsEqual(actualPaths, expectedPaths)) {
    throw CliException(
      'Assembled VSIX has unexpected entries: ${actualPaths.join(', ')}.',
      code: 'INVALID_VSIX',
    );
  }
  for (final entry in decoded) {
    final expected = expectedContents[entry.name]!;
    final actual = entry.readBytes();
    if (!entry.isFile ||
        entry.isSymbolicLink ||
        entry.compression != CompressionType.none ||
        entry.unixPermissions != 0x1a4 ||
        actual == null ||
        !_listsEqual(actual, expected)) {
      throw CliException(
        'Assembled VSIX entry ${entry.name} failed exact validation.',
        code: 'INVALID_VSIX',
      );
    }
  }
  for (final path in const ['[Content_Types].xml', 'extension.vsixmanifest']) {
    late final String source;
    try {
      source = utf8.decode(expectedContents[path]!);
    } on FormatException {
      throw CliException(
        'Assembled VSIX entry $path is not valid UTF-8 XML.',
        code: 'INVALID_VSIX',
      );
    }
    if (!containsOnlyXml10Characters(source)) {
      throw CliException(
        'Assembled VSIX entry $path contains a character forbidden by '
        'XML 1.0.',
        code: 'INVALID_VSIX',
      );
    }
    try {
      XmlDocument.parse(source);
    } on XmlParserException {
      throw CliException(
        'Assembled VSIX entry $path is not valid XML 1.0.',
        code: 'INVALID_VSIX',
      );
    }
  }
}

/// Whether every rune of [source] is legal in an XML 1.0 document.
bool containsOnlyXml10Characters(String source) => source.runes.every(
  (character) =>
      character == 0x9 ||
      character == 0xa ||
      character == 0xd ||
      (character >= 0x20 && character <= 0xd7ff) ||
      (character >= 0xe000 && character <= 0xfffd) ||
      (character >= 0x10000 && character <= 0x10ffff),
);

bool _listsEqual<T>(List<T> left, List<T> right) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (left[index] != right[index]) {
      return false;
    }
  }
  return true;
}

String _manifestString(Map<String, Object?> manifest, String key) {
  final value = manifest[key];
  if (value is! String || value.isEmpty) {
    throw CliException(
      'Generated package.json has no $key value.',
      code: 'INVALID_MANAGED_MANIFEST',
    );
  }
  return value;
}

String _manifestXmlText(Map<String, Object?> manifest, String key) {
  final value = _manifestString(manifest, key);
  if (!containsOnlyXml10Characters(value)) {
    throw CliException(
      'Generated package.json $key contains a character forbidden by XML '
      '1.0. Remove control characters from extension.dart, run '
      'flutter_vscode build, and package again.',
      code: 'INVALID_PROJECT_MANIFEST',
    );
  }
  return value;
}

String _manifestIdentifierComponent(
  Map<String, Object?> manifest,
  String key,
) {
  final value = _manifestString(manifest, key);
  if (!RegExp(r'^[a-z0-9][a-z0-9-]*$').hasMatch(value)) {
    throw CliException(
      'Generated package.json $key "$value" is unsafe for a packaged '
      'extension identifier. flutter_vscode requires lower-kebab '
      'components; update extension.dart and run flutter_vscode build again.',
      code: 'INVALID_PROJECT_MANIFEST',
    );
  }
  return value;
}

String _xml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');
