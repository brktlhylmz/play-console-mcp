import 'dart:convert';
import 'dart:io';

import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;

import '../config/profile_store.dart';
import '../utils/json_helpers.dart';

/// OAuth2 scopes required by Google Play Console MCP APIs.
abstract final class PlayScopes {
  static const String androidPublisher =
      'https://www.googleapis.com/auth/androidpublisher';
  static const String playDeveloperReporting =
      'https://www.googleapis.com/auth/playdeveloperreporting';
  static const String devStorageReadOnly =
      'https://www.googleapis.com/auth/devstorage.read_only';
}

/// Factory signature for creating authenticated HTTP clients. Allows tests to
/// inject deterministic mock HTTP clients without reading real key files.
typedef AuthClientFactory =
    Future<http.Client> Function(
      ResolvedCredentials credentials,
      List<String> scopes,
    );

/// Non-secret credential metadata returned by `inspectCredentials`.
final class CredentialInspection {
  const CredentialInspection({
    required this.source,
    this.path,
    this.clientEmail,
    this.projectId,
    this.type,
    this.error,
  });

  final CredentialSource source;
  final String? path;
  final String? clientEmail;
  final String? projectId;
  final String? type;
  final String? error;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'source': source.name,
      if (path != null) 'path': path,
      if (clientEmail != null) 'client_email': clientEmail,
      if (projectId != null) 'project_id': projectId,
      if (type != null) 'credential_type': type,
      if (error != null) 'error': error,
    };
  }
}

/// Provides and caches scope-specific authenticated HTTP clients for Google APIs.
final class PlayAuthProvider {
  PlayAuthProvider({AuthClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? _defaultClientFactory;

  final AuthClientFactory _clientFactory;
  final Map<String, http.Client> _cache = <String, http.Client>{};

  static Future<http.Client> _defaultClientFactory(
    ResolvedCredentials credentials,
    List<String> scopes,
  ) async {
    switch (credentials.source) {
      case CredentialSource.profileServiceAccountFile:
      case CredentialSource.envServiceAccountPath:
      case CredentialSource.envGoogleApplicationCredentials:
        final path = credentials.serviceAccountPath;
        if (path == null || path.isEmpty) {
          throw StateError('Service account file path is empty.');
        }
        final file = File(path);
        if (!file.existsSync()) {
          throw FileSystemException(
            'Service account JSON file not found.',
            path,
          );
        }
        final jsonText = file.readAsStringSync();
        final saCreds = ServiceAccountCredentials.fromJson(jsonText);
        return clientViaServiceAccount(saCreds, scopes);

      case CredentialSource.envServiceAccountJson:
        final rawJson = credentials.serviceAccountJson;
        if (rawJson == null || rawJson.isEmpty) {
          throw StateError('PLAY_CONSOLE_SERVICE_ACCOUNT_JSON is empty.');
        }
        final saCreds = ServiceAccountCredentials.fromJson(rawJson);
        return clientViaServiceAccount(saCreds, scopes);

      case CredentialSource.applicationDefaultCredentials:
        return clientViaApplicationDefaultCredentials(scopes: scopes);
    }
  }

  /// Returns an authenticated [http.Client] cached by credential source + scopes.
  Future<http.Client> getClient(
    ResolvedCredentials credentials,
    List<String> scopes,
  ) async {
    final sortedScopes = List<String>.from(scopes)..sort();
    final key = '${credentials.cacheKey}|${sortedScopes.join(",")}';
    final existing = _cache[key];
    if (existing != null) {
      return existing;
    }
    final client = await _clientFactory(credentials, sortedScopes);
    _cache[key] = client;
    return client;
  }

  /// Inspects credential configuration without leaking private keys.
  CredentialInspection inspectCredentials(ResolvedCredentials credentials) {
    try {
      String? rawJson;
      if (credentials.source == CredentialSource.envServiceAccountJson) {
        rawJson = credentials.serviceAccountJson;
      } else if (credentials.serviceAccountPath != null) {
        final file = File(credentials.serviceAccountPath!);
        if (!file.existsSync()) {
          return CredentialInspection(
            source: credentials.source,
            path: credentials.serviceAccountPath,
            error:
                'Credential file does not exist at ${credentials.serviceAccountPath}.',
          );
        }
        rawJson = file.readAsStringSync();
      } else {
        return CredentialInspection(source: credentials.source, error: null);
      }

      if (rawJson == null || rawJson.trim().isEmpty) {
        return CredentialInspection(
          source: credentials.source,
          path: credentials.serviceAccountPath,
          error: 'Credential JSON is empty.',
        );
      }

      final decoded = tryAsJsonMap(jsonDecode(rawJson));
      if (decoded == null) {
        return CredentialInspection(
          source: credentials.source,
          path: credentials.serviceAccountPath,
          error: 'Credential JSON did not decode to an object.',
        );
      }

      return CredentialInspection(
        source: credentials.source,
        path: credentials.serviceAccountPath,
        clientEmail: optString(decoded, 'client_email'),
        projectId: optString(decoded, 'project_id'),
        type: optString(decoded, 'type'),
      );
    } on Object catch (e) {
      return CredentialInspection(
        source: credentials.source,
        path: credentials.serviceAccountPath,
        error: 'Failed to read credentials: $e',
      );
    }
  }

  /// Closes all cached HTTP clients.
  void close() {
    for (final client in _cache.values) {
      client.close();
    }
    _cache.clear();
  }
}
