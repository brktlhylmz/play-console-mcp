import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

final class _MetricSetSpec {
  const _MetricSetSpec({
    required this.resourceName,
    required this.defaultMetrics,
    required this.supportsUserCohort,
  });

  final String resourceName;
  final List<String> defaultMetrics;
  final bool supportsUserCohort;
}

/// Android Vitals metrics, error issue/report search, and anomaly alerts built
/// on the Play Developer Reporting API (`v1beta1`).
final class VitalsTools {
  VitalsTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
    DateTime Function()? clock,
  }) : _profileStore = profileStore,
       _apiClient = apiClient,
       _clock = clock ?? DateTime.now;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;
  final DateTime Function() _clock;

  static const List<String> _scopes = <String>[
    PlayScopes.playDeveloperReporting,
  ];

  static const Map<String, _MetricSetSpec>
  _metricSets = <String, _MetricSetSpec>{
    'crash_rate': _MetricSetSpec(
      resourceName: 'crashRateMetricSet',
      defaultMetrics: <String>['crashRate', 'crashRate7dUserWeighted'],
      supportsUserCohort: true,
    ),
    'anr_rate': _MetricSetSpec(
      resourceName: 'anrRateMetricSet',
      defaultMetrics: <String>['anrRate', 'anrRate7dUserWeighted'],
      supportsUserCohort: true,
    ),
    'slow_start_rate': _MetricSetSpec(
      resourceName: 'slowStartRateMetricSet',
      defaultMetrics: <String>['slowStartRate', 'slowStartRate7dUserWeighted'],
      supportsUserCohort: true,
    ),
    'slow_rendering_rate': _MetricSetSpec(
      resourceName: 'slowRenderingRateMetricSet',
      defaultMetrics: <String>[
        'slowRenderingRate20Fps',
        'slowRenderingRate20Fps7dUserWeighted',
      ],
      supportsUserCohort: true,
    ),
    'excessive_wakeup_rate': _MetricSetSpec(
      resourceName: 'excessiveWakeupRateMetricSet',
      defaultMetrics: <String>[
        'excessiveWakeupRate',
        'excessiveWakeupRate7dUserWeighted',
      ],
      supportsUserCohort: true,
    ),
    'stuck_background_wakelock_rate': _MetricSetSpec(
      resourceName: 'stuckBackgroundWakelockRateMetricSet',
      defaultMetrics: <String>[
        'stuckBgWakelockRate',
        'stuckBgWakelockRate7dUserWeighted',
      ],
      supportsUserCohort: true,
    ),
    'lmk_rate': _MetricSetSpec(
      resourceName: 'lmkRateMetricSet',
      defaultMetrics: <String>[
        'userPerceivedLmkRate',
        'userPerceivedLmkRate7dUserWeighted',
      ],
      supportsUserCohort: true,
    ),
    'anon_rss_memory': _MetricSetSpec(
      resourceName: 'anonRssAndSwapMemoryUsageMetricSet',
      defaultMetrics: <String>[
        'anonRssAndSwapMemoryUsageP50',
        'anonRssAndSwapMemoryUsageP90',
      ],
      supportsUserCohort: true,
    ),
    'bitmap_memory': _MetricSetSpec(
      resourceName: 'bitmapMemoryUsageMetricSet',
      defaultMetrics: <String>['bitmapMemoryUsageP50', 'bitmapMemoryUsageP90'],
      supportsUserCohort: true,
    ),
    'error_counts': _MetricSetSpec(
      resourceName: 'errorCountMetricSet',
      defaultMetrics: <String>['errorReportCount', 'distinctUsers'],
      supportsUserCohort: false,
    ),
  };

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'query_android_vitals',
      description:
          'Describes or queries all 10 Android Vitals metric sets (crash_rate, anr_rate, slow_start_rate, slow_rendering_rate, excessive_wakeup_rate, stuck_background_wakelock_rate, lmk_rate, anon_rss_memory, bitmap_memory, error_counts).',
      annotations: const McpToolAnnotations(
        title: 'Query Android Vitals',
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
            'enum': <String>['query', 'describe'],
            'description':
                'Whether to query metrics or describe available dimensions/freshness of the metric set.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'metric_set': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'crash_rate',
              'anr_rate',
              'slow_start_rate',
              'slow_rendering_rate',
              'excessive_wakeup_rate',
              'stuck_background_wakelock_rate',
              'lmk_rate',
              'anon_rss_memory',
              'bitmap_memory',
              'error_counts',
            ],
            'description': 'Target Android Vitals metric set.',
          },
          'metrics': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                'Specific metric names to aggregate (sensible defaults applied if omitted).',
          },
          'dimensions': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description':
                'Optional dimensions to slice by (e.g. ["versionCode", "apiLevel", "deviceModel"]).',
          },
          'start_date': <String, Object?>{
            'type': 'string',
            'description':
                'Inclusive start date YYYY-MM-DD (defaults to 14 days ago).',
          },
          'end_date': <String, Object?>{
            'type': 'string',
            'description':
                'Exclusive end date YYYY-MM-DD (defaults to today UTC).',
          },
          'aggregation_period': <String, Object?>{
            'type': 'string',
            'enum': <String>['DAILY', 'HOURLY', 'FULL_RANGE'],
            'description': 'Timeline granularity (default DAILY).',
          },
          'user_cohort': <String, Object?>{
            'type': 'string',
            'enum': <String>['OS_PUBLIC', 'OS_BETA', 'APP_TESTERS'],
            'description':
                'Optional user cohort filter (not applicable to error_counts).',
          },
          'filter': <String, Object?>{
            'type': 'string',
            'description':
                'AIP-160 filter expression (e.g. "versionCode = 120 AND apiLevel = 34").',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Maximum rows per page (default 100).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['metric_set'],
      },
      handler: _handleQueryVitals,
    ),
    McpToolDefinition(
      name: 'search_error_issues_and_reports',
      description:
          'Searches grouped crash/ANR error issues (with stack traces) or raw individual error reports via Play Developer Reporting API.',
      annotations: const McpToolAnnotations(
        title: 'Search Error Issues & Reports',
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
            'enum': <String>['search_issues', 'search_reports'],
            'description':
                'Search grouped error issues or raw error reports (default search_issues).',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'start_time': <String, Object?>{
            'type': 'string',
            'description':
                'ISO-8601 UTC start timestamp (hour-aligned, defaults to 7 days ago).',
          },
          'end_time': <String, Object?>{
            'type': 'string',
            'description':
                'ISO-8601 UTC end timestamp (hour-aligned, defaults to current UTC hour).',
          },
          'filter': <String, Object?>{
            'type': 'string',
            'description':
                'AIP-160 filter (e.g. "errorIssueType = CRASH AND versionCode = 105").',
          },
          'order_by': <String, Object?>{
            'type': 'string',
            'description':
                'For search_issues: sort order (e.g. "errorReportCount desc").',
          },
          'sample_error_report_limit': <String, Object?>{
            'type': 'integer',
            'description':
                'For search_issues: number of sample error reports/stack traces to attach per issue.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size (default 25, max 100 for reports).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
      },
      handler: _handleSearchErrors,
    ),
    McpToolDefinition(
      name: 'list_vitals_anomalies',
      description:
          'Lists automated Play Console anomaly detection alerts across Android Vitals datasets.',
      annotations: const McpToolAnnotations(
        title: 'List Vitals Anomalies',
        readOnlyHint: true,
        destructiveHint: false,
        idempotentHint: true,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'filter': <String, Object?>{
            'type': 'string',
            'description': 'Optional AIP-160 filter expression.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size (default 50).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
      },
      handler: _handleListAnomalies,
    ),
  ];

  Future<Object?> _handleQueryVitals(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = optString(args, 'action') ?? 'query';
    final metricSetKey = reqString(args, 'metric_set');
    final spec = _metricSets[metricSetKey];
    if (spec == null) {
      throw ArgumentError('Unsupported metric_set: $metricSetKey');
    }

    if (action == 'describe') {
      return _apiClient.getJson(
        credentials: ctx.credentials,
        scopes: _scopes,
        baseUrl: PlayApiEndpoints.developerReporting,
        path: '/apps/$encodedPkg/${spec.resourceName}',
      );
    }

    if (action != 'query') {
      throw ArgumentError('Unsupported query_android_vitals action: $action');
    }

    final aggregationPeriod = optString(args, 'aggregation_period') ?? 'DAILY';
    final nowUtc = _clock().toUtc();
    final defaultStart = nowUtc.subtract(const Duration(days: 14));

    final startDateStr = optString(args, 'start_date');
    final endDateStr = optString(args, 'end_date');

    final startTime = _buildDateTimeObj(
      startDateStr != null
          ? _dateFromIso(startDateStr, 'start_date')
          : DateTime.utc(
              defaultStart.year,
              defaultStart.month,
              defaultStart.day,
            ),
      includeHourZero: aggregationPeriod == 'HOURLY',
    );
    final endTime = _buildDateTimeObj(
      endDateStr != null
          ? _dateFromIso(endDateStr, 'end_date')
          : DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day),
      includeHourZero: aggregationPeriod == 'HOURLY',
    );

    final metrics = optStringList(args, 'metrics') ?? spec.defaultMetrics;
    final dimensions = optStringList(args, 'dimensions');
    final filter = optString(args, 'filter');
    final userCohort = optString(args, 'user_cohort');
    final pageSize = optInt(args, 'page_size') ?? 100;
    final pageToken = optString(args, 'page_token');

    return _apiClient.postJson(
      credentials: ctx.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.developerReporting,
      path: '/apps/$encodedPkg/${spec.resourceName}:query',
      body: <String, Object?>{
        'timelineSpec': <String, Object?>{
          'aggregationPeriod': aggregationPeriod,
          'startTime': startTime,
          'endTime': endTime,
        },
        'metrics': metrics,
        if (dimensions != null && dimensions.isNotEmpty)
          'dimensions': dimensions,
        if (filter != null) 'filter': filter,
        if (spec.supportsUserCohort && userCohort != null)
          'userCohort': userCohort,
        'pageSize': pageSize,
        if (pageToken != null) 'pageToken': pageToken,
      },
    );
  }

  Future<Object?> _handleSearchErrors(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = optString(args, 'action') ?? 'search_issues';

    final nowUtc = _clock().toUtc();
    final alignedNow = DateTime.utc(
      nowUtc.year,
      nowUtc.month,
      nowUtc.day,
      nowUtc.hour,
    );
    final startUtc = _parseTimestampOrDefault(
      optString(args, 'start_time'),
      alignedNow.subtract(const Duration(days: 7)),
      'start_time',
    );
    final endUtc = _parseTimestampOrDefault(
      optString(args, 'end_time'),
      alignedNow,
      'end_time',
    );

    final query = <String, Object?>{
      'interval.startTime.year': startUtc.year,
      'interval.startTime.month': startUtc.month,
      'interval.startTime.day': startUtc.day,
      'interval.startTime.hours': startUtc.hour,
      'interval.startTime.timeZone.id': 'UTC',
      'interval.endTime.year': endUtc.year,
      'interval.endTime.month': endUtc.month,
      'interval.endTime.day': endUtc.day,
      'interval.endTime.hours': endUtc.hour,
      'interval.endTime.timeZone.id': 'UTC',
      if (optString(args, 'filter') case final filter?) 'filter': filter,
      'pageSize': optInt(args, 'page_size') ?? 25,
      if (optString(args, 'page_token') case final token?) 'pageToken': token,
    };

    if (action == 'search_issues') {
      if (optString(args, 'order_by') case final orderBy?) {
        query['orderBy'] = orderBy;
      }
      if (optInt(args, 'sample_error_report_limit') case final limit?) {
        query['sampleErrorReportLimit'] = limit;
      }
      return _apiClient.getJson(
        credentials: ctx.credentials,
        scopes: _scopes,
        baseUrl: PlayApiEndpoints.developerReporting,
        path: '/apps/$encodedPkg/errorIssues:search',
        query: query,
      );
    }

    if (action == 'search_reports') {
      return _apiClient.getJson(
        credentials: ctx.credentials,
        scopes: _scopes,
        baseUrl: PlayApiEndpoints.developerReporting,
        path: '/apps/$encodedPkg/errorReports:search',
        query: query,
      );
    }

    throw ArgumentError(
      'Unsupported search_error_issues_and_reports action: $action',
    );
  }

  Future<Object?> _handleListAnomalies(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    return _apiClient.getJson(
      credentials: ctx.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.developerReporting,
      path: '/apps/$encodedPkg/anomalies',
      query: <String, Object?>{
        if (optString(args, 'filter') case final filter?) 'filter': filter,
        'pageSize': optInt(args, 'page_size') ?? 50,
        if (optString(args, 'page_token') case final token?) 'pageToken': token,
      },
    );
  }

  DateTime _dateFromIso(String value, String fieldName) {
    final parsed = parseIsoDate(value, fieldName: fieldName);
    return DateTime.utc(parsed.year, parsed.month, parsed.day);
  }

  Map<String, Object?> _buildDateTimeObj(
    DateTime utc, {
    required bool includeHourZero,
  }) {
    return <String, Object?>{
      'year': utc.year,
      'month': utc.month,
      'day': utc.day,
      if (includeHourZero) ...<String, Object?>{
        'hours': 0,
        'timeZone': const <String, Object?>{'id': 'UTC'},
      },
    };
  }

  DateTime _parseTimestampOrDefault(
    String? raw,
    DateTime fallbackUtc,
    String fieldName,
  ) {
    if (raw == null) return fallbackUtc;
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) {
      throw ArgumentError.value(
        raw,
        fieldName,
        'Invalid ISO-8601 timestamp for "$fieldName": "$raw".',
      );
    }
    return parsed.toUtc();
  }
}
