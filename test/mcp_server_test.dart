import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:play_console_mcp/play_console_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('McpServer JSON-RPC 2.0 protocol', () {
    late Directory tempDir;
    late PlayConsoleMcpApp app;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_mcp_server_test_');
      final store = PlayProfileStore(
        configFilePath: '${tempDir.path}/config.json',
        environment: const <String, String>{},
      );
      final mockClient = MockClient((request) async {
        return http.Response(
          jsonEncode(<String, Object?>{
            'apps': <Object?>[
              <String, Object?>{
                'name': 'apps/com.example.demo',
                'packageName': 'com.example.demo',
                'displayName': 'Demo App',
              },
            ],
          }),
          200,
        );
      });
      app = PlayConsoleMcpApp(profileStore: store, mockHttpClient: mockClient);
    });

    tearDown(() {
      app.close();
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    Future<List<Map<String, Object?>>> runSession(
      List<Map<String, Object?>> messages,
    ) async {
      final controller = StreamController<List<int>>();
      final output = StringBuffer();
      final future = app.server.serve(input: controller.stream, output: output);
      for (final msg in messages) {
        controller.add(utf8.encode('${jsonEncode(msg)}\n'));
      }
      await controller.close();
      await future;

      final lines = const LineSplitter().convert(output.toString());
      return lines
          .where((l) => l.trim().isNotEmpty)
          .map((l) => asJsonMap(jsonDecode(l)))
          .toList(growable: false);
    }

    test(
      'handles initialize, notifications, ping, tools/list (25), prompts',
      () async {
        final responses = await runSession(<Map<String, Object?>>[
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 1,
            'method': 'initialize',
            'params': <String, Object?>{
              'protocolVersion': '2025-03-26',
              'capabilities': const <String, Object?>{},
            },
          },
          const <String, Object?>{
            'jsonrpc': '2.0',
            'method': 'notifications/initialized',
          },
          const <String, Object?>{'jsonrpc': '2.0', 'id': 2, 'method': 'ping'},
          const <String, Object?>{
            'jsonrpc': '2.0',
            'id': 3,
            'method': 'tools/list',
          },
          const <String, Object?>{
            'jsonrpc': '2.0',
            'id': 4,
            'method': 'prompts/list',
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 5,
            'method': 'prompts/get',
            'params': <String, Object?>{
              'name': 'release_readiness_audit',
              'arguments': <String, Object?>{
                'package_name': 'com.example.demo',
                'track': 'production',
              },
            },
          },
          <String, Object?>{
            'jsonrpc': '2.0',
            'id': 6,
            'method': 'tools/call',
            'params': <String, Object?>{
              'name': 'list_accessible_apps',
              'arguments': const <String, Object?>{},
            },
          },
          const <String, Object?>{
            'jsonrpc': '2.0',
            'id': 7,
            'method': 'unknown/method',
          },
        ]);

        // Notification must NOT emit a response; 7 request IDs -> 7 responses.
        expect(responses.length, equals(7));

        final init = asJsonMap(responses[0]['result']);
        expect(init['protocolVersion'], equals('2025-03-26'));
        expect(
          asJsonMap(init['serverInfo'])['name'],
          equals('play-console-mcp'),
        );
        expect(init['instructions'], isNotNull);

        expect(responses[1]['result'], isA<Map<Object?, Object?>>());

        final toolsList = tryAsJsonList(
          asJsonMap(responses[2]['result'])['tools'],
        );
        expect(toolsList, isNotNull);
        expect(toolsList!.length, equals(25));
        for (final item in toolsList) {
          final tool = asJsonMap(item);
          expect(optString(tool, 'name'), isNotNull);
          expect(optString(tool, 'description'), isNotNull);
          expect(tryAsJsonMap(tool['inputSchema']), isNotNull);
          expect(tryAsJsonMap(tool['annotations']), isNotNull);
        }

        final promptsList = tryAsJsonList(
          asJsonMap(responses[3]['result'])['prompts'],
        );
        expect(promptsList, isNotNull);
        expect(promptsList!.length, equals(4));

        final promptGet = asJsonMap(responses[4]['result']);
        final messages = tryAsJsonList(promptGet['messages']);
        expect(messages, isNotEmpty);

        final toolCall = asJsonMap(responses[5]['result']);
        expect(toolCall['isError'], isFalse);
        final content = tryAsJsonList(toolCall['content'])!;
        expect(
          optString(asJsonMap(content.first), 'text'),
          contains('com.example.demo'),
        );

        final unknownMethodErr = asJsonMap(responses[6]['error']);
        expect(unknownMethodErr['code'], equals(-32601));
      },
    );

    test('returns isError=true when tool throws an exception', () async {
      final responses = await runSession(<Map<String, Object?>>[
        <String, Object?>{
          'jsonrpc': '2.0',
          'id': 10,
          'method': 'tools/call',
          'params': <String, Object?>{
            'name': 'manage_orders',
            'arguments': <String, Object?>{
              'action': 'refund',
              'package_name': 'com.example.demo',
              'order_id': 'GPA.1234',
            },
          },
        },
      ]);

      final result = asJsonMap(responses.single['result']);
      expect(result['isError'], isTrue);
      final text = optString(
        asJsonMap(tryAsJsonList(result['content'])!.first),
        'text',
      );
      expect(text, contains('allow_production_writes'));
    });
  });
}
