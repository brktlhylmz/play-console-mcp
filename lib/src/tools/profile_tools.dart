import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

/// Profile management, credential/API diagnostics (`doctor`), and accessible app
/// discovery tools.
final class ProfileTools {
  ProfileTools({
    required PlayProfileStore profileStore,
    required PlayAuthProvider authProvider,
    required PlayApiClient apiClient,
  }) : _profileStore = profileStore,
       _authProvider = authProvider,
       _apiClient = apiClient;

  final PlayProfileStore _profileStore;
  final PlayAuthProvider _authProvider;
  final PlayApiClient _apiClient;

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'manage_play_profiles',
      description:
          'Lists, saves, removes, sets default Play Console profiles in ~/.config/play_console_mcp/config.json, or runs "doctor" to verify credentials and API permissions (Android Publisher, Play Developer Reporting, and optional GCS bucket).',
      annotations: const McpToolAnnotations(
        title: 'Manage Play Profiles & Doctor',
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>['list', 'save', 'set_default', 'remove', 'doctor'],
            'description': 'Profile or diagnostics action to execute.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description':
                'Profile ID to target (defaults to active default profile).',
          },
          'profile_id': <String, Object?>{
            'type': 'string',
            'description': 'Profile ID when saving/removing/setting default.',
          },
          'label': <String, Object?>{
            'type': 'string',
            'description': 'Human-readable label for the profile.',
          },
          'service_account_path': <String, Object?>{
            'type': 'string',
            'description':
                'Local path to the Google Cloud Service Account JSON key file.',
          },
          'default_package_name': <String, Object?>{
            'type': 'string',
            'description':
                'Default Android packageName (e.g. com.example.app).',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Optional package_name override for doctor check.',
          },
          'developer_id': <String, Object?>{
            'type': 'string',
            'description': 'Default Play Console Developer ID.',
          },
          'gcs_bucket_id': <String, Object?>{
            'type': 'string',
            'description':
                'Default Play GCS reports bucket (e.g. pubsite_prod_rev_0123456789).',
          },
          'bucket_name': <String, Object?>{
            'type': 'string',
            'description': 'Optional GCS bucket override for doctor check.',
          },
          'read_only': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, blocks all mutating API calls for this profile.',
          },
          'allow_production_writes': <String, Object?>{
            'type': 'boolean',
            'description':
                'When true, allows production track writes and destructive actions without per-call confirmation.',
          },
          'default_changes_not_sent_for_review': <String, Object?>{
            'type': 'boolean',
            'description':
                'Default value for edits.commit changesNotSentForReview.',
          },
          'make_default': <String, Object?>{
            'type': 'boolean',
            'description': 'Set saved profile as the default profile.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageProfiles,
    ),
    McpToolDefinition(
      name: 'list_accessible_apps',
      description:
          'Discovers all Google Play apps accessible to the configured credentials via Play Developer Reporting API (apps:search). Useful when package_name is unknown.',
      annotations: const McpToolAnnotations(
        title: 'List Accessible Play Apps',
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Maximum number of apps per page (default 50).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token from previous response.',
          },
        },
      },
      handler: _handleListAccessibleApps,
    ),
  ];

  Future<Object?> _handleManageProfiles(Map<String, Object?> args) async {
    final action = reqString(args, 'action');
    switch (action) {
      case 'list':
        final defaultId = _profileStore.getDefaultProfileId();
        final profiles = _profileStore.listProfiles();
        return <String, Object?>{
          'config_path': _profileStore.configFilePath,
          'default_profile_id': defaultId,
          'profiles': profiles.map((p) => p.toJson()).toList(growable: false),
        };

      case 'save':
        final id = optString(args, 'profile_id') ?? optString(args, 'profile');
        if (id == null) {
          throw ArgumentError(
            'Missing required "profile_id" for action "save".',
          );
        }
        final existing = _findOptionalProfile(id);
        final saved = _profileStore.saveProfile(
          PlayProfile(
            profileId: id,
            label: optString(args, 'label') ?? existing?.label ?? id,
            serviceAccountPath:
                optString(args, 'service_account_path') ??
                existing?.serviceAccountPath,
            defaultPackageName:
                optString(args, 'default_package_name') ??
                optString(args, 'package_name') ??
                existing?.defaultPackageName,
            developerId:
                optString(args, 'developer_id') ?? existing?.developerId,
            gcsBucketId:
                optString(args, 'gcs_bucket_id') ??
                optString(args, 'bucket_name') ??
                existing?.gcsBucketId,
            readOnly: optBool(args, 'read_only') ?? existing?.readOnly ?? false,
            allowProductionWrites:
                optBool(args, 'allow_production_writes') ??
                existing?.allowProductionWrites ??
                false,
            defaultChangesNotSentForReview:
                optBool(args, 'default_changes_not_sent_for_review') ??
                existing?.defaultChangesNotSentForReview ??
                false,
          ),
          makeDefault: optBool(args, 'make_default') ?? false,
        );
        return <String, Object?>{
          'saved': true,
          'default_profile_id': _profileStore.getDefaultProfileId(),
          'profile': saved.toJson(),
        };

      case 'set_default':
        final id = optString(args, 'profile_id') ?? optString(args, 'profile');
        if (id == null) {
          throw ArgumentError(
            'Missing required "profile_id" for action "set_default".',
          );
        }
        final updated = _profileStore.setDefaultProfile(id);
        return <String, Object?>{
          'default_profile_id': updated.profileId,
          'profile': updated.toJson(),
        };

      case 'remove':
        final id = optString(args, 'profile_id') ?? optString(args, 'profile');
        if (id == null) {
          throw ArgumentError(
            'Missing required "profile_id" for action "remove".',
          );
        }
        final removed = _profileStore.removeProfile(id);
        return <String, Object?>{
          'removed': removed,
          'profile_id': id,
          'default_profile_id': _profileStore.getDefaultProfileId(),
        };

      case 'doctor':
        final ctx = _profileStore.resolveContext(args);
        final packageName =
            optString(args, 'package_name') ?? ctx.defaultPackageName;
        final bucket =
            optString(args, 'bucket_name') ??
            optString(args, 'gcs_bucket_id') ??
            ctx.gcsBucketId;
        return runDoctor(ctx, packageName: packageName, bucketName: bucket);

      default:
        throw ArgumentError('Unsupported manage_play_profiles action: $action');
    }
  }

  PlayProfile? _findOptionalProfile(String id) {
    for (final p in _profileStore.listProfiles()) {
      if (p.profileId == id) return p;
    }
    return null;
  }

  /// Runs credential inspection and non-mutating API connectivity probes.
  Future<Map<String, Object?>> runDoctor(
    ResolvedPlayContext context, {
    String? packageName,
    String? bucketName,
  }) async {
    final inspection = _authProvider.inspectCredentials(context.credentials);
    final checks = <String, Object?>{'credentials': inspection.toJson()};

    var ok = inspection.error == null;

    // 1. Probe Play Developer Reporting API (apps:search)
    try {
      final reportingResp = await _apiClient.getJson(
        credentials: context.credentials,
        scopes: const <String>[PlayScopes.playDeveloperReporting],
        baseUrl: PlayApiEndpoints.developerReporting,
        path: '/apps:search',
        query: const <String, Object?>{'pageSize': 5},
      );
      final apps = tryAsJsonList(reportingResp['apps']) ?? const <Object?>[];
      checks['play_developer_reporting'] = <String, Object?>{
        'ok': true,
        'accessible_apps_sample_count': apps.length,
        'sample_apps': apps,
      };
    } on Object catch (e) {
      ok = false;
      checks['play_developer_reporting'] = <String, Object?>{
        'ok': false,
        'error': e.toString(),
      };
    }

    // 2. Probe Android Publisher API v3 if a package_name is known.
    if (packageName != null && packageName.isNotEmpty) {
      try {
        final encodedPkg = Uri.encodeComponent(packageName);
        final releasesResp = await _apiClient.getJson(
          credentials: context.credentials,
          scopes: const <String>[PlayScopes.androidPublisher],
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/tracks/production/releases',
        );
        checks['android_publisher'] = <String, Object?>{
          'ok': true,
          'package_name': packageName,
          'production_releases_count':
              (tryAsJsonList(releasesResp['releases']) ?? const <Object?>[])
                  .length,
        };
      } on Object catch (e) {
        ok = false;
        checks['android_publisher'] = <String, Object?>{
          'ok': false,
          'package_name': packageName,
          'error': e.toString(),
        };
      }
    } else {
      checks['android_publisher'] = <String, Object?>{
        'skipped': true,
        'reason':
            'No package_name provided or configured in profile / PLAY_CONSOLE_DEFAULT_PACKAGE.',
      };
    }

    // 3. Probe Cloud Storage bucket if configured.
    if (bucketName != null && bucketName.isNotEmpty) {
      final normalizedBucket = bucketName.startsWith('gs://')
          ? bucketName.substring(5)
          : bucketName;
      try {
        final encodedBucket = Uri.encodeComponent(normalizedBucket);
        final gcsResp = await _apiClient.getJson(
          credentials: context.credentials,
          scopes: const <String>[PlayScopes.devStorageReadOnly],
          baseUrl: PlayApiEndpoints.cloudStorage,
          path: '/b/$encodedBucket/o',
          query: const <String, Object?>{'maxResults': 5},
        );
        final items = tryAsJsonList(gcsResp['items']) ?? const <Object?>[];
        checks['gcs_reports_bucket'] = <String, Object?>{
          'ok': true,
          'bucket': normalizedBucket,
          'sample_objects_count': items.length,
        };
      } on Object catch (e) {
        ok = false;
        checks['gcs_reports_bucket'] = <String, Object?>{
          'ok': false,
          'bucket': normalizedBucket,
          'error': e.toString(),
        };
      }
    } else {
      checks['gcs_reports_bucket'] = <String, Object?>{
        'skipped': true,
        'reason':
            'No gcs_bucket_id configured (optional; needed only for query_play_gcs_reports).',
      };
    }

    return <String, Object?>{
      'healthy': ok,
      'profile_id': context.profile?.profileId,
      'safety': <String, Object?>{
        'read_only': context.readOnly,
        'allow_production_writes': context.allowProductionWrites,
        'default_changes_not_sent_for_review':
            context.defaultChangesNotSentForReview,
      },
      'checks': checks,
    };
  }

  Future<Object?> _handleListAccessibleApps(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final pageSize = optInt(args, 'page_size') ?? 50;
    final pageToken = optString(args, 'page_token');
    return _apiClient.getJson(
      credentials: ctx.credentials,
      scopes: const <String>[PlayScopes.playDeveloperReporting],
      baseUrl: PlayApiEndpoints.developerReporting,
      path: '/apps:search',
      query: <String, Object?>{
        'pageSize': pageSize,
        if (pageToken != null) 'pageToken': pageToken,
      },
    );
  }
}
