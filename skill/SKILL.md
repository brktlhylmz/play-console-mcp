---
name: play-console-mcp
description: >-
  Use when managing Google Play Console releases, staged rollouts, store listings,
  user reviews, Android Vitals crash/ANR metrics, subscriptions, one-time products,
  purchases, orders/refunds, app recovery, or Play GCS CSV reports via the
  play-console-mcp server.
---

# Google Play Console MCP Workflow

When interacting with Google Play Console through `play-console-mcp`:

1. **Always Discover & Diagnose First:**
   - Call `manage_play_profiles` (`action: "doctor"`) or `list_accessible_apps` if the target `package_name` or profile permissions are uncertain.
2. **Respect Production Safety Guards:**
   - By default, `allow_production_writes` is `false`. Test destructive or production track changes with `dry_run: true` first, and consider `changes_not_sent_for_review: true` when staging changes if a recent policy rejection occurred or manual Play Console sign-off is desired.
   - Keep `changes_in_review_behavior: "ERROR_IF_IN_REVIEW"` (default) unless intentionally replacing an active in-review submission.
3. **Use Atomic Edits or Explicit Sessions:**
   - Single-step tools (`manage_track_release`, `manage_store_listings`, `manage_store_images`, `manage_app_details`, `upload_app_artifact`) automatically manage an edit transaction when `edit_id` is omitted.
   - When combining multiple changes (for example: upload `.aab` + upload `mapping.txt` + update `internal` track + update `en-US` release notes) into one atomic submission, call `manage_edit_session` (`create`), pass `edit_id` to each step, call `validate`, and then `commit`.
4. **Know API Boundaries & Modern Endpoints:**
   - **Reviews (`get_reviews`)** only return comments created or modified within the last 7 days. For historical reviews, installs, ratings, sales, and earnings, use `query_play_gcs_reports`.
   - **One-Time Products (`manage_one_time_products`)** defaults to Google's modern `oneTimeProducts` API (`purchaseOptions` & `offers`); legacy `inappproducts` is available as read-only fallback (`legacy_list` / `legacy_get`).
   - **Android Vitals (`query_android_vitals`, `search_error_issues_and_reports`, `list_vitals_anomalies`)** uses the Play Developer Reporting API (`v1beta1`). Always check vitals before promoting a release to `production`.
