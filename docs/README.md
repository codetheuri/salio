# Salio Documentation Index

This directory is the single source of truth for all Salio project documentation.

---

## Documents

| # | Document | Description |
|---|---|---|
| 01 | [Product Requirements (PRD)](./01-product-requirements.md) | What we are building, for whom, and why. Features, goals, and non-goals. |
| 02 | [Data Models](./02-data-models.md) | Core entities (Customer, Transaction), SQLite schema, and example queries. |
| 03 | [User Flows](./03-user-flows.md) | Step-by-step flows for every key user journey in the app. |
| 04 | [Mobile Architecture](./04-mobile-architecture.md) | Flutter app architecture: folder structure, state management, and offline-first strategy. |
| 05 | [Design System](./05-design-system.md) | Visual identity: colors, typography, spacing, and component guidelines. |
| 06 | [Technical Design](./06-technical-design.md) | Low-level technical decisions for mobile, backend, and sync. |
| 07 | [Phase 4: Analytics & Roles](./07-phase4-analytics-and-roles.md) | Multi-user roles, server-side analytics, offline fallbacks, and UI animations. |
| 08 | [Backend rewrite on Tusk](./08-tusk-rewrite-plan.md) | server-v2: decisions, the sync diagnosis, phases 0–7d and the contract changes. |
| 09 | [Operations](./09-operations.md) | Running server-v2: tenant isolation, database roles, Docker deployment, sessions, CI. |
| 10 | [Mobile app v2 plan](./10-mobile-app-plan.md) | The new Flutter app: decisions, sync engine, responsive UI, self-update, milestones. |

---

## Quick Reference (v1 app)

For the v2 app, see 10.

- **Target platform (Phase 1):** Android (physical device)
- **Database (mobile):** SQLite via `sqflite`
- **State management:** Provider (`ChangeNotifier`)
- **Primary IDs:** UUID v4 (generated client-side)
- **Currency:** KES (Kenyan Shillings)
- **Backend language:** Go (Phase 2)
- **Backend database:** PostgreSQL (Phase 2)
