import 'dart:convert';
import 'dart:io';

import '../utils/json_helpers.dart';

/// Represents a named Google Play Console profile stored in
/// `~/.config/play_console_mcp/config.json`.
final class PlayProfile {
  const PlayProfile({
    required this.profileId,
    required this.label,
    this.serviceAccountPath,
    this.defaultPackageName,
    this.developerId,
    this.gcsBucketId,
    this.readOnly = false,
    this.allowProductionWrites = false,
    this.defaultChangesNotSentForReview = false,
  });

  factory PlayProfile.fromJson(Map<String, Object?> json) {
    return PlayProfile(
      profileId: optString(json, 'profile_id') ?? 'default',
      label: optString(json, 'label') ?? 'Default Play Console Profile',
      serviceAccountPath: optString(json, 'service_account_path'),
      defaultPackageName: optString(json, 'default_package_name'),
      developerId: optString(json, 'developer_id'),
      gcsBucketId: optString(json, 'gcs_bucket_id'),
      readOnly: optBool(json, 'read_only') ?? false,
      allowProductionWrites: optBool(json, 'allow_production_writes') ?? false,
      defaultChangesNotSentForReview:
          optBool(json, 'default_changes_not_sent_for_review') ?? false,
    );
  }

  final String profileId;
  final String label;
  final String? serviceAccountPath;
  final String? defaultPackageName;
  final String? developerId;
  final String? gcsBucketId;
  final bool readOnly;
  final bool allowProductionWrites;
  final bool defaultChangesNotSentForReview;

  PlayProfile copyWith({
    String? profileId,
    String? label,
    String? serviceAccountPath,
    String? defaultPackageName,
    String? developerId,
    String? gcsBucketId,
    bool? readOnly,
    bool? allowProductionWrites,
    bool? defaultChangesNotSentForReview,
  }) {
    return PlayProfile(
      profileId: profileId ?? this.profileId,
      label: label ?? this.label,
      serviceAccountPath: serviceAccountPath ?? this.serviceAccountPath,
      defaultPackageName: defaultPackageName ?? this.defaultPackageName,
      developerId: developerId ?? this.developerId,
      gcsBucketId: gcsBucketId ?? this.gcsBucketId,
      readOnly: readOnly ?? this.readOnly,
      allowProductionWrites:
          allowProductionWrites ?? this.allowProductionWrites,
      defaultChangesNotSentForReview:
          defaultChangesNotSentForReview ?? this.defaultChangesNotSentForReview,
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'profile_id': profileId,
      'label': label,
      if (serviceAccountPath != null)
        'service_account_path': serviceAccountPath,
      if (defaultPackageName != null)
        'default_package_name': defaultPackageName,
      if (developerId != null) 'developer_id': developerId,
      if (gcsBucketId != null) 'gcs_bucket_id': gcsBucketId,
      'read_only': readOnly,
      'allow_production_writes': allowProductionWrites,
      'default_changes_not_sent_for_review': defaultChangesNotSentForReview,
    };
  }
}

/// Source used to resolve Google OAuth2 credentials.
enum CredentialSource {
  profileServiceAccountFile,
  envServiceAccountJson,
  envServiceAccountPath,
  envGoogleApplicationCredentials,
  applicationDefaultCredentials,
}

/// Resolved credential specification ready for [PlayAuthProvider].
final class ResolvedCredentials {
  const ResolvedCredentials({
    required this.source,
    this.serviceAccountPath,
    this.serviceAccountJson,
  });

  final CredentialSource source;
  final String? serviceAccountPath;
  final String? serviceAccountJson;

  /// Stable cache key that does not expose sensitive key material.
  String get cacheKey {
    return switch (source) {
      CredentialSource.profileServiceAccountFile =>
        'profile_file:${serviceAccountPath ?? ''}',
      CredentialSource.envServiceAccountJson =>
        'env_json:${(serviceAccountJson ?? '').hashCode}',
      CredentialSource.envServiceAccountPath =>
        'env_path:${serviceAccountPath ?? ''}',
      CredentialSource.envGoogleApplicationCredentials =>
        'gac:${serviceAccountPath ?? ''}',
      CredentialSource.applicationDefaultCredentials => 'adc',
    };
  }
}

/// Combined profile + environment runtime context for executing a tool call.
final class ResolvedPlayContext {
  const ResolvedPlayContext({
    required this.credentials,
    this.profile,
    this.defaultPackageName,
    this.developerId,
    this.gcsBucketId,
    this.readOnly = false,
    this.allowProductionWrites = false,
    this.defaultChangesNotSentForReview = false,
  });

  final PlayProfile? profile;
  final ResolvedCredentials credentials;
  final String? defaultPackageName;
  final String? developerId;
  final String? gcsBucketId;
  final bool readOnly;
  final bool allowProductionWrites;
  final bool defaultChangesNotSentForReview;

  /// Resolves the target Android `packageName` from [args] or profile/env defaults.
  String requirePackageName(Map<String, Object?> args) {
    final pkg = optString(args, 'package_name') ?? defaultPackageName;
    if (pkg == null || pkg.isEmpty) {
      throw ArgumentError(
        'Missing package_name. Pass "package_name" (e.g. com.example.app) or configure default_package_name in your profile / PLAY_CONSOLE_DEFAULT_PACKAGE.',
      );
    }
    return pkg;
  }

  /// Resolves the Google Play `developerId` from [args] or profile/env defaults.
  String requireDeveloperId(Map<String, Object?> args) {
    final devId = optString(args, 'developer_id') ?? developerId;
    if (devId == null || devId.isEmpty) {
      throw ArgumentError(
        'Missing developer_id. Pass "developer_id" or configure developer_id in your profile / PLAY_CONSOLE_DEVELOPER_ID.',
      );
    }
    return devId;
  }

  /// Resolves the Google Cloud Storage bucket name (`pubsite_prod_rev_*`) from
  /// [args] or profile/env defaults.
  String requireGcsBucket(Map<String, Object?> args) {
    final raw =
        optString(args, 'bucket_name') ??
        optString(args, 'gcs_bucket_id') ??
        gcsBucketId;
    if (raw == null || raw.isEmpty) {
      throw ArgumentError(
        'Missing bucket_name / gcs_bucket_id. Pass "bucket_name" (e.g. pubsite_prod_rev_0123456789) or configure gcs_bucket_id in your profile / PLAY_CONSOLE_GCS_BUCKET.',
      );
    }
    return raw.startsWith('gs://') ? raw.substring(5) : raw;
  }
}

/// Manages reading, writing, and resolving Play Console profiles and
/// environment variable overrides.
final class PlayProfileStore {
  PlayProfileStore({String? configFilePath, Map<String, String>? environment})
    : _configFilePath = configFilePath ?? _defaultConfigPath(),
      _env = environment ?? Platform.environment;

  final String _configFilePath;
  final Map<String, String> _env;

  static String _defaultConfigPath() {
    final home =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        '';
    return '$home/.config/play_console_mcp/config.json';
  }

  String get configFilePath => _configFilePath;

  Map<String, Object?> _readRaw() {
    final file = File(_configFilePath);
    if (!file.existsSync()) {
      return <String, Object?>{};
    }
    final content = file.readAsStringSync().trim();
    if (content.isEmpty) {
      return <String, Object?>{};
    }
    try {
      final decoded = jsonDecode(content);
      return tryAsJsonMap(decoded) ?? <String, Object?>{};
    } on FormatException catch (e) {
      throw FormatException('Failed to parse $_configFilePath: ${e.message}');
    }
  }

  void _writeRaw(Map<String, Object?> data) {
    final file = File(_configFilePath);
    if (!file.parent.existsSync()) {
      file.parent.createSync(recursive: true);
    }
    file.writeAsStringSync('${prettyJson(data)}\n');
    if (!Platform.isWindows) {
      try {
        Process.runSync('chmod', <String>['600', _configFilePath]);
      } on Object {
        // Ignore chmod failures in constrained sandboxes.
      }
    }
  }

  /// Lists all saved profiles in `~/.config/play_console_mcp/config.json`.
  List<PlayProfile> listProfiles() {
    final raw = _readRaw();
    final profilesNode = tryAsJsonMap(raw['profiles']);
    if (profilesNode == null) {
      return const <PlayProfile>[];
    }
    final result = <PlayProfile>[];
    for (final entry in profilesNode.entries) {
      final map = tryAsJsonMap(entry.value);
      if (map != null) {
        final merged = <String, Object?>{'profile_id': entry.key, ...map};
        result.add(PlayProfile.fromJson(merged));
      }
    }
    result.sort((a, b) => a.profileId.compareTo(b.profileId));
    return result;
  }

  /// Returns the default `profile_id` if configured.
  String? getDefaultProfileId() {
    final envDefault = _nonEmptyEnv('PLAY_CONSOLE_PROFILE');
    if (envDefault != null) return envDefault;
    final raw = _readRaw();
    return optString(raw, 'default_profile_id');
  }

  /// Returns the profile matching [profileId] (or default profile if omitted).
  PlayProfile? getProfile([String? profileId]) {
    final targetId = profileId ?? getDefaultProfileId();
    final profiles = listProfiles();
    if (profiles.isEmpty) return null;
    if (targetId != null) {
      for (final p in profiles) {
        if (p.profileId == targetId) return p;
      }
      if (profileId != null) {
        throw ArgumentError(
          'Unknown profile "$profileId". Available profiles: ${profiles.map((p) => p.profileId).join(', ')}.',
        );
      }
    }
    return profiles.first;
  }

  /// Saves or updates [profile] and optionally marks it as default.
  PlayProfile saveProfile(PlayProfile profile, {bool makeDefault = false}) {
    final raw = _readRaw();
    final existingProfiles =
        tryAsJsonMap(raw['profiles']) ?? <String, Object?>{};
    final updatedProfiles = Map<String, Object?>.from(existingProfiles);
    updatedProfiles[profile.profileId] = profile.toJson();

    final currentDefault = optString(raw, 'default_profile_id');
    final nextDefault = makeDefault || currentDefault == null
        ? profile.profileId
        : currentDefault;

    _writeRaw(<String, Object?>{
      'default_profile_id': nextDefault,
      'profiles': updatedProfiles,
    });
    return profile;
  }

  /// Sets [profileId] as the default profile.
  PlayProfile setDefaultProfile(String profileId) {
    final target = getProfile(profileId);
    if (target == null) {
      throw ArgumentError('Profile "$profileId" does not exist.');
    }
    final raw = _readRaw();
    final existingProfiles =
        tryAsJsonMap(raw['profiles']) ?? <String, Object?>{};
    _writeRaw(<String, Object?>{
      'default_profile_id': profileId,
      'profiles': existingProfiles,
    });
    return target;
  }

  /// Removes [profileId] from the configuration file.
  bool removeProfile(String profileId) {
    final raw = _readRaw();
    final existingProfiles = tryAsJsonMap(raw['profiles']);
    if (existingProfiles == null || !existingProfiles.containsKey(profileId)) {
      return false;
    }
    final updated = Map<String, Object?>.from(existingProfiles)
      ..remove(profileId);
    var nextDefault = optString(raw, 'default_profile_id');
    if (nextDefault == profileId) {
      nextDefault = updated.isEmpty ? null : updated.keys.first;
    }
    _writeRaw(<String, Object?>{
      if (nextDefault != null) 'default_profile_id': nextDefault,
      'profiles': updated,
    });
    return true;
  }

  /// Resolves credentials, defaults, and safety flags for a single tool call.
  ResolvedPlayContext resolveContext([Map<String, Object?> args = const {}]) {
    final requestedProfileId = optString(args, 'profile');
    final profile = getProfile(requestedProfileId);

    final credentials = _resolveCredentials(profile);

    final envReadOnly = _boolEnv('PLAY_CONSOLE_READ_ONLY');
    final envAllowProd = _boolEnv('PLAY_CONSOLE_ALLOW_PRODUCTION_WRITES');
    final envNoReview = _boolEnv('PLAY_CONSOLE_CHANGES_NOT_SENT_FOR_REVIEW');

    return ResolvedPlayContext(
      profile: profile,
      credentials: credentials,
      defaultPackageName:
          profile?.defaultPackageName ??
          _nonEmptyEnv('PLAY_CONSOLE_DEFAULT_PACKAGE'),
      developerId:
          profile?.developerId ?? _nonEmptyEnv('PLAY_CONSOLE_DEVELOPER_ID'),
      gcsBucketId:
          profile?.gcsBucketId ?? _nonEmptyEnv('PLAY_CONSOLE_GCS_BUCKET'),
      readOnly: envReadOnly ?? profile?.readOnly ?? false,
      allowProductionWrites:
          envAllowProd ?? profile?.allowProductionWrites ?? false,
      defaultChangesNotSentForReview:
          envNoReview ?? profile?.defaultChangesNotSentForReview ?? false,
    );
  }

  ResolvedCredentials _resolveCredentials(PlayProfile? profile) {
    final profilePath = profile?.serviceAccountPath;
    if (profilePath != null && profilePath.isNotEmpty) {
      return ResolvedCredentials(
        source: CredentialSource.profileServiceAccountFile,
        serviceAccountPath: _expandHome(profilePath),
      );
    }

    final envJson = _nonEmptyEnv('PLAY_CONSOLE_SERVICE_ACCOUNT_JSON');
    if (envJson != null) {
      return ResolvedCredentials(
        source: CredentialSource.envServiceAccountJson,
        serviceAccountJson: envJson,
      );
    }

    final envPath = _nonEmptyEnv('PLAY_CONSOLE_SERVICE_ACCOUNT_PATH');
    if (envPath != null) {
      return ResolvedCredentials(
        source: CredentialSource.envServiceAccountPath,
        serviceAccountPath: _expandHome(envPath),
      );
    }

    final gac = _nonEmptyEnv('GOOGLE_APPLICATION_CREDENTIALS');
    if (gac != null) {
      return ResolvedCredentials(
        source: CredentialSource.envGoogleApplicationCredentials,
        serviceAccountPath: _expandHome(gac),
      );
    }

    return const ResolvedCredentials(
      source: CredentialSource.applicationDefaultCredentials,
    );
  }

  String _expandHome(String rawPath) {
    if (!rawPath.startsWith('~/')) return rawPath;
    final home = _env['HOME'] ?? _env['USERPROFILE'] ?? '';
    if (home.isEmpty) return rawPath;
    return '$home/${rawPath.substring(2)}';
  }

  String? _nonEmptyEnv(String key) {
    final v = _env[key]?.trim();
    return (v == null || v.isEmpty) ? null : v;
  }

  bool? _boolEnv(String key) {
    final v = _nonEmptyEnv(key)?.toLowerCase();
    if (v == null) return null;
    if (v == 'true' || v == '1' || v == 'yes') return true;
    if (v == 'false' || v == '0' || v == 'no') return false;
    return null;
  }
}
