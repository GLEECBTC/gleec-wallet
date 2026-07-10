---
name: refactoring-guru-patterns
description: Select and apply the smallest appropriate GoF-style design pattern in Gleec Wallet and SDK code. Use when introducing interchangeable integrations, subsystem orchestration, lifecycle state, object families, or when reviewing pattern-related complexity.
---

# Refactoring Guru Patterns

Choose patterns from the pressure in the code, not from a desire to name abstractions:

- Use Adapter behind an app-owned interface for third-party APIs and SDKs.
- Use Strategy when mock/live or provider behavior must be interchangeable at runtime or composition time.
- Use Facade for a workflow spanning repositories, signing, and lifecycle coordination.
- Represent lifecycle State with sealed domain values/BLoC state unless behavior-rich state objects materially simplify transitions.
- Use a small Factory at the composition root when a coherent family of collaborators must be selected together; avoid an Abstract Factory hierarchy for two constructors.
- Prefer constructor injection. Do not introduce Singleton service locators.
- Prefer composition over inheriting concrete repositories.

Before adding a pattern, name the variability or coupling it removes. If an interface and one coordinator solve it, stop there.
