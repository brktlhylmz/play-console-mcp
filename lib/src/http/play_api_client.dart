import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../utils/json_helpers.dart';

/// Base URLs for the Google APIs used by `play-console-mcp`.
abstract final class PlayApiEndpoints {
  static const String androidPublisher =
      'https://androidpublisher.googleapis.com/androidpublisher/v3';
  static const String androidPublisherUpload =
      'https://androidpublisher.googleapis.com/upload/androidpublisher/v3';
  static const String androidPublisherResumable =
      'https://androidpublisher.googleapis.com/resumable/upload/androidpublisher/v3';
  static const String developerReporting =
      'https://playdeveloperreporting.googleapis.com/v1beta1';
  static const String cloudStorage =
      'https://storage.googleapis.com/storage/v1';
}

/// Structured HTTP error raised when Google Play or GCS APIs return >= 400,
/// enriched with actionable remediation hints.
final class PlayApiException implements Exception {
  const PlayApiException({
    required this.statusCode,
    required this.method,
    required this.uri,
    required this.message,
    this.googleStatus,
    this.rawBody,
    this.hint,
  });

  final int statusCode;
  final String method;
  final Uri uri;
  final String message;
  final String? googleStatus;
  final String? rawBody;
  final String? hint;

  @override
  String toString() {
    final buf = StringBuffer()
      ..write('Google API error HTTP $statusCode')
      ..write(googleStatus != null ? ' ($googleStatus)' : '')
      ..write(' on $method ${uri.path}: $message');
    if (hint != null && hint!.isNotEmpty) {
      buf.write('\nHint: $hint');
    }
    return buf.toString();
  }
}

/// Unified HTTP REST and Resumable Media Upload client across Android
/// Publisher v3, Play Developer Reporting v1beta1, and GCS v1.
final class PlayApiClient {
  PlayApiClient(this._authProvider);

  final PlayAuthProvider _authProvider;

  /// Sends a `GET` request expecting a JSON object response.
  Future<Map<String, Object?>> getJson({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
  }) {
    return _requestJson(
      credentials: credentials,
      scopes: scopes,
      method: 'GET',
      baseUrl: baseUrl,
      path: path,
      query: query,
    );
  }

  /// Sends a `POST` request with optional JSON body.
  Future<Map<String, Object?>> postJson({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
    Object? body,
  }) {
    return _requestJson(
      credentials: credentials,
      scopes: scopes,
      method: 'POST',
      baseUrl: baseUrl,
      path: path,
      query: query,
      body: body,
    );
  }

  /// Sends a `PUT` request with JSON body.
  Future<Map<String, Object?>> putJson({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
    Object? body,
  }) {
    return _requestJson(
      credentials: credentials,
      scopes: scopes,
      method: 'PUT',
      baseUrl: baseUrl,
      path: path,
      query: query,
      body: body,
    );
  }

  /// Sends a `PATCH` request with JSON body.
  Future<Map<String, Object?>> patchJson({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
    Object? body,
  }) {
    return _requestJson(
      credentials: credentials,
      scopes: scopes,
      method: 'PATCH',
      baseUrl: baseUrl,
      path: path,
      query: query,
      body: body,
    );
  }

  /// Sends a `DELETE` request.
  Future<Map<String, Object?>> deleteJson({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
    Object? body,
  }) {
    return _requestJson(
      credentials: credentials,
      scopes: scopes,
      method: 'DELETE',
      baseUrl: baseUrl,
      path: path,
      query: query,
      body: body,
    );
  }

  /// Downloads raw binary bytes (used for generated APKs and GCS CSV objects).
  Future<Uint8List> downloadBytes({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
  }) async {
    final client = await _authProvider.getClient(credentials, scopes);
    final uri = _buildUri(baseUrl, path, query);
    final response = await client.get(uri);
    if (response.statusCode >= 400) {
      throw _buildApiException('GET', uri, response.statusCode, response.body);
    }
    return response.bodyBytes;
  }

  /// Performs a simple binary media upload (`uploadType=media`), suited for
  /// store icons, feature graphics, and screenshots.
  Future<Map<String, Object?>> uploadMediaSimple({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String uploadBaseUrl,
    required String path,
    required Uint8List bytes,
    required String contentType,
    Map<String, Object?>? query,
  }) async {
    final client = await _authProvider.getClient(credentials, scopes);
    final mergedQuery = <String, Object?>{...?query, 'uploadType': 'media'};
    final uri = _buildUri(uploadBaseUrl, path, mergedQuery);
    final response = await client.post(
      uri,
      headers: <String, String>{
        'Content-Type': contentType,
        'Content-Length': bytes.length.toString(),
      },
      body: bytes,
    );
    return _parseJsonResponse('POST', uri, response.statusCode, response.body);
  }

  /// Performs a 2-step Google Resumable Upload (`POST ?uploadType=resumable` ->
  /// `PUT` payload bytes to returned `Location` URI). Recommended for `.aab`,
  /// `.apk`, and deobfuscation mapping files.
  Future<Map<String, Object?>> uploadMediaResumable({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String resumableBaseUrl,
    required String path,
    required Uint8List bytes,
    String contentType = 'application/octet-stream',
    Map<String, Object?>? query,
  }) async {
    final client = await _authProvider.getClient(credentials, scopes);
    final startQuery = <String, Object?>{...?query, 'uploadType': 'resumable'};
    final startUri = _buildUri(resumableBaseUrl, path, startQuery);
    final initResponse = await client.post(
      startUri,
      headers: <String, String>{
        'X-Upload-Content-Type': contentType,
        'X-Upload-Content-Length': bytes.length.toString(),
        'Content-Length': '0',
      },
    );
    if (initResponse.statusCode >= 400) {
      throw _buildApiException(
        'POST',
        startUri,
        initResponse.statusCode,
        initResponse.body,
      );
    }

    final location = _findHeaderIgnoreCase(initResponse.headers, 'location');
    if (location == null || location.isEmpty) {
      // Fallback: if a server answered directly with JSON instead of Location
      // redirect (unlikely in prod, helpful defensive check).
      if (initResponse.body.trim().isNotEmpty) {
        return _parseJsonResponse(
          'POST',
          startUri,
          initResponse.statusCode,
          initResponse.body,
        );
      }
      throw PlayApiException(
        statusCode: initResponse.statusCode,
        method: 'POST',
        uri: startUri,
        message:
            'Resumable upload initiation did not return a Location header.',
      );
    }

    final uploadUri = Uri.parse(location);
    final putResponse = await client.put(
      uploadUri,
      headers: <String, String>{
        'Content-Type': contentType,
        'Content-Length': bytes.length.toString(),
      },
      body: bytes,
    );
    return _parseJsonResponse(
      'PUT',
      uploadUri,
      putResponse.statusCode,
      putResponse.body,
    );
  }

  Future<Map<String, Object?>> _requestJson({
    required ResolvedCredentials credentials,
    required List<String> scopes,
    required String method,
    required String baseUrl,
    required String path,
    Map<String, Object?>? query,
    Object? body,
  }) async {
    final client = await _authProvider.getClient(credentials, scopes);
    final uri = _buildUri(baseUrl, path, query);
    final encodedBody = body == null ? null : jsonEncode(body);
    final headers = <String, String>{
      'Accept': 'application/json',
      if (encodedBody != null)
        'Content-Type': 'application/json; charset=utf-8',
    };

    final http.Response response;
    switch (method) {
      case 'GET':
        response = await client.get(uri, headers: headers);
      case 'POST':
        response = await client.post(uri, headers: headers, body: encodedBody);
      case 'PUT':
        response = await client.put(uri, headers: headers, body: encodedBody);
      case 'PATCH':
        response = await client.patch(uri, headers: headers, body: encodedBody);
      case 'DELETE':
        response = await client.delete(
          uri,
          headers: headers,
          body: encodedBody,
        );
      default:
        throw ArgumentError('Unsupported HTTP method: $method');
    }

    return _parseJsonResponse(method, uri, response.statusCode, response.body);
  }

  Uri _buildUri(String baseUrl, String path, Map<String, Object?>? query) {
    final normalizedBase = baseUrl.endsWith('/')
        ? baseUrl.substring(0, baseUrl.length - 1)
        : baseUrl;
    final normalizedPath = path.startsWith('/') ? path : '/$path';
    final rawUri = Uri.parse('$normalizedBase$normalizedPath');
    if (query == null || query.isEmpty) {
      return rawUri;
    }

    // Encode query parameters including repeated values cleanly.
    final pairs = <String>[];
    for (final entry in query.entries) {
      final value = entry.value;
      if (value == null) continue;
      if (value is List) {
        for (final item in value) {
          if (item != null) {
            pairs.add(
              '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(item.toString())}',
            );
          }
        }
      } else {
        pairs.add(
          '${Uri.encodeQueryComponent(entry.key)}=${Uri.encodeQueryComponent(value.toString())}',
        );
      }
    }
    if (pairs.isEmpty) return rawUri;
    final sep = rawUri.query.isEmpty ? '?' : '&';
    return Uri.parse('${rawUri.toString()}$sep${pairs.join('&')}');
  }

  Map<String, Object?> _parseJsonResponse(
    String method,
    Uri uri,
    int statusCode,
    String body,
  ) {
    if (statusCode >= 400) {
      throw _buildApiException(method, uri, statusCode, body);
    }
    final trimmed = body.trim();
    if (trimmed.isEmpty) {
      return const <String, Object?>{};
    }
    final decoded = jsonDecode(trimmed);
    return tryAsJsonMap(decoded) ?? <String, Object?>{'data': decoded};
  }

  PlayApiException _buildApiException(
    String method,
    Uri uri,
    int statusCode,
    String rawBody,
  ) {
    var message = rawBody.trim().isEmpty ? 'Empty error body' : rawBody.trim();
    String? googleStatus;

    try {
      final decoded = tryAsJsonMap(jsonDecode(rawBody));
      final errObj = tryAsJsonMap(decoded?['error']);
      if (errObj != null) {
        message = optString(errObj, 'message') ?? message;
        googleStatus = optString(errObj, 'status');
      }
    } on Object {
      // Keep rawBody when error body is non-JSON.
    }

    final hint = _inferHint(statusCode, uri.path, message);
    return PlayApiException(
      statusCode: statusCode,
      method: method,
      uri: uri,
      message: message,
      googleStatus: googleStatus,
      rawBody: rawBody,
      hint: hint,
    );
  }

  String? _inferHint(int statusCode, String path, String message) {
    final lower = message.toLowerCase();
    if (statusCode == 400 && lower.contains('changesnotsentforreview')) {
      return 'Your app likely has a rejected submission or requires manual review dispatch. Retry with changes_not_sent_for_review: true.';
    }
    if (statusCode == 400 && lower.contains('already have changes in review')) {
      return 'Another submission is already in review. Pass changes_in_review_behavior: "CANCEL_IN_REVIEW_AND_SUBMIT" only if you intend to replace the active review.';
    }
    if (statusCode == 403 && path.contains('/inappproducts')) {
      return 'Legacy inappproducts writes are blocked for migrated catalogs. Use manage_one_time_products modern actions (oneTimeProducts) instead.';
    }
    if (statusCode == 403) {
      return 'Ensure the Google Cloud API (androidpublisher.googleapis.com / playdeveloperreporting.googleapis.com) is enabled AND the Service Account is invited in Google Play Console > Users and permissions (new permissions can take up to 24h to propagate, or try saving a minor app metadata change in Play Console UI to force permission sync).';
    }
    if (statusCode == 404) {
      return 'Verify package_name / IDs. Note: Google Play requires the very first APK/AAB of a brand-new app to be uploaded once manually via the Play Console web UI before API edits succeed.';
    }
    if (statusCode == 429) {
      return 'Google Play API rate limit exceeded. Wait briefly and retry.';
    }
    return null;
  }

  String? _findHeaderIgnoreCase(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value;
      }
    }
    return null;
  }
}
