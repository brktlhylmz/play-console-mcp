import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

/// Built-in reusable MCP prompt templates for common Google Play Console
/// release, vitals triage, and review workflows.
List<McpPromptDefinition> buildPlayPrompts() => <McpPromptDefinition>[
  McpPromptDefinition(
    name: 'release_readiness_audit',
    description:
        'Audit track rollout state, Android Vitals stability, anomalies, and recent low-star reviews before shipping or promoting a release.',
    arguments: const <McpPromptArgument>[
      McpPromptArgument(
        name: 'package_name',
        description: 'Android packageName (e.g. com.example.app).',
        required: true,
      ),
      McpPromptArgument(
        name: 'track',
        description: 'Target track to audit (default production).',
      ),
    ],
    handler: (args) {
      final pkg = optString(args, 'package_name') ?? '<package_name>';
      final track = optString(args, 'track') ?? 'production';
      return McpPromptResult(
        description: 'Pre-release audit checklist for $pkg ($track)',
        messages: <McpPromptMessage>[
          McpPromptMessage(
            role: 'user',
            text:
                'Perform a release readiness audit for Google Play app "$pkg" on track "$track":\n'
                '1. Call `list_tracks_and_releases` (action: "list_tracks") to inspect current active/halted/draft releases.\n'
                '2. Call `list_vitals_anomalies` for "$pkg" to check for active spike alerts.\n'
                '3. Call `query_android_vitals` for `crash_rate`, `anr_rate`, and `lmk_rate` over the last 14 days.\n'
                '4. Call `get_reviews` (max_rating: 2, max_results: 20) to surface any recent severe user complaints.\n'
                'Summarize Go / No-Go recommendation with concrete metrics and blockers.',
          ),
        ],
      );
    },
  ),
  McpPromptDefinition(
    name: 'triage_crashes',
    description:
        'Fetch Play Developer Reporting anomalies and top crash/ANR error issues with stack traces and suggest fixes.',
    arguments: const <McpPromptArgument>[
      McpPromptArgument(
        name: 'package_name',
        description: 'Android packageName (e.g. com.example.app).',
        required: true,
      ),
      McpPromptArgument(
        name: 'version_code',
        description: 'Optional versionCode filter.',
      ),
    ],
    handler: (args) {
      final pkg = optString(args, 'package_name') ?? '<package_name>';
      final vc = optString(args, 'version_code');
      final filterHint = vc != null ? ' with filter "versionCode = $vc"' : '';
      return McpPromptResult(
        description: 'Crash and ANR triage workflow for $pkg',
        messages: <McpPromptMessage>[
          McpPromptMessage(
            role: 'user',
            text:
                'Triage production stability issues for "$pkg"$filterHint:\n'
                '1. Call `list_vitals_anomalies` for "$pkg".\n'
                '2. Call `search_error_issues_and_reports` (action: "search_issues", order_by: "errorReportCount desc", sample_error_report_limit: 2${vc != null ? ', filter: "versionCode = $vc"' : ''}).\n'
                '3. Group issues by severity (distinctUsers + errorReportCount), extract root-cause stack frames, and propose concrete code or App Recovery actions.',
          ),
        ],
      );
    },
  ),
  McpPromptDefinition(
    name: 'draft_review_replies',
    description:
        'Fetch unanswered recent Google Play user reviews and draft polite, 350-char-compliant responses for approval before posting.',
    arguments: const <McpPromptArgument>[
      McpPromptArgument(
        name: 'package_name',
        description: 'Android packageName (e.g. com.example.app).',
        required: true,
      ),
      McpPromptArgument(
        name: 'translation_language',
        description: 'Optional translation language (e.g. en).',
      ),
    ],
    handler: (args) {
      final pkg = optString(args, 'package_name') ?? '<package_name>';
      final lang = optString(args, 'translation_language');
      return McpPromptResult(
        description: 'Draft Play Store review replies for $pkg',
        messages: <McpPromptMessage>[
          McpPromptMessage(
            role: 'user',
            text:
                'Fetch unanswered recent reviews for "$pkg" using `get_reviews` (unanswered_only: true, max_results: 25${lang != null ? ', translation_language: "$lang"' : ''}).\n'
                'Draft a concise, empathetic, under-350-character reply in each reviewer\'s original language. Present the drafts in a table and ask for confirmation before calling `reply_to_review`.',
          ),
        ],
      );
    },
  ),
  McpPromptDefinition(
    name: 'prepare_release_notes',
    description:
        'Generate localized Play Store release notes (max 500 chars per locale) from a changelog summary.',
    arguments: const <McpPromptArgument>[
      McpPromptArgument(
        name: 'changes',
        description: 'Summary of bug fixes and new features in this release.',
        required: true,
      ),
      McpPromptArgument(
        name: 'locales',
        description:
            'Comma-separated BCP-47 locales (e.g. en-US,tr-TR,de-DE,ja-JP).',
      ),
    ],
    handler: (args) {
      final changes = optString(args, 'changes') ?? '<describe changes>';
      final locales = optString(args, 'locales') ?? 'en-US, tr-TR';
      return McpPromptResult(
        description: 'Prepare localized 500-char release notes',
        messages: <McpPromptMessage>[
          McpPromptMessage(
            role: 'user',
            text:
                'Generate user-friendly Google Play "What\'s new" release notes for locales [$locales] from these changes:\n'
                '$changes\n\n'
                'Requirements:\n'
                '- Strictly <= 500 characters per locale.\n'
                '- Output a JSON map ready to pass directly into `manage_track_release.release_notes`.',
          ),
        ],
      );
    },
  ),
];
