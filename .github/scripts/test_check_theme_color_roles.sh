#!/usr/bin/env bash
#
# Tests for check_theme_color_roles.sh.
#
# The checker is a regex over formatted Dart, and its whole value is telling a
# painted surface apart from a foreground. Both mistakes are silent: a pattern
# that is too broad flags every `TextStyle(color: onSurface)` until someone
# deletes the check, and one that is too narrow lets the original bug back in.
# These fixtures pin both edges.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
readonly script_dir
readonly subject="$script_dir/check_theme_color_roles.sh"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

failures=0

# fixture <name> <dart source>
fixture() {
  local name="$1" source="$2"
  rm -rf "$work/lib"
  mkdir -p "$work/lib"
  printf '%s\n' "$source" >"$work/lib/$name.dart"
}

expect_pass() {
  local name="$1"
  if (cd "$work" && "$subject" lib) >/dev/null 2>&1; then
    return
  fi
  echo "FAIL: '$name' should have been accepted" >&2
  (cd "$work" && "$subject" lib) >&2 || true
  failures=$((failures + 1))
}

expect_fail() {
  local name="$1"
  if (cd "$work" && "$subject" lib) >/dev/null 2>&1; then
    echo "FAIL: '$name' should have been rejected" >&2
    failures=$((failures + 1))
  fi
}

# A foreground read is the correct use of the role and must not be flagged.
fixture text_style "
Widget build(BuildContext context) => Text(
  'hello',
  style: TextStyle(color: Theme.of(context).colorScheme.onSurface),
);
"
expect_pass 'TextStyle color'

fixture icon_color "
Widget build(BuildContext context) => Icon(
  Icons.add,
  color: Theme.of(context).colorScheme.onSurface,
);
"
expect_pass 'Icon color'

# The original bug, in the shape the formatter actually produces.
fixture wrapped_decoration "
Widget build(BuildContext context) => Container(
  decoration: BoxDecoration(
    color:
        Theme.of(context).colorScheme.onSurface,
    borderRadius: BorderRadius.circular(8),
  ),
);
"
expect_fail 'BoxDecoration color wrapped across lines'

fixture single_line_decoration "
Widget build(BuildContext context) => Container(
  decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface),
);
"
expect_fail 'BoxDecoration color on one line'

fixture background_property "
final style = ButtonStyle(
  backgroundColor: WidgetStatePropertyAll(
    Theme.of(context).colorScheme.onSurface,
  ),
);
"
expect_fail 'backgroundColor property'

fixture scaffold_background "
final theme = ThemeData(scaffoldBackgroundColor: colorScheme.onSurface);
"
expect_fail 'scaffoldBackgroundColor derived from onSurface'

fixture cross_theme "
final color = theme.global.light.colorScheme.onSurface;
"
expect_fail 'widget reaching into the other theme'

# A marker with a reason suppresses the finding.
fixture suppressed "
Widget build(BuildContext context) => Container(
  // theme-role-ok: intentional, this paints the canvas behind a sheet
  decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface),
);
"
expect_pass 'marker with a reason'

# A marker with no reason is an allowance nobody can review.
fixture bare_marker "
Widget build(BuildContext context) => Container(
  // theme-role-ok
  decoration: BoxDecoration(color: Theme.of(context).colorScheme.onSurface),
);
"
expect_fail 'marker with no reason'

if ((failures > 0)); then
  echo "$failures check_theme_color_roles case(s) failed" >&2
  exit 1
fi

echo "check_theme_color_roles.sh OK."
