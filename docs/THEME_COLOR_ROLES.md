# Theme color roles

The app theme owns the shared palette. Use roles according to what they paint:

| Element | Role |
|---|---|
| App canvas | `ThemeData.scaffoldBackgroundColor`: dark `#000000`, light `#FBFBFB` |
| Cards, panels and dialogs | `surface` or the corresponding surface-container role |
| Main text and icons on surfaces | `onSurface`: dark `#FFFFFF`, light `#456078` |
| Secondary text | `onSurfaceVariant` |
| Input fill and text | `InputDecorationTheme` |
| Borders | `outline` or `outlineVariant` |
| Modal barrier | Shared `dialogBarrierColor`, backed by `scrim` |
| Product-specific meaning | Existing theme extensions |

`onSurface` is a foreground color. Do not assign it to a canvas, fill, border or
barrier. Preserve the explicitly pinned light-theme container colors until a
reviewed palette change replaces them. Pair custom button backgrounds with the
button's contrast helper; standard primary buttons use `onPrimary`.

## Validation

`.github/scripts/check_theme_color_roles.sh` runs in the code-guideline workflow.
Its paired shell fixtures test the guard itself. The theme contract lives in
`test_units/theme/theme_color_roles_test.dart`, registered in the wallet suite.
Run the complete unit command in [TESTING.md](TESTING.md) for release validation.

For changed components, inspect light and dark modes at phone and desktop widths
and at 200% text scale. Check primary text contrast, secondary labels, disabled
states, custom button spinners and dialog barriers. Keep visual evidence with the
change's review artifacts, outside maintained release documentation.
