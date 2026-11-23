import 'package:http/http.dart' as http;

import 'src/auth/play_auth_provider.dart';
import 'src/config/profile_store.dart';
import 'src/http/play_api_client.dart';
import 'src/mcp/mcp_server.dart';
import 'src/mcp/mcp_types.dart';
import 'src/prompts/play_prompts.dart';
import 'src/services/edits_service.dart';
import 'src/tools/edit_session_tools.dart';
import 'src/tools/gcs_reports_tools.dart';
import 'src/tools/monetization_tools.dart';
import 'src/tools/operations_tools.dart';
import 'src/tools/profile_tools.dart';
import 'src/tools/purchase_order_tools.dart';
import 'src/tools/release_tools.dart';
import 'src/tools/review_tools.dart';
import 'src/tools/store_listing_tools.dart';
import 'src/tools/vitals_tools.dart';

export 'src/auth/play_auth_provider.dart';
export 'src/config/profile_store.dart';
export 'src/config/safety_guard.dart';
export 'src/http/play_api_client.dart';
export 'src/mcp/mcp_server.dart';
export 'src/mcp/mcp_types.dart';
export 'src/prompts/play_prompts.dart';
export 'src/services/edits_service.dart';
export 'src/tools/edit_session_tools.dart';
export 'src/tools/gcs_reports_tools.dart';
export 'src/tools/monetization_tools.dart';
export 'src/tools/operations_tools.dart';
export 'src/tools/profile_tools.dart';
export 'src/tools/purchase_order_tools.dart';
export 'src/tools/release_tools.dart';
export 'src/tools/review_tools.dart';
export 'src/tools/store_listing_tools.dart';
export 'src/tools/vitals_tools.dart';
export 'src/utils/json_helpers.dart';

/// Semantic version of `play_console_mcp`.
const String playConsoleMcpVersion = '0.1.0';

/// Server-level MCP `InitializeResult.instructions` injected into AI clients.
const String playConsoleMcpInstructions =
    'GOOGLE PLAY CONSOLE MCP RULES: '
    '1) Start with `manage_play_profiles` (action: "doctor") or `list_accessible_apps` if credentials or package_name are unverified. '
    '2) Production track mutations, refunds, subscription cancellations/revocations, user/grant deletions, and app recovery deployments are protected by SafetyGuard (`allow_production_writes` defaults to false; use `dry_run: true` to validate edits or pass `confirm_production`/`confirm_destructive: true` after explicit user confirmation). '
    '3) `get_reviews` returns only the last 7 days of reviews; use `query_play_gcs_reports` for historical reviews, installs, ratings, sales, and earnings. '
    '4) Check `query_android_vitals` and `list_vitals_anomalies` before promoting builds to production.';

/// Canonical agent skill markdown installed optionally via `--install-skill`.
const String playConsoleAgentSkillMarkdown = '''---
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
''';

/// Wires configuration, authentication, Google API clients, 25 domain tools,
/// and 4 MCP prompts into a runnable [McpServer].
final class PlayConsoleMcpApp {
  PlayConsoleMcpApp({
    PlayProfileStore? profileStore,
    AuthClientFactory? authClientFactory,
    http.Client? mockHttpClient,
    DateTime Function()? clock,
  }) : profileStore = profileStore ?? PlayProfileStore(),
       authProvider = PlayAuthProvider(
         clientFactory:
             authClientFactory ??
             (mockHttpClient != null ? (_, _) async => mockHttpClient : null),
       ) {
    apiClient = PlayApiClient(authProvider);
    editsService = EditsService(apiClient);
    profileTools = ProfileTools(
      profileStore: this.profileStore,
      authProvider: authProvider,
      apiClient: apiClient,
    );

    final tools = <McpToolDefinition>[
      ...profileTools.definitions,
      ...EditSessionTools(
        profileStore: this.profileStore,
        editsService: editsService,
      ).definitions,
      ...ReleaseTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
        editsService: editsService,
      ).definitions,
      ...StoreListingTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
        editsService: editsService,
      ).definitions,
      ...ReviewTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
      ).definitions,
      ...VitalsTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
        clock: clock,
      ).definitions,
      ...MonetizationTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
      ).definitions,
      ...PurchaseOrderTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
      ).definitions,
      ...OperationsTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
        editsService: editsService,
      ).definitions,
      ...GcsReportsTools(
        profileStore: this.profileStore,
        apiClient: apiClient,
      ).definitions,
    ];

    server = McpServer(
      name: 'play-console-mcp',
      version: playConsoleMcpVersion,
      instructions: playConsoleMcpInstructions,
      tools: tools,
      prompts: buildPlayPrompts(),
    );
  }

  final PlayProfileStore profileStore;
  final PlayAuthProvider authProvider;
  late final PlayApiClient apiClient;
  late final EditsService editsService;
  late final ProfileTools profileTools;
  late final McpServer server;

  /// Closes cached authenticated HTTP clients.
  void close() {
    authProvider.close();
  }
}
