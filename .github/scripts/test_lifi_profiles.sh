#!/usr/bin/env bash
set -euo pipefail

# Called by the existing required validate_code_guidelines job. Each profile
# is compiled by Flutter, then checked against an independent expected identity.
python3 -m unittest discover -s tool -p 'test_*lifi*.py' -v
# Also compile without a profile: a direct Flutter build must default to production.
flutter test --no-pub --no-test-assets \
  test_units/tests/swap/lifi_integrator_policy_test.dart \
  --dart-define=LIFI_TEST_EXPECTED_ENVIRONMENT=production
for profile in staging production; do
  defines=$(python3 tool/lifi_build_config.py "$profile")
  flutter test --no-pub --no-test-assets \
    test_units/tests/swap/lifi_integrator_policy_test.dart \
    test_units/tests/mm2/lifi_proxy_url_test.dart \
    test_units/tests/mm2/sdk_build_manifest_test.dart \
    test_units/tests/ci/lifi_workflow_contract_test.dart \
    --dart-define-from-file="$defines" \
    --dart-define=LIFI_TEST_EXPECTED_ENVIRONMENT="$profile"
done
