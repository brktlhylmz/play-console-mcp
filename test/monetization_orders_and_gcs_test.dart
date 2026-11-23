import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:play_console_mcp/play_console_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('Monetization, Purchases, Orders, Operations & GCS Reports', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_monetization_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    PlayConsoleMcpApp buildApp(
      Future<http.Response> Function(http.Request) handler, {
      bool allowProductionWrites = false,
    }) {
      final store = PlayProfileStore(
        configFilePath: '${tempDir.path}/config.json',
        environment: <String, String>{
          'PLAY_CONSOLE_DEFAULT_PACKAGE': 'com.example.pay',
          'PLAY_CONSOLE_DEVELOPER_ID': 'dev-101',
          'PLAY_CONSOLE_GCS_BUCKET': 'pubsite_prod_rev_101',
          'PLAY_CONSOLE_ALLOW_PRODUCTION_WRITES': allowProductionWrites
              .toString(),
        },
      );
      return PlayConsoleMcpApp(
        profileStore: store,
        mockHttpClient: MockClient(handler),
      );
    }

    Future<Map<String, Object?>> callTool(
      PlayConsoleMcpApp app,
      String name,
      Map<String, Object?> args,
    ) async {
      final tool = app.server.tools.firstWhere((t) => t.name == name);
      return asJsonMap(await tool.handler(args));
    }

    test(
      'oneTimeProducts uses lowercase path on PATCH and camelCase on GET/DELETE',
      () async {
        final seen = <String>[];
        final app = buildApp((req) async {
          seen.add('${req.method} ${req.url.path}');
          return http.Response(jsonEncode({'productId': 'coins_100'}), 200);
        });
        addTearDown(app.close);

        await callTool(app, 'manage_one_time_products', <String, Object?>{
          'action': 'get',
          'product_id': 'coins_100',
        });
        await callTool(app, 'manage_one_time_products', <String, Object?>{
          'action': 'patch',
          'product_id': 'coins_100',
          'allow_missing': true,
          'product': <String, Object?>{'productId': 'coins_100'},
        });
        await callTool(app, 'manage_one_time_products', <String, Object?>{
          'action': 'delete',
          'product_id': 'coins_100',
          'confirm_destructive': true,
        });

        expect(seen, <String>[
          'GET /androidpublisher/v3/applications/com.example.pay/oneTimeProducts/coins_100',
          'PATCH /androidpublisher/v3/applications/com.example.pay/onetimeproducts/coins_100',
          'DELETE /androidpublisher/v3/applications/com.example.pay/oneTimeProducts/coins_100',
        ]);
      },
    );

    test(
      'convert_region_prices converts decimal amounts to exact units and nanos',
      () async {
        late Map<String, Object?> sentBody;
        final app = buildApp((req) async {
          sentBody = asJsonMap(jsonDecode(req.body));
          return http.Response(
            jsonEncode(<String, Object?>{
              'convertedRegionPrices': <String, Object?>{},
            }),
            200,
          );
        });
        addTearDown(app.close);

        await callTool(app, 'convert_region_prices', <String, Object?>{
          'currency_code': 'usd',
          'amount': 9.99,
        });

        final price = asJsonMap(sentBody['price']);
        expect(price['currencyCode'], equals('USD'));
        expect(price['units'], equals('9'));
        expect(price['nanos'], equals(990000000));
      },
    );

    test(
      'orders batch_get repeats orderIds and refund enforces destructive guard',
      () async {
        late Uri seenBatchUri;
        final app = buildApp((req) async {
          if (req.url.path.endsWith(':batchGet')) {
            seenBatchUri = req.url;
            return http.Response(jsonEncode({'orders': <Object?>[]}), 200);
          }
          if (req.url.path.endsWith(':refund')) {
            expect(req.url.queryParameters['revoke'], equals('true'));
            return http.Response('', 204);
          }
          return http.Response('', 500);
        });
        addTearDown(app.close);

        await callTool(app, 'manage_orders', <String, Object?>{
          'action': 'batch_get',
          'order_ids': <String>['GPA.1', 'GPA.2'],
        });
        expect(seenBatchUri.queryParametersAll['orderIds'], <String>[
          'GPA.1',
          'GPA.2',
        ]);

        await expectLater(
          callTool(app, 'manage_orders', <String, Object?>{
            'action': 'refund',
            'order_id': 'GPA.1',
            'revoke': true,
          }),
          throwsA(isA<SafetyPolicyException>()),
        );

        await callTool(app, 'manage_orders', <String, Object?>{
          'action': 'refund',
          'order_id': 'GPA.1',
          'revoke': true,
          'confirm_destructive': true,
        });
      },
    );

    test('app recovery deploy and delete_user honor safety guards', () async {
      final app = buildApp((req) async {
        return http.Response(jsonEncode({'ok': true}), 200);
      });
      addTearDown(app.close);

      await expectLater(
        callTool(app, 'manage_app_recovery', <String, Object?>{
          'action': 'deploy',
          'app_recovery_id': 'rec-1',
        }),
        throwsA(isA<SafetyPolicyException>()),
      );

      await callTool(app, 'manage_app_recovery', <String, Object?>{
        'action': 'deploy',
        'app_recovery_id': 'rec-1',
        'confirm_production': true,
      });

      await expectLater(
        callTool(app, 'manage_testers_and_team', <String, Object?>{
          'action': 'delete_user',
          'user_email': 'dev@example.com',
        }),
        throwsA(isA<SafetyPolicyException>()),
      );
    });

    test('decodes UTF-16LE BOM Play GCS CSV reports and computes totals', () async {
      const csvText =
          'Date,Package Name,"Country, Region",Daily Device Installs\r\n'
          '2026-11-20,com.example.pay,"Korea, South",120\r\n'
          '2026-11-21,com.example.pay,"United States",80\r\n';
      final utf16Bytes = <int>[0xFF, 0xFE];
      for (final unit in csvText.codeUnits) {
        utf16Bytes
          ..add(unit & 0xFF)
          ..add((unit >> 8) & 0xFF);
      }

      final app = buildApp((req) async {
        if (req.url.path == '/storage/v1/b/pubsite_prod_rev_101/o') {
          return http.Response(
            jsonEncode({
              'items': [
                {
                  'name':
                      'stats/installs/installs_com.example.pay_202611_overview.csv',
                  'size': '1024',
                },
                {
                  'name':
                      'stats/installs/installs_com.other.app_202610_overview.csv',
                  'size': '512',
                },
              ],
            }),
            200,
          );
        }
        if (req.url.path.contains('/o/stats%2Finstalls%2F')) {
          return http.Response.bytes(Uint8List.fromList(utf16Bytes), 200);
        }
        return http.Response('', 404);
      });
      addTearDown(app.close);

      final listRes =
          await callTool(app, 'query_play_gcs_reports', <String, Object?>{
            'action': 'list_reports',
            'category': 'installs',
            'package_name': 'com.example.pay',
            'year_month': '202611',
          });
      expect(listRes['count'], equals(1));

      final readRes =
          await callTool(app, 'query_play_gcs_reports', <String, Object?>{
            'action': 'read_report',
            'object_name':
                'stats/installs/installs_com.example.pay_202611_overview.csv',
          });
      expect(readRes['encoding'], equals('utf-16le'));
      expect(readRes['total_rows'], equals(2));
      final totals = asJsonMap(readRes['numeric_totals']);
      expect(totals['Daily Device Installs'], equals(200));
      final rows = tryAsJsonList(readRes['rows'])!;
      expect(asJsonMap(rows.first)['Country, Region'], equals('Korea, South'));
    });
  });
}
