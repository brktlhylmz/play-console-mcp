import 'dart:convert';
import 'dart:typed_data';

import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

/// Google Cloud Storage Play Console bulk CSV reports (`pubsite_prod_rev_*`)
/// tool supporting installs, ratings, crashes, store_performance, historical
/// reviews, sales, and earnings with automatic UTF-16LE BOM -> UTF-8 decoding.
final class GcsReportsTools {
  GcsReportsTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
  }) : _profileStore = profileStore,
       _apiClient = apiClient;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;

  static const List<String> _scopes = <String>[PlayScopes.devStorageReadOnly];

  static const Map<String, String> _categoryPrefixes = <String, String>{
    'installs': 'stats/installs/',
    'ratings': 'stats/ratings/',
    'crashes': 'stats/crashes/',
    'store_performance': 'stats/store_performance/',
    'reviews': 'reviews/',
    'sales': 'sales/',
    'earnings': 'earnings/',
  };

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'query_play_gcs_reports',
      description:
          'Lists or reads Google Play Console Cloud Storage bulk CSV reports (pubsite_prod_rev_*): installs, ratings, crashes, store_performance, historical reviews, sales, and earnings. Automatically decodes UTF-16LE Play CSV exports and returns structured rows + numeric column summaries.',
      annotations: const McpToolAnnotations(
        title: 'Query Play GCS Bulk Reports',
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
            'enum': <String>['list_reports', 'read_report'],
            'description': 'List report objects or download & parse a CSV.',
          },
          'bucket_name': <String, Object?>{
            'type': 'string',
            'description':
                'GCS bucket name (e.g. pubsite_prod_rev_0123456789; falls back to profile/env).',
          },
          'category': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'installs',
              'ratings',
              'crashes',
              'store_performance',
              'reviews',
              'sales',
              'earnings',
            ],
            'description': 'Report folder category shortcut for list_reports.',
          },
          'prefix': <String, Object?>{
            'type': 'string',
            'description': 'Custom GCS prefix filter for list_reports.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Optional packageName filter when listing reports.',
          },
          'year_month': <String, Object?>{
            'type': 'string',
            'description':
                'Optional YYYYMM filter (e.g. 202611) when listing reports.',
          },
          'object_name': <String, Object?>{
            'type': 'string',
            'description':
                'Required for read_report: full GCS object key (e.g. stats/installs/installs_com.example.app_202611_overview.csv).',
          },
          'max_rows': <String, Object?>{
            'type': 'integer',
            'description':
                'Maximum data rows to include in read_report output (default 200).',
          },
          'max_results': <String, Object?>{
            'type': 'integer',
            'description': 'Maximum GCS objects to list (default 100).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'GCS pagination token.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleQueryGcsReports,
    ),
  ];

  Future<Object?> _handleQueryGcsReports(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final bucket = ctx.requireGcsBucket(args);
    final encodedBucket = Uri.encodeComponent(bucket);
    final action = reqString(args, 'action');

    if (action == 'list_reports') {
      final category = optString(args, 'category');
      final customPrefix = optString(args, 'prefix');
      final prefix =
          customPrefix ??
          (category != null ? _categoryPrefixes[category] : null);
      if (category != null && customPrefix == null && prefix == null) {
        throw ArgumentError('Unsupported GCS report category: $category');
      }

      final resp = await _apiClient.getJson(
        credentials: ctx.credentials,
        scopes: _scopes,
        baseUrl: PlayApiEndpoints.cloudStorage,
        path: '/b/$encodedBucket/o',
        query: <String, Object?>{
          if (prefix != null) 'prefix': prefix,
          'maxResults': optInt(args, 'max_results') ?? 100,
          if (optString(args, 'page_token') case final pt?) 'pageToken': pt,
        },
      );

      final packageFilter = optString(args, 'package_name');
      final yearMonthFilter = optString(args, 'year_month');
      final items = tryAsJsonList(resp['items']) ?? const <Object?>[];
      final filtered = <Map<String, Object?>>[];
      for (final item in items) {
        final obj = tryAsJsonMap(item);
        if (obj == null) continue;
        final name = optString(obj, 'name') ?? '';
        if (packageFilter != null && !name.contains(packageFilter)) continue;
        if (yearMonthFilter != null && !name.contains(yearMonthFilter)) {
          continue;
        }
        filtered.add(<String, Object?>{
          'name': name,
          if (obj['size'] != null) 'size': obj['size'],
          if (obj['updated'] != null) 'updated': obj['updated'],
          if (obj['contentType'] != null) 'contentType': obj['contentType'],
        });
      }

      return <String, Object?>{
        'bucket': bucket,
        if (prefix != null) 'prefix': prefix,
        'count': filtered.length,
        'reports': filtered,
        if (resp['nextPageToken'] != null)
          'nextPageToken': resp['nextPageToken'],
      };
    }

    if (action == 'read_report') {
      final objectName = reqString(args, 'object_name');
      final maxRows = optInt(args, 'max_rows') ?? 200;
      final bytes = await _apiClient.downloadBytes(
        credentials: ctx.credentials,
        scopes: _scopes,
        baseUrl: PlayApiEndpoints.cloudStorage,
        path: '/b/$encodedBucket/o/${Uri.encodeComponent(objectName)}',
        query: const <String, Object?>{'alt': 'media'},
      );

      final decoded = decodePlayCsvBytes(bytes);
      final parsed = parseCsvTable(decoded.text);
      if (parsed.isEmpty) {
        return <String, Object?>{
          'bucket': bucket,
          'object_name': objectName,
          'encoding': decoded.encoding,
          'headers': const <String>[],
          'total_rows': 0,
          'rows': const <Object?>[],
          'numeric_totals': const <String, num>{},
        };
      }

      final headers = parsed.first;
      final dataRows = parsed.skip(1).toList(growable: false);
      final numericTotals = <String, num>{};
      final mappedRows = <Map<String, String>>[];

      for (var i = 0; i < dataRows.length; i++) {
        final row = dataRows[i];
        final record = <String, String>{};
        for (var c = 0; c < headers.length; c++) {
          final colName = headers[c];
          final cell = c < row.length ? row[c] : '';
          record[colName] = cell;
          final numVal = num.tryParse(cell.trim());
          if (numVal != null) {
            numericTotals[colName] = (numericTotals[colName] ?? 0) + numVal;
          }
        }
        if (i < maxRows) {
          mappedRows.add(record);
        }
      }

      return <String, Object?>{
        'bucket': bucket,
        'object_name': objectName,
        'encoding': decoded.encoding,
        'headers': headers,
        'total_rows': dataRows.length,
        'returned_rows': mappedRows.length,
        'truncated': dataRows.length > mappedRows.length,
        'numeric_totals': numericTotals,
        'rows': mappedRows,
      };
    }

    throw ArgumentError('Unsupported query_play_gcs_reports action: $action');
  }

  /// Decodes Play Console GCS CSV payloads (handling UTF-16LE BOM, UTF-16BE BOM,
  /// UTF-8 BOM, and plain UTF-8).
  static ({String encoding, String text}) decodePlayCsvBytes(Uint8List bytes) {
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      final codeUnits = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        codeUnits.add(bytes[i] | (bytes[i + 1] << 8));
      }
      return (encoding: 'utf-16le', text: String.fromCharCodes(codeUnits));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      final codeUnits = <int>[];
      for (var i = 2; i + 1 < bytes.length; i += 2) {
        codeUnits.add((bytes[i] << 8) | bytes[i + 1]);
      }
      return (encoding: 'utf-16be', text: String.fromCharCodes(codeUnits));
    }
    if (bytes.length >= 3 &&
        bytes[0] == 0xEF &&
        bytes[1] == 0xBB &&
        bytes[2] == 0xBF) {
      return (
        encoding: 'utf-8-bom',
        text: utf8.decode(bytes.sublist(3), allowMalformed: true),
      );
    }
    return (encoding: 'utf-8', text: utf8.decode(bytes, allowMalformed: true));
  }

  /// RFC 4180 compliant CSV parser handling quoted fields, escaped `""`, and
  /// CRLF/LF line endings.
  static List<List<String>> parseCsvTable(String input) {
    final rows = <List<String>>[];
    var currentRow = <String>[];
    final field = StringBuffer();
    var inQuotes = false;

    for (var i = 0; i < input.length; i++) {
      final ch = input[i];
      if (inQuotes) {
        if (ch == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            field.write('"');
            i++;
          } else {
            inQuotes = false;
          }
        } else {
          field.write(ch);
        }
        continue;
      }

      if (ch == '"') {
        inQuotes = true;
      } else if (ch == ',') {
        currentRow.add(field.toString());
        field.clear();
      } else if (ch == '\r') {
        if (i + 1 < input.length && input[i + 1] == '\n') {
          i++;
        }
        currentRow.add(field.toString());
        field.clear();
        if (currentRow.any((cell) => cell.isNotEmpty)) {
          rows.add(currentRow);
        }
        currentRow = <String>[];
      } else if (ch == '\n') {
        currentRow.add(field.toString());
        field.clear();
        if (currentRow.any((cell) => cell.isNotEmpty)) {
          rows.add(currentRow);
        }
        currentRow = <String>[];
      } else {
        field.write(ch);
      }
    }

    if (field.isNotEmpty || currentRow.isNotEmpty) {
      currentRow.add(field.toString());
      if (currentRow.any((cell) => cell.isNotEmpty)) {
        rows.add(currentRow);
      }
    }

    return rows;
  }
}
