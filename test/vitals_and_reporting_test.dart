import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:play_console_mcp/play_console_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('VitalsTools & Developer Reporting API', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_vitals_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('routes all 10 Android Vitals metric sets accurately', () async {
      final capturedPaths = <String>[];
      final capturedBodies = <String, Map<String, Object?>>{};
      final store = PlayProfileStore(
        configFilePath: '${tempDir.path}/config.json',
        environment: const <String, String>{
          'PLAY_CONSOLE_DEFAULT_PACKAGE': 'com.example.vitals',
        },
      );
      final app = PlayConsoleMcpApp(
        profileStore: store,
        clock: () => DateTime.utc(2026, 11, 22, 15, 30),
        mockHttpClient: MockClient((req) async {
          capturedPaths.add(req.url.path);
          if (req.body.isNotEmpty) {
            capturedBodies[req.url.path] = asJsonMap(jsonDecode(req.body));
          }
          return http.Response(jsonEncode({'rows': <Object?>[]}), 200);
        }),
      );
      addTearDown(app.close);

      final tool = app.server.tools.firstWhere(
        (t) => t.name == 'query_android_vitals',
      );

      final expectedResources = <String, String>{
        'crash_rate': 'crashRateMetricSet',
        'anr_rate': 'anrRateMetricSet',
        'slow_start_rate': 'slowStartRateMetricSet',
        'slow_rendering_rate': 'slowRenderingRateMetricSet',
        'excessive_wakeup_rate': 'excessiveWakeupRateMetricSet',
        'stuck_background_wakelock_rate':
            'stuckBackgroundWakelockRateMetricSet',
        'lmk_rate': 'lmkRateMetricSet',
        'anon_rss_memory': 'anonRssAndSwapMemoryUsageMetricSet',
        'bitmap_memory': 'bitmapMemoryUsageMetricSet',
        'error_counts': 'errorCountMetricSet',
      };

      for (final entry in expectedResources.entries) {
        await tool.handler(<String, Object?>{
          'metric_set': entry.key,
          'user_cohort': 'OS_PUBLIC',
          'dimensions': <String>['versionCode'],
        });
        final expectedPath =
            '/v1beta1/apps/com.example.vitals/${entry.value}:query';
        expect(capturedPaths, contains(expectedPath));
        final body = capturedBodies[expectedPath]!;
        if (entry.key == 'error_counts') {
          expect(body.containsKey('userCohort'), isFalse);
        } else {
          expect(body['userCohort'], equals('OS_PUBLIC'));
        }
      }
    });

    test(
      'encodes hour-aligned UTC interval query params for error issues & anomalies',
      () async {
        late Uri seenIssuesUri;
        late Uri seenAnomaliesUri;
        final store = PlayProfileStore(
          configFilePath: '${tempDir.path}/config.json',
          environment: const <String, String>{
            'PLAY_CONSOLE_DEFAULT_PACKAGE': 'com.example.vitals',
          },
        );
        final app = PlayConsoleMcpApp(
          profileStore: store,
          clock: () => DateTime.utc(2026, 11, 22, 15, 45),
          mockHttpClient: MockClient((req) async {
            if (req.url.path.endsWith('errorIssues:search')) {
              seenIssuesUri = req.url;
              return http.Response(
                jsonEncode({'errorIssues': <Object?>[]}),
                200,
              );
            }
            if (req.url.path.endsWith('/anomalies')) {
              seenAnomaliesUri = req.url;
              return http.Response(jsonEncode({'anomalies': <Object?>[]}), 200);
            }
            return http.Response('', 500);
          }),
        );
        addTearDown(app.close);

        final searchTool = app.server.tools.firstWhere(
          (t) => t.name == 'search_error_issues_and_reports',
        );
        await searchTool.handler(<String, Object?>{
          'action': 'search_issues',
          'filter': 'errorIssueType = CRASH',
          'order_by': 'errorReportCount desc',
          'sample_error_report_limit': 2,
        });

        expect(
          seenIssuesUri.queryParameters['interval.startTime.year'],
          equals('2026'),
        );
        expect(
          seenIssuesUri.queryParameters['interval.startTime.day'],
          equals('15'),
        );
        expect(
          seenIssuesUri.queryParameters['interval.endTime.hours'],
          equals('15'),
        );
        expect(
          seenIssuesUri.queryParameters['interval.startTime.timeZone.id'],
          equals('UTC'),
        );
        expect(
          seenIssuesUri.queryParameters['sampleErrorReportLimit'],
          equals('2'),
        );

        final anomaliesTool = app.server.tools.firstWhere(
          (t) => t.name == 'list_vitals_anomalies',
        );
        await anomaliesTool.handler(const <String, Object?>{});
        expect(
          seenAnomaliesUri.path,
          equals('/v1beta1/apps/com.example.vitals/anomalies'),
        );
      },
    );
  });
}
