# Unused usage response fields

Fields that the subscription usage endpoints return but Token Torch does not read. This file is a
reference for future changes. The sample responses live next to it in this folder.

Each section is a snapshot of one capture (`--capture-usage-responses docs`). Add new captures as new
sections at the top, and leave older sections unchanged so the history shows when fields appeared or
changed. Meanings are inferred from names and values, since none of these APIs are documented.

## Capture 2026-10-04 11:03 UTC

Token Torch 5.13.0. Accounts: Claude Max 20x, ChatGPT Pro Lite, Copilot Individual Max.

Fields first read in this version, so not listed below:

- Claude: `extra_usage.user_disabled` / `spend_limit_reached`, `cedar_ember`
  `eligible` and grant `resets_left` / `ends_at`, and window `limit_dollars` / `used_dollars`.
- Codex: `model_usage` and `rate_limit_reset_credits.applicable_available_count` (shown only when above 0; it
  counts credits that would reset a window right now, and is 0 when no window has usage to clear).
- Copilot: `overage_entitlement` and `credits_used`.

### Claude Code — `GET /api/oauth/usage?cedar_ember=1`

| Field | Captured value | Likely meaning |
| --- | --- | --- |
| `spend.used` | `{amount_minor: 0, currency: "USD", exponent: 2}` | Extra usage spend as integer minor units; a newer counterpart to `extra_usage` |
| `spend.limit`, `cap`, `balance`, `auto_reload` | `null` | Spend cap, prepaid balance, auto top-up settings |
| `spend.percent`, `severity`, `enabled`, `disabled_reason` | `0`, `"normal"`, `false`, `null` | Spend share of cap and its warning level |
| `spend.can_purchase_credits`, `can_toggle` | `false`, `false` | Whether the account may buy credits or toggle extra usage |
| `spend.disclaimer` | "Usage credits cover you when you hit your plan limits. [Learn more](…)" | Help text |
| `member_dashboard_available` | `false` | Probably a Team/Enterprise admin dashboard flag |
| `seven_day_breakdown.rows[]` | `Claude Code` 97, `Chats` 3, `Cowork` 0, `Other` 0 (`key`, `display_name`, `percent`) | Weekly usage split by surface. Shown briefly as a "7-day usage by surface" row, then removed as not helpful |
| `seven_day_breakdown.as_of`, `window_started_at` | `2026-10-04T11:03:22Z`, `2026-10-02T09:00:00Z` | When the breakdown was computed and the 7-day window start |
| Every window: `remaining_dollars`, `locked_reason` | `null` (`250.0` on `iguana_necktie`) | Remaining money (we compute it) and why a window is blocked |
| `extra_usage.credits_ever_enabled` | `true` | Whether extra usage was ever turned on |
| `extra_usage.disabled_reason`, `decimal_places` | `null` | Reason for an imposed disable; currency precision |
| `extra_usage.daily`, `weekly` | `null` | Possibly daily and weekly spend caps |
| `limits[].group`, `severity`, `is_active` | e.g. `"weekly"`, `"normal"`, `true` | Limit grouping, warning level, which limit currently applies |
| `limits[].scope.surface` | `null` | Scopes a limit to a surface instead of a model |
| `cedar_ember.grants[].label` | "Claude Opus 5.5 launch: one usage-limit reset for Pro and Max" | Why the grant exists. Shown briefly as a caption, then removed: only the count matters |
| `cedar_ember.grants[].clears` | `five_hour`, `seven_day`, `seven_day_overage_included` | Windows a reset clears. Removed with the caption |
| `cedar_ember.grants[].id`, `resets_total`, `starts_at` | `opus55-launch-promax-20260921`, `1`, `2026-09-22T16:00:00Z` | Grant identity and validity start |
| `cedar_ember.grants[].paused`, `usable_now`, `use_requires_limit` | `false`, `true`, `false` | Whether a reset can be spent right now |
| `cedar_ember.grants[].percent_used` | `{five_hour: 2, seven_day: 5, seven_day_overage_included: 0}` | Current usage of the windows a reset would clear |
| `cedar_ember.grants[].blocking`, `arm` | `[]`, `null` | Unknown; possibly reasons a reset is blocked, and A/B test arm |
| `cedar_ember.at_limit`, `exhausted`, `cooldown_until`, `ineligible_reason` | `false`, `[]`, `null`, `null` | Reset program state |
| `cedar_ember.next_grant_id` | `opus55-launch-promax-20260921` | The grant a claim would use (we pick the one expiring soonest) |
| `cedar_ember.weekly_resets_at` | `2026-10-09T09:00:00Z` | Same as `seven_day.resets_at` |
| `cedar_ember.event_props` | `surface: claude_code_cli`, `tier: claude_max_20x`, `tenure_bucket: 365+`, `billing_path: stripe`, `billing_period: unknown`, `extra_usage_state: disabled` | Analytics properties; `tier` could confirm the plan without the credential's `rateLimitTier` |
| Null windows, not decoded | `nimbus_quill`, `cinder_cove`, `copper_kite`, `brass_thimble`, `harbor_lantern`, `wattle_ember`, `amber_ladder`, `amber_cistern`, `juniper_tide`, `amber_gauge` | Reserved codename windows. `iguana_necktie` was one of these until the cloud session credit filled it |
| Null windows, already decoded | `seven_day_oauth_apps`, `seven_day_opus`, `seven_day_sonnet`, `seven_day_cowork`, `seven_day_omelette`, `tangelo`, `omelette_promotional` | Rows appear automatically once these return data |

### Codex — `GET /backend-api/wham/usage`

| Field | Captured value | Likely meaning |
| --- | --- | --- |
| `user_id`, `account_id`, `email` | (scrubbed) | Account identifiers; deliberately not read |
| `credits.approx_local_messages`, `approx_cloud_messages` | `[63, 325]`, `[10, 63]` | Low/high estimate of messages the credit balance buys. Shown briefly as a caption under Extra usage, then removed |
| `rate_limit.primary_window.reset_after_seconds` | `604800` | Seconds until reset; redundant with `reset_at`, which we read |
| `model_usage.<model>.available_at` | `null` | Shape unknown; parsed as RFC 3339 text or epoch seconds if it appears |

Codex sent no `x-codex-*` response headers, so OpenUsage's header fallbacks for used percent and credit
balance have no data to read.

### Copilot — `GET /copilot_internal/user`

| Field | Captured value | Likely meaning |
| --- | --- | --- |
| `quota_snapshots.*.quota_id` | Same as the bucket key | Bucket identity |
| `quota_snapshots.*.has_quota` | `true` | Whether the bucket applies to the account |
| `quota_snapshots.*.timestamp_utc` | `2026-10-04T11:03:23.551Z` | When GitHub computed the snapshot; a possible freshness hint |
| `quota_snapshots.*.quota_reset_at` | `0` | Apparently unused by GitHub; `quota_reset_date_utc` is authoritative |
| `quota_snapshots.*.token_based_billing`, top-level `token_based_billing` | `true` | Usage-based billing (AI credits) is active |
| `can_upgrade_plan`, `can_signup_for_limited` | `false`, `false` | Upsell flags |
| `chat_enabled`, `cli_enabled`, `is_mcp_enabled`, `copilot_app_enabled`, `cloud_session_storage_enabled`, `cli_remote_control_enabled`, `editor_preview_features_enabled`, `copilotignore_enabled` | all `true` except `copilotignore_enabled: false` | Feature flags, not usage |
| `restricted_telemetry`, `enterprise_usage_telemetry`, `te`, `is_staff` | `false` | Telemetry and staff flags |
| `endpoints` | `api`, `proxy`, `telemetry`, `origin-tracker`, `exp` | Copilot service hosts |
| `id`, `login`, `analytics_tracking_id` | (scrubbed) | Account identifiers; deliberately not read |
| `organization_list`, `organization_login_list`, `enterprise_list` | `[]` | Org and enterprise seat sources; relevant for org-managed seats |

### Response headers

| Provider | Headers | Notes |
| --- | --- | --- |
| Copilot | `x-ratelimit-limit` 5000, `-remaining`, `-used`, `-reset`, `-resource: core` | GitHub REST API budget, not Copilot usage; useful only for diagnosing failed requests |
| Claude | `anthropic-organization-id`, `anthropic-workspace-id`, `request-id`, `cf-ray`, `server-timing` | Identifiers and diagnostics; no usage data |
| Codex | `x-oai-request-id`, `cf-ray`, `report-to`, `nel` | Identifiers and diagnostics; no usage data |
