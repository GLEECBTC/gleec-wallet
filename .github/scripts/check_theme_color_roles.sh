#!/usr/bin/env bash
#
# Rejects Material colour-role misuse, specifically `colorScheme.onSurface`
# read as a background.
#
# Both app themes used to assign `onSurface` the page background and derive
# `scaffoldBackgroundColor` from it. That inverted Material's contract, so
# every widget that correctly painted text with `onSurface` rendered it in the
# canvas colour - the Private Keys Export notices measured 1.03:1. Analysis
# cannot catch a regression here: the wrong token still compiles, and CI runs
# `flutter analyze --no-fatal-warnings --no-fatal-infos`.
#
# `dart format` wraps `color:` and `.colorScheme.onSurface` onto separate
# lines, so a line-oriented grep produces false negatives. Each file is slurped
# and its whitespace collapsed before matching.
#
# Allowances are inline `// theme-role-ok: <reason>` markers rather than a
# path:line list, which goes stale the moment anything moves.

set -euo pipefail

readonly marker='theme-role-ok'
readonly default_roots=(app_theme lib packages)

fail() {
  echo "Error: $1" >&2
  exit 1
}

# Property names that are only ever a painted surface. A bare `color:` is
# deliberately absent: it names the *text* colour inside TextStyle and the
# *icon* colour on Icon, both of which are correct uses of a foreground role.
readonly background_properties='backgroundColor|fillColor|barrierColor|surfaceTintColor|selectedBackgroundColor|scaffoldBackgroundColor|cardColor|canvasColor|dividerColor'

# Constructors whose `color:` argument is a surface rather than a foreground.
readonly painted_constructors='BoxDecoration|ShapeDecoration|ColoredBox|DecoratedBox|Border\\.all|BorderSide|Card|Material'

scan() {
  local roots=("$@")
  perl -0777 -ne '
    my $src = $_;
    my $file = $ARGV;
    $src =~ s/\r//g;
    my @lines = split(/\n/, $src, -1);

    # An allowance is honoured when the marker sits in the comment block just
    # above the finding. Six lines, because a reason worth writing usually
    # wraps, and because the formatter can push the argument down a line.
    my $allowed = sub {
      my ($line) = @_;
      for my $i (($line - 7) .. ($line - 1)) {
        next if $i < 0 || $i > $#lines;
        return 1 if $lines[$i] =~ /'"$marker"'\s*:\s*\S/;
      }
      return 0;
    };

    my @patterns = (
      # backgroundColor: ... onSurface
      qr/(?:'"$background_properties"')\s*:\s*(?:[^,;{}]|\n){0,160}?colorScheme\s*\.\s*onSurface\b/,
      # BoxDecoration( ... color: ... onSurface
      qr/(?:'"$painted_constructors"')\s*\(\s*(?:[^()]|\n){0,120}?\bcolor\s*:\s*(?:[^,;{}]|\n){0,120}?colorScheme\s*\.\s*onSurface\b/,
    );

    # A widget reaching into the *other* theme is the same bug in a different
    # costume: UiPrimaryButton read theme.global.light.colorScheme.onSurface
    # for a near-white, which only worked while that role held a background.
    push @patterns, qr/theme\s*\.\s*global\s*\.\s*(?:light|dark)\s*\.\s*colorScheme/
      if $file !~ m{^(?:\./)?app_theme/};

    for my $pattern (@patterns) {
      while ($src =~ /$pattern/g) {
        my $hit = $&;
        my $line = 1 + (substr($src, 0, $-[0]) =~ tr/\n//);
        next if $allowed->($line);
        $hit =~ s/\s+/ /g;
        print "$file:$line: $hit\n";
      }
    }
  ' $(find "${roots[@]}" -name "*.dart" \
      -not -path "*/build/*" -not -path "*/.dart_tool/*" | sort)
}

# An allowance nobody needs any more is a comment that has stopped meaning
# anything; fail on those too rather than letting them accumulate.
check_orphaned_markers() {
  local roots=("$@")
  local orphans=()
  while IFS= read -r hit; do
    orphans+=("$hit")
  done < <(grep -rn "$marker" "${roots[@]}" --include='*.dart' 2>/dev/null |
    grep -Ev "$marker\s*:\s*\S" || true)

  if ((${#orphans[@]} > 0)); then
    printf '%s\n' "${orphans[@]}" >&2
    fail "found ${#orphans[@]} '$marker' marker(s) with no reason. Write '// $marker: <why>'."
  fi
}

main() {
  local roots=("$@")
  ((${#roots[@]} == 0)) && roots=("${default_roots[@]}")

  for root in "${roots[@]}"; do
    [[ -d "$root" ]] || fail "no such directory: $root"
  done

  check_orphaned_markers "${roots[@]}"

  local violations
  violations=$(scan "${roots[@]}")

  if [[ -n "$violations" ]]; then
    echo "$violations" >&2
    echo >&2
    fail "colorScheme.onSurface is a *foreground* role - content drawn on a surface.
Use Theme.of(context).scaffoldBackgroundColor for the page colour, or a
surfaceContainer role for a raised panel. If a use really is correct, mark it
with '// $marker: <reason>' on the line above."
  fi

  echo "Theme colour roles OK."
}

main "$@"
