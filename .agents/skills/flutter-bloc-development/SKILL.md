---
name: flutter-bloc-development
description: Build or refactor Gleec Wallet Flutter features with BLoC, injected repository/service boundaries, immutable state, and the existing app theme/UI kit. Use for feature state, data integration, widgets connected to BLoC, or architecture reviews in this repository.
---

# Flutter BLoC Development

- Put new feature behavior in `Bloc<Event, State>` under `lib/bloc`; use sealed immutable events and an `Equatable` state with explicit status fields.
- Inject repositories, SDK clients, and services through constructors and register long-lived instances in the root `MultiRepositoryProvider`/`MultiBlocProvider`.
- Keep widgets limited to event dispatch, rendering, and presentation side effects. Never pass `BuildContext` into BLoCs or call SDK/RPC transports from widgets.
- Return typed domain models from repositories. Parse raw JSON at SDK or repository boundaries.
- Use `droppable()` for destructive/submit events, `restartable()` for refresh/search, and `sequential()` where ordering is an invariant.
- Prefer `BlocListener` for navigation, dialogs, and messages; never make one BLoC depend directly on another.
- Reuse `app_theme`, `komodo_ui_kit`, localization, and existing shared widgets. Do not invent a parallel token system.
- Extract discrete UI sections as widgets with explicit inputs and keep rebuild scopes low with `BlocSelector` or `context.select`.
- Add focused `bloc_test`, repository contract, widget, and semantics tests for new behavior even when legacy suites have unrelated failures.

Treat legacy `lib/blocs`, public imperative state methods, raw stream controllers, and direct widget-to-SDK calls as migration context, not examples.
