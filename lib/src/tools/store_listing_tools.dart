import 'dart:io';

import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../services/edits_service.dart';
import '../utils/json_helpers.dart';

/// Tools for managing Play Store app contact details, localized store listings
/// (with Fastlane metadata directory sync/export), and store graphics/screenshots.
final class StoreListingTools {
  StoreListingTools({
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
  static const int _maxTitleLength = 30;
  static const int _maxShortDescriptionLength = 80;
  static const int _maxFullDescriptionLength = 4000;

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'manage_app_details',
      description:
          'Reads or updates app-level contact details and defaultLanguage (edits.details).',
      annotations: const McpToolAnnotations(
        title: 'Manage App Details',
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
            'enum': <String>['get', 'update'],
            'description': 'Action to perform.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'default_language': <String, Object?>{
            'type': 'string',
            'description': 'Default BCP-47 language code (e.g. en-US).',
          },
          'contact_email': <String, Object?>{
            'type': 'string',
            'description': 'Public developer support email.',
          },
          'contact_phone': <String, Object?>{
            'type': 'string',
            'description': 'Public developer support phone number.',
          },
          'contact_website': <String, Object?>{
            'type': 'string',
            'description': 'Public app or developer website URL.',
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
            'description': 'Stage changes without submitting for review.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageAppDetails,
    ),
    McpToolDefinition(
      name: 'manage_store_listings',
      description:
          'Lists, reads, updates, patches, deletes localized Play Store listings, or syncs/exports Fastlane metadata directories (<dir>/<locale>/{title,short_description,full_description,video}.txt). Pre-validates Play Console limits (30 / 80 / 4000 chars).',
      annotations: const McpToolAnnotations(
        title: 'Manage Store Listings',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: true,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'list',
              'get',
              'update',
              'patch',
              'delete',
              'delete_all',
              'sync_from_fastlane_dir',
              'export_to_fastlane_dir',
            ],
            'description': 'Store listing action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'language': <String, Object?>{
            'type': 'string',
            'description': 'BCP-47 locale (e.g. en-US, tr-TR, ja-JP).',
          },
          'title': <String, Object?>{
            'type': 'string',
            'description': 'Localized app title (max 30 chars).',
          },
          'short_description': <String, Object?>{
            'type': 'string',
            'description': 'Localized short description (max 80 chars).',
          },
          'full_description': <String, Object?>{
            'type': 'string',
            'description': 'Localized full description (max 4000 chars).',
          },
          'video': <String, Object?>{
            'type': 'string',
            'description': 'Optional YouTube promo video URL.',
          },
          'metadata_dir': <String, Object?>{
            'type': 'string',
            'description':
                'Fastlane metadata directory containing locale subfolders (e.g. android/fastlane/metadata/android).',
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
            'description': 'Stage changes without submitting for review.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for delete_all when production writes are disabled.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageStoreListings,
    ),
    McpToolDefinition(
      name: 'manage_store_images',
      description:
          'Lists, uploads (with optional ai_generated_state attestation), or deletes Play Store icons, feature graphics, and screenshots.',
      annotations: const McpToolAnnotations(
        title: 'Manage Store Images',
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
            'enum': <String>['list', 'upload', 'delete', 'delete_all'],
            'description': 'Image operation.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'language': <String, Object?>{
            'type': 'string',
            'description': 'BCP-47 locale (e.g. en-US).',
          },
          'image_type': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'phoneScreenshots',
              'sevenInchScreenshots',
              'tenInchScreenshots',
              'tvScreenshots',
              'wearScreenshots',
              'icon',
              'featureGraphic',
              'tvBanner',
            ],
            'description': 'Google Play image asset slot.',
          },
          'file_path': <String, Object?>{
            'type': 'string',
            'description': 'Local PNG/JPEG image file path for upload.',
          },
          'image_id': <String, Object?>{
            'type': 'string',
            'description': 'Image ID to delete.',
          },
          'ai_generated_state': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'aiGeneratedStateNotAiGenerated',
              'aiGeneratedStateAiGeneratedDeveloperAttested',
            ],
            'description': 'Optional AI-generated asset attestation.',
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
            'description': 'Stage changes without submitting for review.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for delete_all when production writes are disabled.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action', 'language', 'image_type'],
      },
      handler: _handleManageStoreImages,
    ),
  ];

  Future<Object?> _handleManageAppDetails(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final editId = optString(args, 'edit_id');

    if (action == 'get') {
      return _editsService.withReadOnlyEdit(
        context: ctx,
        packageName: packageName,
        existingEditId: editId,
        action: (id) => _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/details',
        ),
      );
    }

    if (action == 'update') {
      final body = <String, Object?>{
        if (optString(args, 'default_language') case final lang?)
          'defaultLanguage': lang,
        if (optRawString(args, 'contact_email') case final email?)
          'contactEmail': email,
        if (optRawString(args, 'contact_phone') case final phone?)
          'contactPhone': phone,
        if (optRawString(args, 'contact_website') case final web?)
          'contactWebsite': web,
      };
      if (body.isEmpty) {
        throw ArgumentError(
          'Provide at least one field to update (default_language, contact_email, contact_phone, contact_website).',
        );
      }
      final exec = await _editsService.withEdit(
        context: ctx,
        packageName: packageName,
        operation: 'edits.details.patch ($packageName)',
        editId: editId,
        dryRun: optBool(args, 'dry_run') ?? false,
        changesNotSentForReview: optBool(args, 'changes_not_sent_for_review'),
        action: (activeId) => _apiClient.patchJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/details',
          body: body,
        ),
      );
      return exec.toJson();
    }

    throw ArgumentError('Unsupported manage_app_details action: $action');
  }

  Future<Object?> _handleManageStoreListings(Map<String, Object?> args) async {
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
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);

    switch (action) {
      case 'list':
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/listings',
          ),
        );

      case 'get':
        final language = reqString(args, 'language');
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/listings/${Uri.encodeComponent(language)}',
          ),
        );

      case 'update':
      case 'patch':
        final language = reqString(args, 'language');
        final title = optRawString(args, 'title');
        final shortDesc = optRawString(args, 'short_description');
        final fullDesc = optRawString(args, 'full_description');
        final video = optRawString(args, 'video');
        _validateListingLimits(
          language: language,
          title: title,
          shortDescription: shortDesc,
          fullDescription: fullDesc,
        );
        final body = <String, Object?>{
          'language': language,
          if (title != null) 'title': title,
          if (shortDesc != null) 'shortDescription': shortDesc,
          if (fullDesc != null) 'fullDescription': fullDesc,
          if (video != null) 'video': video,
        };
        if (action == 'update' &&
            (title == null || shortDesc == null || fullDesc == null)) {
          throw ArgumentError(
            'Action "update" requires title, short_description, and full_description. Use "patch" for partial updates.',
          );
        }
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.listings.$action ($language)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) {
            final path =
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/listings/${Uri.encodeComponent(language)}';
            return action == 'update'
                ? _apiClient.putJson(
                    credentials: ctx.credentials,
                    scopes: _scopes,
                    baseUrl: PlayApiEndpoints.androidPublisher,
                    path: path,
                    body: body,
                  )
                : _apiClient.patchJson(
                    credentials: ctx.credentials,
                    scopes: _scopes,
                    baseUrl: PlayApiEndpoints.androidPublisher,
                    path: path,
                    body: body,
                  );
          },
        );
        return exec.toJson();

      case 'delete':
        final language = reqString(args, 'language');
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.listings.delete ($language)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) => _apiClient.deleteJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/listings/${Uri.encodeComponent(language)}',
          ),
        );
        return exec.toJson();

      case 'delete_all':
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.listings.deleteall ($packageName)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          isProductionOrDestructive: true,
          confirmed: confirmed,
          action: (activeId) => _apiClient.deleteJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/listings',
          ),
        );
        return exec.toJson();

      case 'sync_from_fastlane_dir':
        final dirPath = reqString(args, 'metadata_dir');
        final payloads = _readFastlaneDir(dirPath);
        if (payloads.isEmpty) {
          throw StateError(
            'No locale directories with title.txt / short_description.txt / full_description.txt found under "$dirPath".',
          );
        }
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'sync_from_fastlane_dir ($packageName)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) async {
            final updatedLocales = <Map<String, Object?>>[];
            for (final payload in payloads) {
              final lang = payload['language'] as String;
              final resp = await _apiClient.patchJson(
                credentials: ctx.credentials,
                scopes: _scopes,
                baseUrl: PlayApiEndpoints.androidPublisher,
                path:
                    '/applications/$encodedPkg/edits/${Uri.encodeComponent(activeId)}/listings/${Uri.encodeComponent(lang)}',
                body: payload,
              );
              updatedLocales.add(resp);
            }
            return <String, Object?>{
              'synced_locales': payloads
                  .map((p) => p['language'])
                  .toList(growable: false),
              'listings': updatedLocales,
            };
          },
        );
        return exec.toJson();

      case 'export_to_fastlane_dir':
        final dirPath = reqString(args, 'metadata_dir');
        final listResp = await _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '/applications/$encodedPkg/edits/${Uri.encodeComponent(id)}/listings',
          ),
        );
        final listings =
            tryAsJsonList(listResp['listings']) ?? const <Object?>[];
        final exported = <String>[];
        for (final item in listings) {
          final map = tryAsJsonMap(item);
          if (map == null) continue;
          final lang = optString(map, 'language');
          if (lang == null) continue;
          final localeDir = Directory('$dirPath/$lang');
          if (!localeDir.existsSync()) {
            localeDir.createSync(recursive: true);
          }
          _writeTextIfPresent(
            localeDir,
            'title.txt',
            optRawString(map, 'title'),
          );
          _writeTextIfPresent(
            localeDir,
            'short_description.txt',
            optRawString(map, 'shortDescription'),
          );
          _writeTextIfPresent(
            localeDir,
            'full_description.txt',
            optRawString(map, 'fullDescription'),
          );
          _writeTextIfPresent(
            localeDir,
            'video.txt',
            optRawString(map, 'video'),
          );
          exported.add(lang);
        }
        return <String, Object?>{
          'exported_dir': dirPath,
          'exported_locales': exported,
        };

      default:
        throw ArgumentError(
          'Unsupported manage_store_listings action: $action',
        );
    }
  }

  Future<Object?> _handleManageStoreImages(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final language = reqString(args, 'language');
    final imageType = reqString(args, 'image_type');
    final editId = optString(args, 'edit_id');
    final dryRun = optBool(args, 'dry_run') ?? false;
    final changesNotSentForReview = optBool(
      args,
      'changes_not_sent_for_review',
    );
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);

    final basePath =
        '/applications/$encodedPkg/edits/{editId}/listings/${Uri.encodeComponent(language)}/${Uri.encodeComponent(imageType)}';

    switch (action) {
      case 'list':
        return _editsService.withReadOnlyEdit(
          context: ctx,
          packageName: packageName,
          existingEditId: editId,
          action: (id) => _apiClient.getJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path: basePath.replaceFirst('{editId}', Uri.encodeComponent(id)),
          ),
        );

      case 'upload':
        final filePath = reqString(args, 'file_path');
        final file = File(filePath);
        if (!file.existsSync()) {
          throw FileSystemException('Image file not found.', filePath);
        }
        final contentType = _detectImageContentType(filePath);
        final aiState = optString(args, 'ai_generated_state');
        final bytes = file.readAsBytesSync();
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.images.upload ($language/$imageType)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) => _apiClient.uploadMediaSimple(
            credentials: ctx.credentials,
            scopes: _scopes,
            uploadBaseUrl: PlayApiEndpoints.androidPublisherUpload,
            path: basePath.replaceFirst(
              '{editId}',
              Uri.encodeComponent(activeId),
            ),
            bytes: bytes,
            contentType: contentType,
            query: <String, Object?>{
              if (aiState != null) 'aiGeneratedState': aiState,
            },
          ),
        );
        return exec.toJson();

      case 'delete':
        final imageId = reqString(args, 'image_id');
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.images.delete ($language/$imageType/$imageId)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          action: (activeId) => _apiClient.deleteJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path:
                '${basePath.replaceFirst('{editId}', Uri.encodeComponent(activeId))}/${Uri.encodeComponent(imageId)}',
          ),
        );
        return exec.toJson();

      case 'delete_all':
        final exec = await _editsService.withEdit(
          context: ctx,
          packageName: packageName,
          operation: 'edits.images.deleteall ($language/$imageType)',
          editId: editId,
          dryRun: dryRun,
          changesNotSentForReview: changesNotSentForReview,
          isProductionOrDestructive: true,
          confirmed: confirmed,
          action: (activeId) => _apiClient.deleteJson(
            credentials: ctx.credentials,
            scopes: _scopes,
            baseUrl: PlayApiEndpoints.androidPublisher,
            path: basePath.replaceFirst(
              '{editId}',
              Uri.encodeComponent(activeId),
            ),
          ),
        );
        return exec.toJson();

      default:
        throw ArgumentError('Unsupported manage_store_images action: $action');
    }
  }

  void _validateListingLimits({
    required String language,
    String? title,
    String? shortDescription,
    String? fullDescription,
  }) {
    if (title != null && title.length > _maxTitleLength) {
      throw ArgumentError(
        '[$language] title exceeds $_maxTitleLength chars (${title.length} chars).',
      );
    }
    if (shortDescription != null &&
        shortDescription.length > _maxShortDescriptionLength) {
      throw ArgumentError(
        '[$language] short_description exceeds $_maxShortDescriptionLength chars (${shortDescription.length} chars).',
      );
    }
    if (fullDescription != null &&
        fullDescription.length > _maxFullDescriptionLength) {
      throw ArgumentError(
        '[$language] full_description exceeds $_maxFullDescriptionLength chars (${fullDescription.length} chars).',
      );
    }
  }

  List<Map<String, Object?>> _readFastlaneDir(String dirPath) {
    final root = Directory(dirPath);
    if (!root.existsSync()) {
      throw FileSystemException('Metadata directory does not exist.', dirPath);
    }
    final dirs = root.listSync().whereType<Directory>().toList()
      ..sort((a, b) => a.path.compareTo(b.path));
    final payloads = <Map<String, Object?>>[];
    for (final dir in dirs) {
      final locale = dir.uri.pathSegments.where((s) => s.isNotEmpty).last;
      final title = _readTrimmedTxt(dir, 'title.txt');
      final shortDesc = _readTrimmedTxt(dir, 'short_description.txt');
      final fullDesc = _readTrimmedTxt(dir, 'full_description.txt');
      final video = _readTrimmedTxt(dir, 'video.txt');
      if (title == null &&
          shortDesc == null &&
          fullDesc == null &&
          video == null) {
        continue;
      }
      _validateListingLimits(
        language: locale,
        title: title,
        shortDescription: shortDesc,
        fullDescription: fullDesc,
      );
      payloads.add(<String, Object?>{
        'language': locale,
        if (title != null) 'title': title,
        if (shortDesc != null) 'shortDescription': shortDesc,
        if (fullDesc != null) 'fullDescription': fullDesc,
        if (video != null) 'video': video,
      });
    }
    return payloads;
  }

  String? _readTrimmedTxt(Directory dir, String filename) {
    final file = File('${dir.path}/$filename');
    if (!file.existsSync()) return null;
    final text = file.readAsStringSync().trim();
    return text.isEmpty ? null : text;
  }

  void _writeTextIfPresent(Directory dir, String filename, String? content) {
    if (content == null || content.trim().isEmpty) return;
    File('${dir.path}/$filename').writeAsStringSync('${content.trim()}\n');
  }

  String _detectImageContentType(String filePath) {
    final lower = filePath.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) {
      return 'image/jpeg';
    }
    if (lower.endsWith('.webp')) return 'image/webp';
    throw ArgumentError(
      'Unsupported image extension for "$filePath". Play Store expects .png or .jpg/.jpeg.',
    );
  }
}
