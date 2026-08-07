import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../dart_vscode/tool/binding_generator/contract.dart'
    as contract_writer;
import 'support/repository.dart';

void main() {
  test('the workflow is the one aggregate: every suite and gate is a step', () {
    // There is no aggregate script; the workflow lists what CI runs, and
    // scripts/ci_gates.sh mirrors it locally. A suite or gate missing here
    // is a suite or gate CI silently stopped running. The YAML is parsed
    // rather than grepped: a working-directory that only feeds the checks
    // job's publish dry-run must not satisfy a suite requirement.
    final source = File(
      repoPath('.github/workflows/test.yml'),
    ).readAsStringSync();
    final workflow = loadYaml(source) as YamlMap;
    final jobs = workflow['jobs'] as YamlMap;

    List<YamlMap> steps(String job) =>
        ((jobs[job] as YamlMap)['steps'] as YamlList)
            .whereType<YamlMap>()
            .toList();
    final commands = [
      for (final job in jobs.keys)
        for (final step in steps(job as String))
          if (step['run'] != null) step['run']! as String,
    ].join('\n');

    expect(commands, contains('flutter analyze'));
    expect(
      commands,
      contains('dart pub publish --dry-run --ignore-warnings'),
    );
    expect(commands, contains('git diff --exit-code'));
    expect(commands, contains('git status --porcelain'));
    for (final gate in [
      './scripts/test_binding_importer.sh',
      './scripts/test_host_extension.sh',
      './scripts/test_packaged_extension.sh',
      './scripts/test_coverage_extension.sh',
      './scripts/test_pubspec_lens.sh',
      './scripts/test_breakpoints.sh',
      './scripts/test_host_extension_native.sh',
    ]) {
      expect(commands, contains(gate));
    }

    // Kali's review: real webview bugs were found on desktop. Every gate
    // that exercises a live VS Code must therefore run natively on macOS
    // too, not only inside the Linux container.
    final desktopCommands = [
      for (final step in steps('desktop'))
        if (step['run'] != null) step['run']! as String,
    ].join('\n');
    expect(
      desktopCommands,
      contains('./scripts/test_host_extension_native.sh'),
    );
    for (final gate in [
      './scripts/test_coverage_extension.sh',
      './scripts/test_pubspec_lens.sh',
      './scripts/test_breakpoints.sh',
      './scripts/test_packaged_extension.sh',
    ]) {
      expect(
        desktopCommands,
        contains('FLUTTER_VSCODE_GATE_NATIVE=1 $gate'),
        reason: '$gate must also prove the desktop platform',
      );
    }

    final testSuiteDirectories = {
      for (final step in steps('test'))
        if (step['working-directory'] != null)
          step['working-directory']! as String,
    };
    for (final suite in [
      'packages/dart_vscode',
      'packages/flutter_vscode',
      'extensions/pubspec_lens/shared',
      'extensions/coverage_treemap/shared',
      'extensions/coverage_treemap/views/treemap_panel',
    ]) {
      expect(
        testSuiteDirectories,
        contains(suite),
        reason: 'the $suite suite must run as its own test-job step',
      );
    }
  });

  test('generated structural names stay behind Framework Modules', () {
    // JSAnon_* names are hashes of anonymous IR shapes: a baseline bump
    // can rename them, so any authored file that names one breaks on
    // maintenance the author never asked for. The one place allowed to
    // name them is the Framework Module that exists to hide them
    // (context.own in package:dart_vscode/host_commands.dart).
    final authored = <String>[
      repoPath('packages/dart_vscode/lib/src/host_runtime.dart'),
      repoPath('packages/dart_vscode/lib/src/flutter_view_host.dart'),
      'lib/src/cli/create_command.dart',
      'test/fixtures/host_extension/host/lib/extension.dart',
      repoPath('extensions/pubspec_lens/host/lib/extension.dart'),
      repoPath('extensions/coverage_treemap/host/lib/extension.dart'),
    ];
    for (final path in authored) {
      expect(
        File(path).readAsStringSync(),
        isNot(contains('JSAnon_')),
        reason:
            '$path must own registrations via context.own, not the '
            'generated structural name',
      );
    }
  });

  test('no project carries a copy of the protocol to drift from', () {
    // The protocol is a library in package:dart_vscode; there is no second
    // copy that could disagree with it.
    expect(
      Directory(
        'test/fixtures/host_extension/shared/lib/generated',
      ).existsSync(),
      isFalse,
    );
  });

  test('the Host fixture composes the framework view-host skeleton', () {
    final fixture = File(
      'test/fixtures/host_extension/host/lib/extension.dart',
    ).readAsStringSync();

    expect(
      fixture,
      contains('FlutterViewHost.open('),
      reason: 'the fixture must compose the framework-owned view host',
    );
    for (final skeleton in [
      'String _viewHtml(',
      'createFlutterViewPanel(',
      'HostViewSession.connect(',
      'Content-Security-Policy',
    ]) {
      expect(
        fixture,
        isNot(contains(skeleton)),
        reason:
            'only adversity machinery may stay fixture-owned; '
            '"$skeleton" belongs to FlutterViewHost',
      );
    }
  });

  test('published packages exclude repository-only hardening fixtures', () {
    final pubIgnore = File('.pubignore').readAsLinesSync().toSet();

    expect(
      pubIgnore,
      containsAll({
        // The specs, gate scripts, docs, and example extensions live above
        // this package, so the archive never sees them and `.pubignore` has
        // nothing to say about them. Nothing under tool/ is an
        // Extension Author asset either.
        '/test/',
        '**/build/',
        '/tool/',
      }),
    );
    // Binding generation is a dart_vscode maintainer operation: the
    // framework package holds none of it, so its ignore file has nothing
    // to say about it either.
    expect(Directory('tool/bindings').existsSync(), isFalse);
    expect(Directory('tool/binding_generator').existsSync(), isFalse);
    for (final line in pubIgnore) {
      expect(line, isNot(contains('binding')));
    }

    // dart_vscode ships the generated API layer but never its maintainer
    // tool/ area: the importer, generator, IR, and pinned inputs stay
    // repository-only, and its tests stay beside the package per Dart
    // convention without shipping in the archive.
    final layerPubIgnore = File(
      repoPath('packages/dart_vscode/.pubignore'),
    ).readAsLinesSync().toSet();
    expect(layerPubIgnore, containsAll({'/tool/', '/test/'}));

    // The artifact grows with the number of files it attests, and splitting
    // a module into parts means more files, not more prose. The bound keeps
    // it reviewable; it is not a claim that fewer receipts is better.
    expect(
      File(repoPath(contract_writer.contractArtifactPath)).lengthSync(),
      lessThan(24 * 1024),
    );
  });

  test('shipped example extensions honor the Extension Author guardrails', () {
    final areaReadme = File(
      repoPath('extensions/README.md'),
    ).readAsStringSync();
    expect(
      areaReadme,
      contains('consumes the framework the way an Extension'),
      reason: 'extensions/README.md must record the guardrails',
    );
    expect(
      File('README.md').readAsStringSync(),
      contains('extensions/'),
      reason: 'the root README must route readers to the shipped examples',
    );
    final workflow = File(
      repoPath('.github/workflows/test.yml'),
    ).readAsStringSync();
    expect(
      workflow,
      contains('test_coverage_extension.sh'),
      reason: 'CI must run the example-extension gate',
    );
    expect(
      workflow,
      contains('test_pubspec_lens.sh'),
      reason: 'CI must run the pubspec-lens gate',
    );
    final extensionDirs = Directory(
      repoPath('extensions'),
    ).listSync().whereType<Directory>();
    expect(extensionDirs, isNotEmpty);
    for (final extension in extensionDirs) {
      for (final root in ['host', 'shared']) {
        final dir = Directory(p.join(extension.path, root, 'lib'));
        if (!dir.existsSync()) {
          continue;
        }
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is! File || !entity.path.endsWith('.dart')) {
            continue;
          }
          final source = entity.readAsStringSync();
          // The published surface is fair game -- an Extension Author
          // imports the shipped API layer exactly like this. Reaching into
          // the repository's private `src/` is what the guardrail forbids.
          expect(
            source,
            isNot(contains("import 'package:flutter_vscode/src/")),
            reason:
                '${entity.path} must consume the published package '
                'surface, never the framework internals (guardrail)',
          );
        }
      }
    }
  });

  test('the startup measurement is documented from gate output', () {
    final doc = File(repoPath('docs/reference/startup.md')).readAsStringSync();
    expect(
      doc,
      contains('webview load to first rendered frame'),
      reason: 'the doc must define what the measurement covers',
    );
    expect(
      doc,
      contains('viewColdStartMs'),
      reason: 'the doc must name the gate field it cites',
    );
    expect(
      doc,
      contains('Recorded'),
      reason: 'the doc must carry a recording-time value from a gate run',
    );
    for (final harness in [
      'test/fixtures/host_extension/test/run.cjs',
      'test/fixtures/packaged_test_driver/test/run.cjs',
    ]) {
      expect(
        File(harness).readAsStringSync(),
        contains('viewColdStartMs'),
        reason: '$harness must assert and print the measurement',
      );
    }
  });

  test('packaged E2E activates the pub-filtered framework contents', () {
    final packagedGate = File(
      repoPath('scripts/test_packaged_extension.sh'),
    ).readAsStringSync();

    expect(
      packagedGate,
      contains('dart tool/pub_archive_list.dart'),
      reason: "staging must consume pub's actual archive file selection",
    );
    expect(
      packagedGate,
      isNot(contains('rsync')),
      reason: 'no rsync approximation of the publish archive may remain',
    );
    expect(
      packagedGate,
      isNot(contains(r'VIEW_FIXTURE_ROOT="${PACKAGE_COPY}/test/fixtures')),
    );
    expect(
      packagedGate,
      contains(
        r'"override:flutter_vscode@{path: ${PACKAGE_COPY}}"',
      ),
    );
  });

  test('the pinned host is proven on macOS, not only in Linux containers', () {
    // Every live-only webview bug this project has found was found by hand
    // on desktop; the containers cannot see that class of failure. The
    // native gate runs the same driver against the same pinned VS Code,
    // directly on the host OS -- no Docker, no xvfb.
    final native = File(repoPath('scripts/test_host_extension_native.sh'));
    expect(native.existsSync(), isTrue);
    final script = native.readAsStringSync();
    expect(
      script,
      isNot(contains('docker')),
      reason: 'the native gate exists precisely to not be a container',
    );
    expect(
      script,
      contains('run.cjs'),
      reason: 'same driver, same pinned VS Code, different platform',
    );

    final workflow = File(
      repoPath('.github/workflows/test.yml'),
    ).readAsStringSync();
    expect(
      workflow,
      contains('runs-on: macos-latest'),
      reason: 'desktop stays proven only if CI runs it',
    );
    expect(workflow, contains('./scripts/test_host_extension_native.sh'));
  });

  test('Extension Host gates use fresh invocation-scoped VS Code caches', () {
    for (final path in [
      repoPath('scripts/test_host_extension.sh'),
      repoPath('scripts/test_packaged_extension.sh'),
    ]) {
      final gate = File(path).readAsStringSync();

      expect(gate, contains('mktemp -d'), reason: path);
      expect(
        gate,
        contains(r'TEMP_ROOT="$(cd "${TEMP_ROOT}" && pwd -P)"'),
        reason: path,
      );
      expect(
        gate,
        contains(r'CACHE_ROOT="${TEMP_ROOT}/vscode-test-cache"'),
        reason: path,
      );
      expect(gate, contains('trap cleanup EXIT'), reason: path);
      expect(gate, contains(r'rm -rf "${TEMP_ROOT}"'), reason: path);
      expect(
        gate,
        contains(r'--volume "${CACHE_ROOT}:/vscode-test-cache"'),
        reason: path,
      );
      expect(gate, isNot(contains('docker volume create')), reason: path);
      expect(gate, isNot(contains('CACHE_VOLUME=')), reason: path);
    }
  });

  test('Host fixture resolves the receipted root package before its CLI', () {
    final builder = File(
      repoPath('scripts/build_host_fixture.sh'),
    ).readAsStringSync();
    const repositoryRoot = r'${REPO_ROOT}';
    const resolution =
        'flutter pub get --enforce-lockfile --no-example '
        '--directory="$repositoryRoot"';
    const packageBin = 'packages/flutter_vscode/bin/flutter_vscode.dart';
    const cli = 'dart "$repositoryRoot/$packageBin" build';

    expect(builder, contains(resolution));
    expect(builder, contains(cli));
    expect(builder.indexOf(resolution), lessThan(builder.indexOf(cli)));
  });

  test('lock-enforced Host builds include a trackable root lockfile', () {
    // One workspace, one lockfile: it lives at the repository root and is the
    // pinned resolution for the framework and every member package alike.
    expect(
      FileSystemEntity.typeSync(repoPath('pubspec.lock')),
      FileSystemEntityType.file,
    );

    final ignored = Process.runSync(
      'git',
      ['check-ignore', '--quiet', '--', 'pubspec.lock'],
    );
    expect(
      ignored.exitCode,
      1,
      reason: 'pubspec.lock must survive a fresh repository checkout.',
    );

    final repositoryFiles = Process.runSync(
      'git',
      ['ls-files', '--cached', '--', 'pubspec.lock'],
      workingDirectory: repositoryRoot.path,
    );
    expect(
      repositoryFiles.exitCode,
      0,
      reason:
          'git failed in ${repositoryRoot.path}:\n'
          '${repositoryFiles.stdout}\n${repositoryFiles.stderr}',
    );
    expect(
      (repositoryFiles.stdout as String).trim(),
      'pubspec.lock',
      reason:
          'pubspec.lock must be committed, not merely untracked and '
          'unignored, so a fresh checkout satisfies --enforce-lockfile.',
    );

    final committedFiles = Process.runSync(
      'git',
      ['ls-tree', '--name-only', 'HEAD', '--', 'pubspec.lock'],
      workingDirectory: repositoryRoot.path,
    );
    expect(
      committedFiles.exitCode,
      0,
      reason:
          'git failed in ${repositoryRoot.path}:\n'
          '${committedFiles.stdout}\n${committedFiles.stderr}',
    );
    expect(
      (committedFiles.stdout as String).trim(),
      'pubspec.lock',
      reason:
          'pubspec.lock must exist in the HEAD tree, not merely the '
          'index, so a fresh checkout satisfies --enforce-lockfile.',
    );
  });

  test('parity report is linked from the reference index', () {
    expect(
      File(repoPath('docs/reference/index.md')).readAsStringSync(),
      contains('parity.md'),
      reason: 'the generated parity burn-down must be discoverable',
    );
    expect(
      File(repoPath('docs/reference/parity.md')).readAsStringSync(),
      contains('defect'),
      reason:
          "the report must state the vision's missing-path-is-a-defect "
          'rule',
    );
  });

  test('generated Host API guide registers providers synchronously', () {
    final guide = File(
      repoPath('docs/reference/generated-host-api.md'),
    ).readAsStringSync();

    expect(guide, isNot(contains('Future<JSAny?>(()')));
    expect(guide, contains('Future<JSAny?>.value(null).toJS'));
    expect(
      guide.indexOf('registerCommand'),
      lessThan(guide.indexOf('Future<JSAny?>.value(null).toJS')),
      reason:
          'the activation example must register through the single '
          "layer's registerCommand before returning its settled future",
    );
    expect(guide, contains('toHostCallback'));
  });
}
