---
name: gleec-ui-pro-design-gate
description: Audit a proposed Gleec Wallet screen or flow before implementation for hierarchy, financial trust, accessibility, responsive behavior, theme consistency, and complete loading/empty/error/recovery states. Use for UI design reviews and implementation readiness decisions.
---

# Gleec UI Design Gate

Approve a design only when it satisfies all of these checks:

1. Preserve Gleec's Manrope typography, semantic theme colors, and UI-kit components; reject generic crypto neon, speculative partner branding, and hard-coded per-screen palettes.
2. Make custody context, asset/network, amount, fees, timing, status, and recovery actions explicit for financial operations.
3. Define happy, loading, empty, pending, blocked, failure, retry, expired-session, and destructive-confirmation states.
4. Keep one primary action per surface; maintain predictable back behavior and a maximum of five narrow-screen primary navigation items.
5. Meet 48dp touch targets, visible keyboard focus, logical semantics order, 4.5:1 body-text contrast, large text, reduced motion, and color-independent status communication.
6. Specify layouts at 375, 768, 1024, and 1440 logical pixels without horizontal overflow or unreadably wide text.
7. Isolate sensitive data from screenshots, logs, analytics, state snapshots, and ordinary domain models.

Record rejected directions and the reason. Design-tool output is advisory; product intent and repository tokens remain authoritative.
