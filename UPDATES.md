# Recent Updates & Decisions

This file is the append-only log of project decisions and notable changes, maintained by coding agents following the `recent-updates` skill. Everything below the marker line is user-owned history: slopctl never overwrites it during init or merge.

<!-- {changelog} -->

### 2026-09-01 (v5.9.0, claude fable weekly window)

- claude code menu now shows a Fable share of 7-day limit row directly below the 7-day window
- the row is named for a share rather than a window because weekly_scoped is a sub-cap inside the weekly limit, not a separate allowance, and two stacked percentages otherwise read as additive
- the plan-specific 50 percent figure is kept out of the label since fable runs on usage credits rather than the weekly limit on pro
- fable arrives only as a weekly_scoped entry of the /api/oauth/usage limits array, not as a top-level seven_day_* key, so the response decoder gained limits[] with its scope/model shape
- the row is pushed with skipIfEmpty false because an unstarted fable window reports percent 0 and a null reset, which the shared window helper would otherwise drop
- the limits array's session and weekly_all entries are ignored since they restate five_hour and seven_day
- the model is matched by case-insensitive substring on display_name or id, so a later versioned name such as Fable 5 does not silently drop the row
- rationale: fable usage was invisible in token torch; the field name was confirmed against a live read-only usage request rather than guessed from third-party docs, which disagreed
- version bump: 5.8.6 to 5.9.0 (MINOR - new user-facing quota row, backward compatible)

### 2025-10-05 (v0.1.0, initial setup)

- initial AGENTS.md setup
- established core coding standards and conventions
- defined repository structure and governance principles
