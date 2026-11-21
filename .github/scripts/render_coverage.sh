#!/usr/bin/env bash
set -euo pipefail

# The caller deletes stale LCOV before running its one complete test suite.
# A failed test step prevents this action from running; never rerun a different
# configuration here or publish a report after a failed command.
test -s coverage/lcov.info
if ! command -v genhtml >/dev/null 2>&1; then
  case "${RUNNER_OS:-}" in
    Linux) bash .github/scripts/setup_linux_dependencies.sh lcov ;;
    macOS) command -v brew >/dev/null; brew install lcov ;;
    *) echo 'A supported coverage reporting environment is required.'; exit 1 ;;
  esac
fi
rm -rf coverage/html
rm -f coverage-html.zip
genhtml -q coverage/lcov.info -o coverage/html
test -s coverage/html/index.html
zip -q -r coverage-html.zip coverage/html
printf '%s\n' 'Coverage report rendered from the passing test result.'
