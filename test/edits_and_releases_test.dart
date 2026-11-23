import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:play_console_mcp/play_console_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('EditsService & ReleaseTools', () {
    late Directory tempDir;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_release_test_');
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    PlayConsoleMcpApp buildApp(
      Future<http.Response> Function(http.Request) handler, {
      bool allowProductionWrites = false,
      bool readOnly = false,
    }) {
      final store = PlayProfileStore(
        configFilePath: '${tempDir.path}/config.json',
        environment: <String, String>{
          'PLAY_CONSOLE_DEFAULT_PACKAGE': 'com.example.game',
          'PLAY_CONSOLE_READ_ONLY': readOnly.toString(),
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
      final res = await tool.handler(args);
      return asJsonMap(res);
    }

    test(
      'atomic edit commits with ERROR_IF_IN_REVIEW and changesNotSentForReview',
      () async {
        final requests = <String>[];
        final app = buildApp((req) async {
          requests.add('${req.method} ${req.url.path}?${req.url.query}');
          if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
            return http.Response(jsonEncode({'id': 'edit-100'}), 200);
          }
          if (req.method == 'PUT' && req.url.path.endsWith('/tracks/beta')) {
            return http.Response(req.body, 200);
          }
          if (req.method == 'POST' &&
              req.url.path.endsWith('/edits/edit-100:commit')) {
            expect(
              req.url.queryParameters['changesNotSentForReview'],
              equals('true'),
            );
            expect(
              req.url.queryParameters['changesInReviewBehavior'],
              equals('ERROR_IF_IN_REVIEW'),
            );
            return http.Response(jsonEncode({'id': 'edit-100'}), 200);
          }
          return http.Response('Unexpected ${req.method} ${req.url}', 500);
        });
        addTearDown(app.close);

        final result = await callTool(
          app,
          'manage_track_release',
          <String, Object?>{
            'action': 'update_track',
            'track': 'beta',
            'version_codes': <int>[42],
            'status': 'inProgress',
            'user_fraction': 0.25,
            'in_app_update_priority': 3,
            'release_notes': <String, String>{
              'en-US': 'Performance improvements',
            },
            'changes_not_sent_for_review': true,
          },
        );

        expect(result['mode'], equals('committed'));
        expect(result['edit_id'], equals('edit-100'));
        final updatedTrack = asJsonMap(result['result']);
        expect(updatedTrack['track'], equals('beta'));
        expect(requests.length, equals(3));
      },
    );

    test(
      'dry_run validates edit and deletes it without committing even in readOnly mode',
      () async {
        final ops = <String>[];
        final app = buildApp((req) async {
          ops.add('${req.method} ${req.url.path}');
          if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
            return http.Response(jsonEncode({'id': 'edit-dry'}), 200);
          }
          if (req.method == 'PUT' &&
              req.url.path.endsWith('/tracks/production')) {
            return http.Response(req.body, 200);
          }
          if (req.method == 'POST' &&
              req.url.path.endsWith('/edits/edit-dry:validate')) {
            return http.Response(jsonEncode({'id': 'edit-dry'}), 200);
          }
          if (req.method == 'DELETE' &&
              req.url.path.endsWith('/edits/edit-dry')) {
            return http.Response('', 204);
          }
          return http.Response('Unexpected ${req.method} ${req.url.path}', 500);
        }, readOnly: true);
        addTearDown(app.close);

        final result = await callTool(
          app,
          'manage_track_release',
          <String, Object?>{
            'action': 'update_track',
            'track': 'production',
            'version_codes': <int>[101],
            'status': 'completed',
            'dry_run': true,
          },
        );

        expect(result['mode'], equals('dry_run_validated_and_discarded'));
        expect(ops, <String>[
          'POST /androidpublisher/v3/applications/com.example.game/edits',
          'PUT /androidpublisher/v3/applications/com.example.game/edits/edit-dry/tracks/production',
          'POST /androidpublisher/v3/applications/com.example.game/edits/edit-dry:validate',
          'DELETE /androidpublisher/v3/applications/com.example.game/edits/edit-dry',
        ]);
      },
    );

    test('rolls back temporary edit if mid-edit request fails', () async {
      var deleted = false;
      final app = buildApp((req) async {
        if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
          return http.Response(jsonEncode({'id': 'edit-err'}), 200);
        }
        if (req.method == 'PUT') {
          return http.Response(
            jsonEncode({
              'error': {'code': 400, 'message': 'Invalid version code'},
            }),
            400,
          );
        }
        if (req.method == 'DELETE' &&
            req.url.path.endsWith('/edits/edit-err')) {
          deleted = true;
          return http.Response('', 204);
        }
        return http.Response('', 500);
      });
      addTearDown(app.close);

      await expectLater(
        callTool(app, 'manage_track_release', <String, Object?>{
          'action': 'update_track',
          'track': 'internal',
          'version_codes': <int>[999],
          'status': 'completed',
        }),
        throwsA(isA<PlayApiException>()),
      );
      expect(deleted, isTrue);
    });

    test(
      'protects production promote_release and supports resumable AAB upload',
      () async {
        final aabFile = File('${tempDir.path}/app-release.aab')
          ..writeAsBytesSync(const <int>[1, 2, 3, 4, 5]);

        final app = buildApp((req) async {
          if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
            return http.Response(jsonEncode({'id': 'edit-up'}), 200);
          }
          if (req.method == 'POST' &&
              req.url.path.contains('/resumable/upload/') &&
              req.url.queryParameters['uploadType'] == 'resumable') {
            expect(req.headers['X-Upload-Content-Length'], equals('5'));
            return http.Response(
              '',
              200,
              headers: <String, String>{
                'location':
                    'https://androidpublisher.googleapis.com/resumable/upload/session-abc',
              },
            );
          }
          if (req.method == 'PUT' && req.url.path.endsWith('/session-abc')) {
            expect(req.bodyBytes, equals(<int>[1, 2, 3, 4, 5]));
            return http.Response(
              jsonEncode({'versionCode': 123, 'sha256': 'deadbeef'}),
              200,
            );
          }
          if (req.method == 'GET' && req.url.path.endsWith('/tracks/beta')) {
            return http.Response(
              jsonEncode({
                'track': 'beta',
                'releases': [
                  {
                    'versionCodes': ['123'],
                    'status': 'completed',
                  },
                ],
              }),
              200,
            );
          }
          if (req.method == 'PUT' &&
              req.url.path.endsWith('/tracks/production')) {
            return http.Response(req.body, 200);
          }
          if (req.method == 'POST' && req.url.path.endsWith(':commit')) {
            return http.Response(jsonEncode({'id': 'edit-up'}), 200);
          }
          return http.Response('Unexpected ${req.method} ${req.url}', 500);
        });
        addTearDown(app.close);

        // Resumable bundle upload works without production confirmation.
        final uploadRes = await callTool(
          app,
          'upload_app_artifact',
          <String, Object?>{
            'action': 'upload_bundle',
            'file_path': aabFile.path,
          },
        );
        expect(asJsonMap(uploadRes['result'])['versionCode'], equals(123));

        // Promote to production is blocked by default...
        await expectLater(
          callTool(app, 'manage_track_release', <String, Object?>{
            'action': 'promote_release',
            'source_track': 'beta',
            'target_track': 'production',
            'user_fraction': 0.1,
          }),
          throwsA(isA<SafetyPolicyException>()),
        );

        // ...and succeeds when confirm_production: true is provided.
        final promoted =
            await callTool(app, 'manage_track_release', <String, Object?>{
              'action': 'promote_release',
              'source_track': 'beta',
              'target_track': 'production',
              'user_fraction': 0.1,
              'confirm_production': true,
            });
        final releases = tryAsJsonList(
          asJsonMap(promoted['result'])['releases'],
        )!;
        final firstRelease = asJsonMap(releases.first);
        expect(firstRelease['status'], equals('inProgress'));
        expect(firstRelease['userFraction'], equals(0.1));
      },
    );

    test(
      'halt, resume, and complete rollout mutate release states cleanly',
      () async {
        var currentRelease = <String, Object?>{
          'versionCodes': <String>['200'],
          'status': 'inProgress',
          'userFraction': 0.2,
        };
        final app = buildApp((req) async {
          if (req.method == 'POST' && req.url.path.endsWith('/edits')) {
            return http.Response(jsonEncode({'id': 'e1'}), 200);
          }
          if (req.method == 'GET' &&
              req.url.path.endsWith('/tracks/production')) {
            return http.Response(
              jsonEncode({
                'track': 'production',
                'releases': [currentRelease],
              }),
              200,
            );
          }
          if (req.method == 'PUT' &&
              req.url.path.endsWith('/tracks/production')) {
            final body = asJsonMap(jsonDecode(req.body));
            currentRelease = asJsonMap(tryAsJsonList(body['releases'])!.first);
            return http.Response(req.body, 200);
          }
          if (req.method == 'POST' && req.url.path.endsWith(':commit')) {
            return http.Response(jsonEncode({'id': 'e1'}), 200);
          }
          return http.Response('', 500);
        }, allowProductionWrites: true);
        addTearDown(app.close);

        await callTool(app, 'manage_track_release', <String, Object?>{
          'action': 'halt_rollout',
          'track': 'production',
        });
        expect(currentRelease['status'], equals('halted'));

        await callTool(app, 'manage_track_release', <String, Object?>{
          'action': 'resume_rollout',
          'track': 'production',
        });
        expect(currentRelease['status'], equals('inProgress'));
        expect(currentRelease['userFraction'], equals(0.2));

        await callTool(app, 'manage_track_release', <String, Object?>{
          'action': 'complete_rollout',
          'track': 'production',
        });
        expect(currentRelease['status'], equals('completed'));
        expect(currentRelease.containsKey('userFraction'), isFalse);
      },
    );
  });
}
