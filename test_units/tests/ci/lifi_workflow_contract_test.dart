import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

YamlMap workflow(String name) =>
    loadYaml(File('.github/workflows/$name.yml').readAsStringSync()) as YamlMap;

void main() {
  test('all builds select production without a staging choice', () {
    for (final action in ['lifi-profile', 'generate-assets']) {
      final config =
          loadYaml(
                File('.github/actions/$action/action.yml').readAsStringSync(),
              )
              as YamlMap;
      final input = action == 'lifi-profile'
          ? 'requested'
          : 'LIFI_BUILD_ENVIRONMENT';
      expect(config['inputs'][input]['default'], 'production');
    }
    for (final name in [
      'firebase-hosting-pull-request',
      'mobile-builds',
      'desktop-builds',
      'docker-android-build',
      'docker-linux-build',
    ]) {
      final config = workflow(name);
      final dispatch = config['on']['workflow_dispatch'] as YamlMap?;
      final inputs = dispatch?['inputs'] as YamlMap?;
      expect(inputs?['lifi_environment'], isNull);
      final jobs = config['jobs'] as Map;
      final steps = jobs.values.single['steps'] as List;
      final selection = steps.singleWhere(
        (dynamic step) => step['uses'] == './.github/actions/lifi-profile',
      );
      expect(selection['with']['requested'], 'production');
    }
  });

  test(
    'production LI.FI consumers run inside the existing required merge check',
    () {
      final config = workflow('validate-code-guidelines');
      expect(config['on']['pull_request']['paths'], isNull);
      expect(config['on']['pull_request']['branches'], contains('**'));
      final steps = config['jobs']['validate_code_guidelines']['steps'] as List;
      final gate = steps.where(
        (dynamic step) =>
            step['run'] == 'bash .github/scripts/test_lifi_profiles.sh',
      );
      expect(gate, hasLength(1));
      expect(gate.single['if'], isNull);
      expect(gate.single['continue-on-error'], isNull);
      final script = File(
        '.github/scripts/test_lifi_profiles.sh',
      ).readAsStringSync();
      expect(script, contains('set -euo pipefail'));
      expect(script, contains('for profile in production'));
    },
  );

  test('published native releases fail when a platform build fails', () {
    for (final platform in ['mobile', 'desktop']) {
      final config = workflow('$platform-builds');
      expect(config['on']['release']['types'], ['published']);
      expect(config['permissions'], {'contents': 'read'});
      final job = config['jobs']['build_$platform'];
      expect(job['continue-on-error'], isNull);
      expect(job['strategy']['fail-fast'], isFalse);
    }
  });

  test('native and Docker artifacts identify the selected public profile', () {
    for (final file in [
      'mobile-builds',
      'desktop-builds',
      'docker-android-build',
      'docker-linux-build',
    ]) {
      final config = workflow(file);
      final jobs = config['jobs'] as Map;
      final steps = jobs.values.single['steps'] as List;
      expect(
        steps.any(
          (dynamic step) => step['uses'] == './.github/actions/lifi-profile',
        ),
        isTrue,
      );
      final upload = steps.singleWhere(
        (dynamic step) => (step['uses'] as String? ?? '').startsWith(
          'actions/upload-artifact@',
        ),
      );
      final provenance = steps.singleWhere(
        (dynamic step) => step['uses'] == './.github/actions/build-provenance',
      );
      expect(
        upload['with']['name'],
        contains('steps.lifi_profile.outputs.environment'),
      );
      expect(upload['with']['if-no-files-found'], 'error');
      expect(provenance['with']['artifact_name'], upload['with']['name']);
    }
  });

  test('third-party GitHub Actions are pinned to full commit SHAs', () {
    final uses = RegExp(r'uses:\s*([^\s#]+)', multiLine: true);
    for (final file in Directory(
      '.github',
    ).listSync(recursive: true).whereType<File>()) {
      if (!file.path.endsWith('.yml') && !file.path.endsWith('.yaml')) continue;
      for (final match in uses.allMatches(file.readAsStringSync())) {
        final action = match.group(1)!;
        if (action.startsWith('./')) continue;
        expect(action, matches(r'^[^@]+@[0-9a-f]{40}$'), reason: file.path);
      }
    }
  });
}
