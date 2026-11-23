import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:play_console_mcp/play_console_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('StoreListingTools & ReviewTools', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_store_review_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    PlayConsoleMcpApp buildApp(
      Future<http.Response> Function(http.Request) handler,
    ) {
      final store = PlayProfileStore(
        configFilePath: '${tempDir.path}/config.json',
        environment: const <String, String>{
          'PLAY_CONSOLE_DEFAULT_PACKAGE': 'com.example.shop',
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
      'validates 30/80/4000 char listing limits and syncs Fastlane dir',
      () async {
        final fastlaneDir = Directory(
          '${tempDir.path}/fastlane/metadata/android',
        );
        Directory('${fastlaneDir.path}/en-US').createSync(recursive: true);
        Directory('${fastlaneDir.path}/tr-TR').createSync(recursive: true);
        File(
          '${fastlaneDir.path}/en-US/title.txt',
        ).writeAsStringSync('Shop Mate');
        File(
          '${fastlaneDir.path}/en-US/short_description.txt',
        ).writeAsStringSync('Fast shopping tracker');
        File(
          '${fastlaneDir.path}/tr-TR/title.txt',
        ).writeAsStringSync('Alisveris Dostu');

        final patchedLocales = <String>[];
        final app = buildApp((req) async {
          if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
            return http.Response(jsonEncode({'id': 'edit-meta'}), 200);
          }
          if (req.method == 'PATCH' && req.url.path.contains('/listings/')) {
            final locale = req.url.pathSegments.last;
            patchedLocales.add(locale);
            return http.Response(req.body, 200);
          }
          if (req.method == 'POST' && req.url.path.endsWith(':commit')) {
            return http.Response(jsonEncode({'id': 'edit-meta'}), 200);
          }
          return http.Response('', 500);
        });
        addTearDown(app.close);

        await expectLater(
          callTool(app, 'manage_store_listings', <String, Object?>{
            'action': 'patch',
            'language': 'en-US',
            'title': 'This title is definitely longer than thirty characters',
          }),
          throwsA(isA<ArgumentError>()),
        );

        final synced = await callTool(
          app,
          'manage_store_listings',
          <String, Object?>{
            'action': 'sync_from_fastlane_dir',
            'metadata_dir': fastlaneDir.path,
          },
        );
        expect(patchedLocales, <String>['en-US', 'tr-TR']);
        expect(asJsonMap(synced['result'])['synced_locales'], <String>[
          'en-US',
          'tr-TR',
        ]);
      },
    );

    test('uploads store image with aiGeneratedState query param', () async {
      final pngFile = File('${tempDir.path}/shot1.png')
        ..writeAsBytesSync(const <int>[0x89, 0x50, 0x4E, 0x47]);

      String? seenAiState;
      String? seenContentType;
      final app = buildApp((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
          return http.Response(jsonEncode({'id': 'edit-img'}), 200);
        }
        if (req.method == 'POST' &&
            req.url.path.contains('/upload/') &&
            req.url.queryParameters['uploadType'] == 'media') {
          seenAiState = req.url.queryParameters['aiGeneratedState'];
          seenContentType = req.headers['Content-Type'];
          return http.Response(
            jsonEncode({
              'image': {'id': 'img-1'},
            }),
            200,
          );
        }
        if (req.method == 'POST' && req.url.path.endsWith(':commit')) {
          return http.Response(jsonEncode({'id': 'edit-img'}), 200);
        }
        return http.Response('', 500);
      });
      addTearDown(app.close);

      final res = await callTool(app, 'manage_store_images', <String, Object?>{
        'action': 'upload',
        'language': 'en-US',
        'image_type': 'phoneScreenshots',
        'file_path': pngFile.path,
        'ai_generated_state': 'aiGeneratedStateNotAiGenerated',
      });
      expect(seenAiState, equals('aiGeneratedStateNotAiGenerated'));
      expect(seenContentType, equals('image/png'));
      expect(
        asJsonMap(asJsonMap(res['result'])['image'])['id'],
        equals('img-1'),
      );
    });

    test(
      'filters reviews and enforces 350-char limit on reply_to_review',
      () async {
        final app = buildApp((req) async {
          if (req.method == 'GET' && req.url.path.endsWith('/reviews')) {
            return http.Response(
              jsonEncode({
                'reviews': [
                  {
                    'reviewId': 'r1',
                    'comments': [
                      {
                        'userComment': {'text': 'Crashes!', 'starRating': 1},
                      },
                    ],
                  },
                  {
                    'reviewId': 'r2',
                    'comments': [
                      {
                        'userComment': {'text': 'Good app', 'starRating': 5},
                      },
                      {
                        'developerComment': {'text': 'Thanks!'},
                      },
                    ],
                  },
                ],
              }),
              200,
            );
          }
          if (req.method == 'POST' &&
              req.url.path.endsWith('/reviews/r1:reply')) {
            return http.Response(
              jsonEncode({
                'result': {'replyText': 'Fixed in v1.2!'},
              }),
              200,
            );
          }
          return http.Response('', 500);
        });
        addTearDown(app.close);

        final listRes = await callTool(app, 'get_reviews', <String, Object?>{
          'action': 'list',
          'max_rating': 2,
          'unanswered_only': true,
        });
        expect(listRes['total_returned'], equals(1));
        expect(listRes['total_unfiltered_in_page'], equals(2));

        await expectLater(
          callTool(app, 'reply_to_review', <String, Object?>{
            'review_id': 'r1',
            'reply_text': 'a' * 351,
          }),
          throwsA(isA<ArgumentError>()),
        );

        final replyRes = await callTool(
          app,
          'reply_to_review',
          <String, Object?>{'review_id': 'r1', 'reply_text': 'Fixed in v1.2!'},
        );
        expect(
          asJsonMap(replyRes['result'])['replyText'],
          equals('Fixed in v1.2!'),
        );
      },
    );
  });
}
