import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:yaml/yaml.dart';

void main() {
  test('SDK reference YAML matches the canonical pinned build manifest', () {
    const base = 'sdk/packages/komodo_defi_framework/app_build/build_config';
    final canonical = jsonDecode(File('$base.json').readAsStringSync());
    final reference = loadYaml(File('$base.yaml').readAsStringSync());
    expect(reference, canonical);
    expect(canonical['coins']['update_commit_on_build'], isFalse);
    expect(canonical['api']['require_full_commit_hash'], isTrue);
  });
}
