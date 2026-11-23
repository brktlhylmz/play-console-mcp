import 'dart:io';

import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../services/edits_service.dart';
import '../utils/json_helpers.dart';

/// Release, track, staged rollout, artifact upload, and generated/system APK
/// tools built on Android Publisher v3 and Play Reporting release filters.
final class ReleaseTools {
  ReleaseTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
    required EditsService editsService,
  }) : _profileStore = profileStore,
       _apiClient = apiClient,
       _editsService = editsService;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;
  final EditsService _editsService;

  static const List<String> _publisherScopes = <String>[
    PlayScopes.androidPublisher,
  ];

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'list_tracks_and_releases',
      description:
          'Reads Play Console release tracks, active/draft releases, country availability, or Reporting API release filter options.',
      annotations: const McpToolAnnotations(
        title: 'List Tracks & Releases',
        readOnlyHint: true,
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
              'list_tracks',
              'get_track',
              'list_releases',
              'country_availability',
              'release_filter_options',
            ],
            'description': 'Inspection action to execute.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'track': <String, Object?>{
            'type': 'string',
            'description':
                'Track name (e.g. internal, alpha, beta, production, or custom closed track).',
          },
          'edit_id': <String, Object?>{
            'type': 'string',
            'description': 'Optional open edit_id to inspect staged changes.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleListTracksAndReleases,
    ),
    McpToolDefinition(
      name: 'manage_track_release',
      description:
          'Creates tracks, updates track releases, promotes builds across tracks, updates staged rollout percentages, halts, resumes, or completes rollouts. Production writes are protected by SafetyGuard and support dry_run and changes_not_sent_for_review.',
      annotations: const McpToolAnnotations(
        title: 'Manage Track & Release Rollout',
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
              'create_track',
              'update_track',
              'promote_release',
              'update_rollout',
              'halt_rollout',
              'resume_rollout',
              'complete_rollout',
            ],
            'description': 'Track or rollout operation to perform.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'track': <String, Object?>{
            'type': 'string',
            'description':
                'Target track (e.g. internal, alpha, beta, production).',
          },
          'source_track': <String, Object?>{
            'type': 'string',
            'description': 'Source track for promote_release.',
          },
          'target_track': <String, Object?>{
            'type': 'string',
            'description':
                'Destination track for promote_release (overrides track).',
          },
          'track_type': <String, Object?>{
            'type': 'string',
            'description':
                'For create_track: track type (e.g. CLOSED_TESTING).',
          },
          'form_factor': <String, Object?>{
            'type': 'string',
            'description':
                'For create_track: formFactor (e.g. DEFAULT, WEAR, TV, AUTOMOTIVE).',
          },
          'version_codes': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'integer'},
            'description': 'Version codes to include in the release.',
          },
          'release_name': <String, Object?>{
            'type': 'string',
            'description': 'Human-readable release name in Play Console.',
          },
          'status': <String, Object?>{
            'type': 'string',
            'enum': <String>['draft', 'inProgress', 'halted', 'completed'],
            'description': 'Release rollout status.',
          },
          'user_fraction': <String, Object?>{
            'type': 'number',
            'description':
                'Staged rollout fraction between 0.0 and 1.0 (exclusive, e.g. 0.1 for 10%).',
          },
          'in_app_update_priority': <String, Object?>{
            'type': 'integer',
            'description': 'Google Play In-App Update priority (0 to 5).',
          },
          'release_notes': <String, Object?>{
            'type': 'object',
            'additionalProperties': <String, Object?>{'type': 'string'},
            'description':
                'Map of BCP-47 locale -> localized "What\'s new" text (max 500 chars each), e.g. {"en-US": "Bug fixes", "tr-TR": "Hata düzeltmeleri"}.',
          },
          'country_targeting': <String, Object?>{
            'type': 'object',
            'description':
                'Optional CountryTargeting object {countries: [...], includeRestOfWorld: bool}.',
          },
          'releases': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'object'},
            'description':
                'Optional full TrackRelease[] override for update_track.',
          },
          'edit_id': <String, Object?>{
            'type': 'string',
            'description': 'Optional existing edit_id to stage changes into.',
          },
          'dry_run': <String, Object?>{
            'type': 'boolean',
            'description':
                'Validate edit changes and discard without committing.',
          },
          'changes_not_sent_for_review': <String, Object?>{
            'type': 'boolean',
            'description':
                'Commit changes into Publishing Overview without submitting for review automatically.',
          },
          'changes_in_review_behavior': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'ERROR_IF_IN_REVIEW',
              'CANCEL_IN_REVIEW_AND_SUBMIT',
            ],
            'description': 'Behavior when an active review already exists.',
          },
          'confirm_production': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required when targeting production while allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageTrackRelease,
    ),
    McpToolDefinition(
      name: 'upload_app_artifact',
      description:
          'Uploads Android App Bundles (.aab), APKs, ProGuard/native deobfuscation files, or Internal App Sharing artifacts via Google Resumable Media Upload, or lists uploaded bundles/APKs in an edit.',
      annotations: const McpToolAnnotations(
        title: 'Upload / List App Artifacts',
        readOnlyHint: false,
        destructiveHint: false,
        idempotentHint: false,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'upload_bundle',
              'upload_apk',
              'upload_deobfuscation',
              'upload_internal_sharing',
              'list_bundles',
              'list_apks',
            ],
            'description': 'Artifact action to perform.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'file_path': <String, Object?>{
            'type': 'string',
            'description':
                'Local path to .aab, .apk, mapping.txt, or native-debug-symbols.zip.',
          },
          'apk_version_code': <String, Object?>{
            'type': 'integer',
            'description':
                'Required for upload_deobfuscation: target versionCode.',
          },
          'deobfuscation_file_type': <String, Object?>{
            'type': 'string',
            'enum': <String>['proguard', 'nativeCode'],
            'description': 'Required for upload_deobfuscation.',
          },
          'artifact_type': <String, Object?>{
            'type': 'string',
            'enum': <String>['bundle', 'apk'],
            'description':
                'For upload_internal_sharing: whether file_path is a bundle (.aab) or apk.',
          },
          'ack_bundle_installation_warning': <String, Object?>{
            'type': 'boolean',
            'description':
                'Acknowledge Play bundle installation size warning if applicable.',
          },
          'device_tier_config_id': <String, Object?>{
            'type': 'string',
            'description':
                'Optional device tier config ID when uploading a bundle.',
          },
          'edit_id': <String, Object?>{
            'type': 'string',
            'description': 'Optional open edit_id.',
          },
          'dry_run': <String, Object?>{
            'type': 'boolean',
            'description': 'Validate and discard edit without committing.',
          },
          'changes_not_sent_for_review': <String, Object?>{
            'type': 'boolean',
            'description': 'Hold committed edit before sending to review.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleUploadAppArtifact,
    ),
    McpToolDefinition(
      name: 'manage_generated_and_system_apks',
      description:
          'Lists or downloads signed APKs generated from an App Bundle, and lists, creates, or downloads OEM System APK variants.',
      annotations: const McpToolAnnotations(
        title: 'Generated & System APKs',
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
              'list_generated',
              'download_generated',
              'list_system_variants',
              'create_system_variant',
              'download_system_variant',
            ],
            'description': 'Generated/System APK action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'version_code': <String, Object?>{
            'type': 'integer',
            'description': 'App bundle versionCode.',
          },
          'download_id': <String, Object?>{
            'type': 'string',
            'description':
                'For download_generated: downloadId from list_generated.',
          },
          'variant_id': <String, Object?>{
            'type': 'integer',
            'description': 'For download_system_variant: variantId.',
          },
          'output_path': <String, Object?>{
            'type': 'string',
            'description': 'Local destination file path for downloaded APK.',
          },
          'device_spec': <String, Object?>{
            'type': 'object',
            'description':
                'For create_system_variant: DeviceSpec {supportedAbis, supportedLocales, screenDensity}.',
          },
          'options': <String, Object?>{
            'type': 'object',
            'description':
                'For create_system_variant: SystemApkOptions {uncompressedNativeLibraries, uncompressedDexFiles, rotated}.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action', 'version_code'],
      },
      handler: _handleGeneratedAndSystemApks,
    ),
  ];

  Future<Object?> _handleListTracksAndReleases(
    Map<String, Object?> args,
  ) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final editId = optString(args, 'edit_id');

    switch (action) {
      case 'list_tracks':
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/tracks',
          ),
        );

      case 'get_track':
        final track = reqString(args, 'track');
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/tracks/${Uri.encodeComponent(track)}',
          ),
        );

      case 'list_releases':
        final track = optString(args, 'track') ?? 'production';
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/tracks/${Uri.encodeComponent(track)}/releases',
        );

      case 'country_availability':
        final track = optString(args, 'track') ?? 'production';
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/countryAvailability/${Uri.encodeComponent(track)}',
          ),
        );

      case 'release_filter_options':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: const <String>[PlayScopes.playDeveloperReporting],
          baseUrl: PlayApiEndpoints.developerReporting,
          path: '/apps/$encodedPkg:fetchReleaseFilterOptions',
        );

      default:
        throw ArgumentError(
          'Unsupported list_tracks_and_releases action: $action',
        );
    }
  }

  Future<Object?> _handleManageTrackRelease(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final editId = optString(args, 'edit_id');
    final dryRun = optBool(args, 'dry_run') ?? false;
    final changesNotSentForReview = optBool(
      args,
      'changes_not_sent_for_review',
    );
    final changesInReviewBehavior = optString(
      args,
      'changes_in_review_behavior',
    );
    final confirmProd =
        (optBool(args, 'confirm_production') ?? false) ||
        (optBool(args, 'confirm_destructive') ?? false);

    switch (action) {
      case 'create_track':
        final track = reqString(args, 'track');
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.tracks.create ($track)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          changesInReviewBehavior: changesInReviewBehavior,
          isProductionOrDestructive: track == 'production',
          confirmed: confirmProd,
          action: (activeId) {
            return _apiClient.postJson(
              credentials: ctx.credentials,
              scopes: _publisherScopes,
              baseUrl: PlayApiEndpoints.androidPublisher,
              path:
                  '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/tracks',
              body: <String, Object?>{
                'track': track,
                if (optString(args, 'form_factor') case final ff?)
                  'formFactor': ff,
                if (optString(args, 'track_type') case final tt?) 'type': tt,
              },
            );
          },
        );
        return exec.toJson();

      case 'update_track':
        final track = reqString(args, 'track');
        final explicitReleases = tryAsJsonList(args['releases']);
        final List<Map<String, Object?>> releasesPayload;
        if (explicitReleases != null) {
          releasesPayload = explicitReleases
              .map((r) => asJsonMap(r, fieldName: 'releases[]'))
              .toList(growable: false);
        } else {
          releasesPayload = <Map<String, Object?>>[_buildReleasePayload(args)];
        }
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.tracks.update ($track)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          changesInReviewBehavior: changesInReviewBehavior,
          isProductionOrDestructive: track == 'production',
          confirmed: confirmProd,
          action: (activeId) => _putTrack(
            ctx: ctx,
            encodedPkg: encodedPkg,
            editId: activeId,
            track: track,
            releases: releasesPayload,
          ),
        );
        return exec.toJson();

      case 'promote_release':
        final sourceTrack = reqString(args, 'source_track');
        final targetTrack =
            optString(args, 'target_track') ?? reqString(args, 'track');
        final requestedVersionCodes = optIntList(args, 'version_codes');
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'promote_release ($sourceTrack -> $targetTrack)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          changesInReviewBehavior: changesInReviewBehavior,
          isProductionOrDestructive: targetTrack == 'production',
          confirmed: confirmProd,
          action: (activeId) async {
            final srcData = await _getTrack(
              ctx: ctx,
              encodedPkg: encodedPkg,
              editId: activeId,
              track: sourceTrack,
            );
            final srcReleases =
                tryAsJsonList(srcData['releases']) ?? const <Object?>[];
            if (srcReleases.isEmpty) {
              throw StateError(
                'Source track "$sourceTrack" has no releases to promote.',
              );
            }
            Map<String, Object?>? chosen;
            for (final item in srcReleases) {
              final map = tryAsJsonMap(item);
              if (map == null) continue;
              if (requestedVersionCodes == null ||
                  requestedVersionCodes.isEmpty) {
                chosen = map;
                break;
              }
              final vcs = _parseVersionCodes(map['versionCodes']);
              if (requestedVersionCodes.every(vcs.contains)) {
                chosen = map;
                break;
              }
            }
            if (chosen == null) {
              throw StateError(
                'No release matching version_codes $requestedVersionCodes found on "$sourceTrack".',
              );
            }

            final promoted = Map<String, Object?>.from(chosen);
            if (requestedVersionCodes != null &&
                requestedVersionCodes.isNotEmpty) {
              promoted['versionCodes'] = requestedVersionCodes
                  .map((v) => v.toString())
                  .toList(growable: false);
            }
            final status = optString(args, 'status');
            final userFraction = optDouble(args, 'user_fraction');
            if (status != null) {
              promoted['status'] = status;
            } else if (userFraction != null) {
              promoted['status'] = 'inProgress';
            } else if (promoted['status'] == 'draft') {
              promoted['status'] = 'completed';
            }

            if (promoted['status'] == 'inProgress') {
              if (userFraction != null) {
                _validateUserFraction(userFraction);
                promoted['userFraction'] = userFraction;
              } else if (promoted['userFraction'] == null) {
                throw ArgumentError(
                  'user_fraction (0 < f < 1) is required when promoting with status "inProgress".',
                );
              }
            } else {
              promoted.remove('userFraction');
            }

            if (optString(args, 'release_name') case final rn?) {
              promoted['name'] = rn;
            }
            if (optInt(args, 'in_app_update_priority') case final p?) {
              _validatePriority(p);
              promoted['inAppUpdatePriority'] = p;
            }
            final notesOverride = _parseReleaseNotes(args['release_notes']);
            if (notesOverride != null) {
              promoted['releaseNotes'] = notesOverride;
            }
            if (optJsonMap(args, 'country_targeting') case final ct?) {
              promoted['countryTargeting'] = ct;
            }

            return _putTrack(
              ctx: ctx,
              encodedPkg: encodedPkg,
              editId: activeId,
              track: targetTrack,
              releases: <Map<String, Object?>>[promoted],
            );
          },
        );
        return exec.toJson();

      case 'update_rollout':
      case 'halt_rollout':
      case 'resume_rollout':
      case 'complete_rollout':
        final track = optString(args, 'track') ?? 'production';
        final userFraction = optDouble(args, 'user_fraction');
        final targetVersionCodes = optIntList(args, 'version_codes');
        if (action == 'update_rollout') {
          if (userFraction == null) {
            throw ArgumentError(
              'Missing required "user_fraction" for update_rollout.',
            );
          }
          _validateUserFraction(userFraction);
        } else if (userFraction != null) {
          _validateUserFraction(userFraction);
        }

        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: '$action ($track)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          changesInReviewBehavior: changesInReviewBehavior,
          isProductionOrDestructive: track == 'production',
          confirmed: confirmProd,
          action: (activeId) async {
            final currentTrack = await _getTrack(
              ctx: ctx,
              encodedPkg: encodedPkg,
              editId: activeId,
              track: track,
            );
            final currentReleases =
                tryAsJsonList(currentTrack['releases']) ?? const <Object?>[];
            if (currentReleases.isEmpty) {
              throw StateError('Track "$track" has no releases.');
            }

            final updatedReleases = <Map<String, Object?>>[];
            var modified = false;
            for (final item in currentReleases) {
              final release = Map<String, Object?>.from(asJsonMap(item));
              final matchesVersion =
                  targetVersionCodes == null ||
                  targetVersionCodes.isEmpty ||
                  targetVersionCodes.every(
                    _parseVersionCodes(release['versionCodes']).contains,
                  );

              final currentStatus = optString(release, 'status');
              final shouldUpdate =
                  !modified &&
                  matchesVersion &&
                  switch (action) {
                    'update_rollout' =>
                      currentStatus == 'inProgress' ||
                          currentStatus == 'halted',
                    'halt_rollout' => currentStatus == 'inProgress',
                    'resume_rollout' => currentStatus == 'halted',
                    'complete_rollout' =>
                      currentStatus == 'inProgress' ||
                          currentStatus == 'halted',
                    _ => false,
                  };

              if (shouldUpdate) {
                modified = true;
                switch (action) {
                  case 'update_rollout':
                    release['status'] = 'inProgress';
                    release['userFraction'] = userFraction;
                  case 'halt_rollout':
                    release['status'] = 'halted';
                  case 'resume_rollout':
                    release['status'] = 'inProgress';
                    if (userFraction != null) {
                      release['userFraction'] = userFraction;
                    } else if (release['userFraction'] == null) {
                      throw StateError(
                        'Halted release does not carry a prior userFraction; supply user_fraction to resume.',
                      );
                    }
                  case 'complete_rollout':
                    release['status'] = 'completed';
                    release.remove('userFraction');
                }
              }
              updatedReleases.add(release);
            }

            if (!modified) {
              throw StateError(
                'No matching release found on track "$track" eligible for "$action".',
              );
            }

            return _putTrack(
              ctx: ctx,
              encodedPkg: encodedPkg,
              editId: activeId,
              track: track,
              releases: updatedReleases,
            );
          },
        );
        return exec.toJson();

      default:
        throw ArgumentError('Unsupported manage_track_release action: $action');
    }
  }

  Future<Map<String, Object?>> _getTrack({
    required ResolvedPlayContext ctx,
    required String encodedPkg,
    required String editId,
    required String track,
  }) {
    return _apiClient.getJson(
      credentials: ctx.credentials,
      scopes: _publisherScopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path:
          '/applications/$encodedPkg/edits/${Uri.encodeComponent(editId)}/tracks/${Uri.encodeComponent(track)}',
    );
  }

  Future<Map<String, Object?>> _putTrack({
    required ResolvedPlayContext ctx,
    required String encodedPkg,
    required String editId,
    required String track,
    required List<Map<String, Object?>> releases,
  }) {
    return _apiClient.putJson(
      credentials: ctx.credentials,
      scopes: _publisherScopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path:
          '/applications/$encodedPkg/edits/${Uri.encodeComponent(editId)}/tracks/${Uri.encodeComponent(track)}',
      body: <String, Object?>{'track': track, 'releases': releases},
    );
  }

  Map<String, Object?> _buildReleasePayload(Map<String, Object?> args) {
    final versionCodes = optIntList(args, 'version_codes');
    if (versionCodes == null || versionCodes.isEmpty) {
      throw ArgumentError(
        'Provide "version_codes" (or full "releases" array) for update_track.',
      );
    }
    final status = optString(args, 'status') ?? 'completed';
    final userFraction = optDouble(args, 'user_fraction');
    if (status == 'inProgress') {
      if (userFraction == null) {
        throw ArgumentError(
          'user_fraction is required when release status is "inProgress".',
        );
      }
      _validateUserFraction(userFraction);
    } else if (userFraction != null) {
      _validateUserFraction(userFraction);
    }

    final priority = optInt(args, 'in_app_update_priority');
    if (priority != null) _validatePriority(priority);
    final releaseNotes = _parseReleaseNotes(args['release_notes']);

    return <String, Object?>{
      'versionCodes': versionCodes.map((v) => v.toString()).toList(),
      'status': status,
      if (optString(args, 'release_name') case final name?) 'name': name,
      if (userFraction != null && status == 'inProgress')
        'userFraction': userFraction,
      if (priority != null) 'inAppUpdatePriority': priority,
      if (releaseNotes != null) 'releaseNotes': releaseNotes,
      if (optJsonMap(args, 'country_targeting') case final ct?)
        'countryTargeting': ct,
    };
  }

  List<Map<String, Object?>>? _parseReleaseNotes(Object? raw) {
    final map = tryAsJsonMap(raw);
    if (map == null) return null;
    final notes = <Map<String, Object?>>[];
    for (final entry in map.entries) {
      final text = entry.value?.toString() ?? '';
      if (text.length > 500) {
        throw ArgumentError(
          'Release note for "${entry.key}" exceeds Play Console 500-character limit (${text.length} chars).',
        );
      }
      notes.add(<String, Object?>{'language': entry.key, 'text': text});
    }
    return notes;
  }

  List<int> _parseVersionCodes(Object? raw) {
    final list = tryAsJsonList(raw) ?? const <Object?>[];
    final out = <int>[];
    for (final v in list) {
      if (v is int) {
        out.add(v);
      } else if (v is String) {
        final parsed = int.tryParse(v);
        if (parsed != null) out.add(parsed);
      }
    }
    return out;
  }

  void _validateUserFraction(double fraction) {
    if (fraction <= 0 || fraction >= 1) {
      throw ArgumentError.value(
        fraction,
        'user_fraction',
        'user_fraction must be strictly between 0.0 and 1.0 (e.g. 0.1 for 10%). Use complete_rollout for 100%.',
      );
    }
  }

  void _validatePriority(int priority) {
    if (priority < 0 || priority > 5) {
      throw ArgumentError.value(
        priority,
        'in_app_update_priority',
        'in_app_update_priority must be between 0 and 5.',
      );
    }
  }

  Future<Object?> _handleUploadAppArtifact(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final editId = optString(args, 'edit_id');
    final dryRun = optBool(args, 'dry_run') ?? false;
    final changesNotSentForReview = optBool(
      args,
      'changes_not_sent_for_review',
    );

    switch (action) {
      case 'list_bundles':
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/bundles',
          ),
        );

      case 'list_apks':
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/apks',
          ),
        );

      case 'upload_bundle':
        final file = _requireReadableFile(reqString(args, 'file_path'));
        final bytes = file.readAsBytesSync();
        final ackWarning = optBool(args, 'ack_bundle_installation_warning');
        final deviceTierId = optString(args, 'device_tier_config_id');
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.bundles.upload',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) => _apiClient.uploadMediaResumable(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            resumableBaseUrl: PlayApiEndpoints.androidPublisherResumable,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/bundles',
            bytes: bytes,
            query: <String, Object?>{
              if (ackWarning != null)
                'ackBundleInstallationWarning': ackWarning,
              if (deviceTierId != null) 'deviceTierConfigId': deviceTierId,
            },
          ),
        );
        return exec.toJson();

      case 'upload_apk':
        final file = _requireReadableFile(reqString(args, 'file_path'));
        final bytes = file.readAsBytesSync();
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.apks.upload',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) => _apiClient.uploadMediaResumable(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            resumableBaseUrl: PlayApiEndpoints.androidPublisherResumable,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/apks',
            bytes: bytes,
            contentType: 'application/vnd.android.package-archive',
          ),
        );
        return exec.toJson();

      case 'upload_deobfuscation':
        final file = _requireReadableFile(reqString(args, 'file_path'));
        final versionCode = reqInt(args, 'apk_version_code');
        final fileType = reqString(args, 'deobfuscation_file_type');
        final bytes = file.readAsBytesSync();
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.deobfuscationfiles.upload ($fileType)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) => _apiClient.uploadMediaResumable(
            credentials: ctx.credentials,
            scopes: _publisherScopes,
            resumableBaseUrl: PlayApiEndpoints.androidPublisherResumable,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/apks/$versionCode/deobfuscationFiles/${Uri.encodeComponent(fileType)}',
            bytes: bytes,
          ),
        );
        return exec.toJson();

      case 'upload_internal_sharing':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'internalappsharingartifacts.upload ($packageName)',
        );
        final filePath = reqString(args, 'file_path');
        final file = _requireReadableFile(filePath);
        final inferredType = filePath.toLowerCase().endsWith('.apk')
            ? 'apk'
            : 'bundle';
        final artifactType = optString(args, 'artifact_type') ?? inferredType;
        if (artifactType != 'bundle' && artifactType != 'apk') {
          throw ArgumentError(
            'artifact_type must be "bundle" or "apk" (got "$artifactType").',
          );
        }
        final bytes = file.readAsBytesSync();
        return _apiClient.uploadMediaResumable(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          resumableBaseUrl: PlayApiEndpoints.androidPublisherResumable,
          path:
              '/applications/internalappsharing/$encodedPkg/artifacts/$artifactType',
          bytes: bytes,
        );

      default:
        throw ArgumentError('Unsupported upload_app_artifact action: $action');
    }
  }

  Future<Object?> _handleGeneratedAndSystemApks(
    Map<String, Object?> args,
  ) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final versionCode = reqInt(args, 'version_code');

    switch (action) {
      case 'list_generated':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/generatedApks/$versionCode',
        );

      case 'download_generated':
        final downloadId = reqString(args, 'download_id');
        final outputPath = reqString(args, 'output_path');
        final bytes = await _apiClient.downloadBytes(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/generatedApks/$versionCode/downloads/${Uri.encodeComponent(downloadId)}:download',
          query: const <String, Object?>{'alt': 'media'},
        );
        _writeOutputFile(outputPath, bytes);
        return <String, Object?>{
          'downloaded': true,
          'output_path': outputPath,
          'bytes_written': bytes.length,
        };

      case 'list_system_variants':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/systemApks/$versionCode/variants',
        );

      case 'create_system_variant':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'systemapks.variants.create ($packageName)',
        );
        final deviceSpec = optJsonMap(args, 'device_spec');
        if (deviceSpec == null) {
          throw ArgumentError(
            'Missing required "device_spec" object for create_system_variant.',
          );
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/systemApks/$versionCode/variants',
          body: <String, Object?>{
            'deviceSpec': deviceSpec,
            if (optJsonMap(args, 'options') case final opts?) 'options': opts,
          },
        );

      case 'download_system_variant':
        final variantId = reqInt(args, 'variant_id');
        final outputPath = reqString(args, 'output_path');
        final bytes = await _apiClient.downloadBytes(
          credentials: ctx.credentials,
          scopes: _publisherScopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/systemApks/$versionCode/variants/$variantId:download',
          query: const <String, Object?>{'alt': 'media'},
        );
        _writeOutputFile(outputPath, bytes);
        return <String, Object?>{
          'downloaded': true,
          'output_path': outputPath,
          'bytes_written': bytes.length,
        };

      default:
        throw ArgumentError(
          'Unsupported manage_generated_and_system_apks action: $action',
        );
    }
  }

  File _requireReadableFile(String filePath) {
    final file = File(filePath);
    if (!file.existsSync()) {
      throw FileSystemException('File not found.', filePath);
    }
    return file;
  }

  void _writeOutputFile(String path, List<int> bytes) {
    final outFile = File(path);
    if (!outFile.parent.existsSync()) {
      outFile.parent.createSync(recursive: true);
    }
    outFile.writeAsBytesSync(bytes);
  }
}
