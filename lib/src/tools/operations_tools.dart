import 'dart:io';

import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../services/edits_service.dart';
import '../utils/json_helpers.dart';

/// Operational Play Console tools: App Recovery actions, Data Safety CSV &
/// Device Tier Configs, and Track Testers / Developer Account Team & Grants.
final class OperationsTools {
  OperationsTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
    required EditsService editsService,
  }) : _profileStore = profileStore,
       _apiClient = apiClient,
       _editsService = editsService;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;
  final EditsService _editsService;

  static const List<String> _scopes = <String>[PlayScopes.androidPublisher];

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'manage_app_recovery',
      description:
          'Manages Google Play App Recovery actions (list, create draft, add_targeting, deploy, cancel) to prompt impacted users on broken versions to update.',
      annotations: const McpToolAnnotations(
        title: 'Manage App Recovery Actions',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'list',
              'create',
              'add_targeting',
              'deploy',
              'cancel',
            ],
            'description': 'App recovery action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'version_code': <String, Object?>{
            'type': 'integer',
            'description': 'For list: app versionCode filter.',
          },
          'app_recovery_id': <String, Object?>{
            'type': 'string',
            'description': 'App recovery action ID.',
          },
          'targeting': <String, Object?>{
            'type': 'object',
            'description':
                'Targeting payload (versionList, versionRange, allUsers, androidSdks, regions).',
          },
          'is_remote_in_app_update_requested': <String, Object?>{
            'type': 'boolean',
            'description':
                'For create: prompt users via Play Remote In-App Update.',
          },
          'confirm_production': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for deploy when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageAppRecovery,
    ),
    McpToolDefinition(
      name: 'manage_compliance_and_targeting',
      description:
          'Uploads Data Safety CSV declarations (applications.dataSafety) and manages Device Tier Configurations (list, get, create).',
      annotations: const McpToolAnnotations(
        title: 'Manage Data Safety & Device Tiers',
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
            'enum': <String>[
              'upload_data_safety_csv',
              'list_device_tier_configs',
              'get_device_tier_config',
              'create_device_tier_config',
            ],
            'description': 'Compliance or device-tier action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'csv_content': <String, Object?>{
            'type': 'string',
            'description': 'Inline Data Safety CSV string.',
          },
          'csv_file_path': <String, Object?>{
            'type': 'string',
            'description': 'Local path to Data Safety CSV file.',
          },
          'device_tier_config_id': <String, Object?>{
            'type': 'string',
            'description': 'Target deviceTierConfigId for get.',
          },
          'device_tier_config': <String, Object?>{
            'type': 'object',
            'description':
                'DeviceTierConfig object for create_device_tier_config.',
          },
          'allow_unknown_devices': <String, Object?>{
            'type': 'boolean',
            'description': 'Optional allowUnknownDevices flag on create.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size for list_device_tier_configs.',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token for list_device_tier_configs.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageComplianceAndTargeting,
    ),
    McpToolDefinition(
      name: 'manage_testers_and_team',
      description:
          'Manages track tester Google Groups (get_testers, update_testers) and Play Console developer account users and per-app grants (list/create/patch/delete).',
      annotations: const McpToolAnnotations(
        title: 'Manage Testers & Team Permissions',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'get_testers',
              'update_testers',
              'list_users',
              'create_user',
              'patch_user',
              'delete_user',
              'create_grant',
              'patch_grant',
              'delete_grant',
            ],
            'description': 'Tester or developer team management action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description':
                'Android packageName (for tester actions and grant actions).',
          },
          'track': <String, Object?>{
            'type': 'string',
            'description':
                'Target track for tester actions (e.g. alpha, beta).',
          },
          'google_groups': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                'Google Group email addresses for update_testers (Play API does not support individual emails here).',
          },
          'developer_id': <String, Object?>{
            'type': 'string',
            'description':
                'Play Console developer account ID (falls back to profile/env).',
          },
          'user_email': <String, Object?>{
            'type': 'string',
            'description': 'Target team user email address.',
          },
          'user': <String, Object?>{
            'type': 'object',
            'description': 'User object for create_user / patch_user.',
          },
          'grant': <String, Object?>{
            'type': 'object',
            'description': 'Grant object for create_grant / patch_grant.',
          },
          'update_mask': <String, Object?>{
            'type': 'string',
            'description': 'Optional updateMask for patch_user / patch_grant.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size for list_users.',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token for list_users.',
          },
          'edit_id': <String, Object?>{
            'type': 'string',
            'description': 'Optional open edit_id for tester actions.',
          },
          'dry_run': <String, Object?>{
            'type': 'boolean',
            'description':
                'Validate and discard tester edit without committing.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for delete_user / delete_grant when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageTestersAndTeam,
    ),
  ];

  Future<Object?> _handleManageAppRecovery(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final confirmed =
        (optBool(args, 'confirm_production') ?? false) ||
        (optBool(args, 'confirm_destructive') ?? false);

    switch (action) {
      case 'list':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/appRecoveries',
          query: <String, Object?>{
            if (optInt(args, 'version_code') case final vc?) 'versionCode': vc,
          },
        );

      case 'create':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'apprecovery.create ($packageName)',
        );
        final targeting = optJsonMap(args, 'targeting');
        if (targeting == null) {
          throw ArgumentError(
            'Missing required "targeting" object for create.',
          );
        }
        final remoteUpdate =
            optBool(args, 'is_remote_in_app_update_requested') ?? true;
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/appRecoveries',
          body: <String, Object?>{
            'targeting': targeting,
            'remoteInAppUpdate': <String, Object?>{
              'isRemoteInAppUpdateRequested': remoteUpdate,
            },
          },
        );

      case 'add_targeting':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'apprecovery.addTargeting ($packageName)',
        );
        final recoveryId = Uri.encodeComponent(
          reqString(args, 'app_recovery_id'),
        );
        final targeting = optJsonMap(args, 'targeting');
        if (targeting == null) {
          throw ArgumentError(
            'Missing required "targeting" object for add_targeting.',
          );
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/appRecoveries/$recoveryId:addTargeting',
          body: <String, Object?>{'targetingUpdate': targeting},
        );

      case 'deploy':
        final recoveryId = reqString(args, 'app_recovery_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'apprecovery.deploy ($packageName / $recoveryId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/appRecoveries/${Uri.encodeComponent(recoveryId)}:deploy',
          body: const <String, Object?>{},
        );

      case 'cancel':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'apprecovery.cancel ($packageName)',
        );
        final recoveryId = Uri.encodeComponent(
          reqString(args, 'app_recovery_id'),
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/appRecoveries/$recoveryId:cancel',
          body: const <String, Object?>{},
        );

      default:
        throw ArgumentError('Unsupported manage_app_recovery action: $action');
    }
  }

  Future<Object?> _handleManageComplianceAndTargeting(
    Map<String, Object?> args,
  ) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');

    switch (action) {
      case 'upload_data_safety_csv':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'applications.dataSafety ($packageName)',
        );
        var csv = optRawString(args, 'csv_content');
        final filePath = optString(args, 'csv_file_path');
        if ((csv == null || csv.trim().isEmpty) && filePath != null) {
          final file = File(filePath);
          if (!file.existsSync()) {
            throw FileSystemException(
              'Data safety CSV file not found.',
              filePath,
            );
          }
          csv = file.readAsStringSync();
        }
        if (csv == null || csv.trim().isEmpty) {
          throw ArgumentError(
            'Provide either "csv_content" or "csv_file_path" for upload_data_safety_csv.',
          );
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/dataSafety',
          body: <String, Object?>{'safetyLabels': csv},
        );

      case 'list_device_tier_configs':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/deviceTierConfigs',
          query: <String, Object?>{
            'pageSize': optInt(args, 'page_size') ?? 50,
            if (optString(args, 'page_token') case final t?) 'pageToken': t,
          },
        );

      case 'get_device_tier_config':
        final configId = Uri.encodeComponent(
          reqString(args, 'device_tier_config_id'),
        );
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/deviceTierConfigs/$configId',
        );

      case 'create_device_tier_config':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'applications.deviceTierConfigs.create ($packageName)',
        );
        final config = optJsonMap(args, 'device_tier_config');
        if (config == null) {
          throw ArgumentError('Missing required "device_tier_config" object.');
        }
        final allowUnknown = optBool(args, 'allow_unknown_devices');
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/deviceTierConfigs',
          query: <String, Object?>{
            if (allowUnknown != null) 'allowUnknownDevices': allowUnknown,
          },
          body: config,
        );

      default:
        throw ArgumentError(
          'Unsupported manage_compliance_and_targeting action: $action',
        );
    }
  }

  Future<Object?> _handleManageTestersAndTeam(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final action = reqString(args, 'action');
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);

    switch (action) {
      case 'get_testers':
        final packageName = ctx.requirePackageName(args);
        final encodedPkg = Uri.encodeComponent(packageName);
        final track = reqString(args, 'track');
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: optString(args, 'edit_id'),
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/testers/${Uri.encodeComponent(track)}',
          ),
        );

      case 'update_testers':
        final packageName = ctx.requirePackageName(args);
        final encodedPkg = Uri.encodeComponent(packageName);
        final track = reqString(args, 'track');
        final groups = optStringList(args, 'google_groups');
        if (groups == null) {
          throw ArgumentError(
            'Missing required "google_groups" array for update_testers.',
          );
        }
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.testers.update ($track)',
          editId: optString(args, 'edit_id'),
          dryRun: optBool(args, 'dry_run') ?? false,
          action: (activeId) => _apiClient.putJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/testers/${Uri.encodeComponent(track)}',
            body: <String, Object?>{'googleGroups': groups},
          ),
        );
        return exec.toJson();

      case 'list_users':
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/developers/$devId/users',
          query: <String, Object?>{
            'pageSize': optInt(args, 'page_size') ?? 50,
            if (optString(args, 'page_token') case final pt?) 'pageToken': pt,
          },
        );

      case 'create_user':
        SafetyGuard.checkWrite(context: ctx, operation: 'users.create');
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        final userBody = optJsonMap(args, 'user');
        if (userBody == null) {
          throw ArgumentError('Missing required "user" object.');
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/developers/$devId/users',
          body: userBody,
        );

      case 'patch_user':
        SafetyGuard.checkWrite(context: ctx, operation: 'users.patch');
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        final email = Uri.encodeComponent(reqString(args, 'user_email'));
        final userBody = optJsonMap(args, 'user');
        if (userBody == null) {
          throw ArgumentError('Missing required "user" object.');
        }
        return _apiClient.patchJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/developers/$devId/users/$email',
          query: <String, Object?>{
            if (optString(args, 'update_mask') case final mask?)
              'updateMask': mask,
          },
          body: userBody,
        );

      case 'delete_user':
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        final email = reqString(args, 'user_email');
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'users.delete ($email)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.deleteJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/developers/$devId/users/${Uri.encodeComponent(email)}',
        );

      case 'create_grant':
        SafetyGuard.checkWrite(context: ctx, operation: 'grants.create');
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        final email = Uri.encodeComponent(reqString(args, 'user_email'));
        final grantBody = optJsonMap(args, 'grant');
        if (grantBody == null) {
          throw ArgumentError('Missing required "grant" object.');
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/developers/$devId/users/$email/grants',
          body: grantBody,
        );

      case 'patch_grant':
        SafetyGuard.checkWrite(context: ctx, operation: 'grants.patch');
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        final email = Uri.encodeComponent(reqString(args, 'user_email'));
        final pkgGrant = Uri.encodeComponent(ctx.requirePackageName(args));
        final grantBody = optJsonMap(args, 'grant');
        if (grantBody == null) {
          throw ArgumentError('Missing required "grant" object.');
        }
        return _apiClient.patchJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/developers/$devId/users/$email/grants/$pkgGrant',
          query: <String, Object?>{
            if (optString(args, 'update_mask') case final mask?)
              'updateMask': mask,
          },
          body: grantBody,
        );

      case 'delete_grant':
        final devId = Uri.encodeComponent(ctx.requireDeveloperId(args));
        final email = reqString(args, 'user_email');
        final pkgGrant = ctx.requirePackageName(args);
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'grants.delete ($email -> $pkgGrant)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.deleteJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/developers/$devId/users/${Uri.encodeComponent(email)}/grants/${Uri.encodeComponent(pkgGrant)}',
        );

      default:
        throw ArgumentError(
          'Unsupported manage_testers_and_team action: $action',
        );
    }
  }
}
