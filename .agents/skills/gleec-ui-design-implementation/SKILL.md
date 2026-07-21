---
name: gleec-ui-design-implementation
description: Implement approved Gleec Wallet interfaces in Flutter with existing theme/UI-kit primitives, adaptive layouts, accessible interactions, complete async states, and scoped visual verification. Use when creating or refining production screens and components in this repository.
---

# Gleec UI Implementation

- Read the feature design contract and existing theme/UI-kit APIs before writing widgets.
- Build mobile-first with `LayoutBuilder`, bounded content widths, adaptive gutters, safe areas, and no device-name branching.
- Use semantic `ColorScheme`/theme-extension values and existing buttons, inputs, cards, skeletons, and typography.
- Keep critical values stable with tabular figures and locale-aware currency/date formatting.
- Use Material interaction primitives, tooltips, focus traversal, `Semantics`, and minimum 48dp targets.
- Keep motion purposeful, interruptible, 150–300ms, and disabled or simplified when accessible navigation/reduced motion is active.
- Put sensitive rendering behind an isolated gateway/widget and activate screenshot sensitivity for its lifecycle.
- Add previews for representative states, widget/semantics tests for behavior, and responsive checks at the project breakpoints.
- Run `dart format` on changed files and scoped `flutter analyze`; separate pre-existing failures from new ones.
