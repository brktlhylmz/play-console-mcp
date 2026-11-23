import 'dart:convert';
import 'dart:io';

import 'package:play_console_mcp/play_console_mcp.dart';
import 'package:test/test.dart';

void main() {
  group('PlayProfileStore', () {
    late Directory tempDir;
    late String configPath;

    setUp(() {
      tempDir = Directory.systemTemp.createTempSync('play_console_mcp_test_');
      configPath = '${tempDir.path}/config.json';
    });

    tearDown(() {
      if (tempDir.existsSync()) {
        tempDir.deleteSync(recursive: true);
      }
    });

    test('saves, lists, switches default, and removes profiles', () {
      final store = PlayProfileStore(
        configFilePath: configPath,
        environment: const <String, String>{},
      );

      expect(store.listProfiles(), isEmpty);

      store.saveProfile(
        const PlayProfile(
          profileId: 'staging',
          label: 'Staging Account',
          serviceAccountPath: '~/keys/staging.json',
          defaultPackageName: 'com.example.staging',
          readOnly: false,
          allowProductionWrites: false,
        ),
      );

      store.saveProfile(
        const PlayProfile(
          profileId: 'prod',
          label: 'Production Account',
          serviceAccountPath: '/opt/keys/prod.json',
          defaultPackageName: 'com.example.app',
          developerId: '1234567890',
          gcsBucketId: 'pubsite_prod_rev_999',
          allowProductionWrites: true,
        ),
        makeDefault: true,
      );

      expect(store.getDefaultProfileId(), equals('prod'));
      expect(store.listProfiles().map((p) => p.profileId), <String>[
        'prod',
        'staging',
      ]);

      store.setDefaultProfile('staging');
      expect(store.getDefaultProfileId(), equals('staging'));

      final ctx = store.resolveContext();
      expect(ctx.profile?.profileId, equals('staging'));
      expect(ctx.defaultPackageName, equals('com.example.staging'));
      expect(
        ctx.credentials.source,
        equals(CredentialSource.profileServiceAccountFile),
      );
      expect(ctx.credentials.serviceAccountPath, equals('~/keys/staging.json'));

      expect(store.removeProfile('staging'), isTrue);
      expect(store.getDefaultProfileId(), equals('prod'));
    });

    test('resolves credential and safety env overrides cleanly', () {
      final saJson = jsonEncode(<String, Object?>{
        'type': 'service_account',
        'project_id': 'my-play-project',
        'client_email': 'play-bot@my-play-project.iam.gserviceaccount.com',
        'private_key': 'SECRET_PRIVATE_KEY_NEVER_EXPOSE',
      });

      final store = PlayProfileStore(
        configFilePath: configPath,
        environment: <String, String>{
          'HOME': tempDir.path,
          'PLAY_CONSOLE_SERVICE_ACCOUNT_JSON': saJson,
          'PLAY_CONSOLE_DEFAULT_PACKAGE': 'com.env.app',
          'PLAY_CONSOLE_DEVELOPER_ID': 'dev-42',
          'PLAY_CONSOLE_GCS_BUCKET': 'gs://pubsite_prod_rev_42',
          'PLAY_CONSOLE_READ_ONLY': 'true',
          'PLAY_CONSOLE_ALLOW_PRODUCTION_WRITES': 'false',
        },
      );

      final ctx = store.resolveContext();
      expect(
        ctx.credentials.source,
        equals(CredentialSource.envServiceAccountJson),
      );
      expect(ctx.readOnly, isTrue);
      expect(ctx.allowProductionWrites, isFalse);
      expect(ctx.requirePackageName(const <String, Object?>{}), 'com.env.app');
      expect(ctx.requireDeveloperId(const <String, Object?>{}), 'dev-42');
      expect(
        ctx.requireGcsBucket(const <String, Object?>{}),
        'pubsite_prod_rev_42',
      );

      final inspection = PlayAuthProvider().inspectCredentials(ctx.credentials);
      expect(inspection.error, isNull);
      expect(
        inspection.clientEmail,
        equals('play-bot@my-play-project.iam.gserviceaccount.com'),
      );
      expect(inspection.projectId, equals('my-play-project'));
      expect(
        jsonEncode(inspection.toJson()),
        isNot(contains('SECRET_PRIVATE_KEY_NEVER_EXPOSE')),
      );
    });

    test('falls back to GOOGLE_APPLICATION_CREDENTIALS and ADC', () {
      final gacStore = PlayProfileStore(
        configFilePath: configPath,
        environment: <String, String>{
          'GOOGLE_APPLICATION_CREDENTIALS': '/tmp/gac.json',
        },
      );
      expect(
        gacStore.resolveContext().credentials.source,
        equals(CredentialSource.envGoogleApplicationCredentials),
      );

      final adcStore = PlayProfileStore(
        configFilePath: configPath,
        environment: const <String, String>{},
      );
      expect(
        adcStore.resolveContext().credentials.source,
        equals(CredentialSource.applicationDefaultCredentials),
      );
    });
  });

  group('SafetyGuard', () {
    const creds = ResolvedCredentials(
      source: CredentialSource.applicationDefaultCredentials,
    );

    test('blocks writes in readOnly mode unless dryRun is true', () {
      const ctx = ResolvedPlayContext(credentials: creds, readOnly: true);

      expect(
        () => SafetyGuard.checkWrite(
          context: ctx,
          operation: 'edits.tracks.update',
        ),
        throwsA(isA<SafetyPolicyException>()),
      );

      expect(
        () => SafetyGuard.checkWrite(
          context: ctx,
          operation: 'edits.tracks.update',
          dryRun: true,
        ),
        returnsNormally,
      );
    });

    test(
      'blocks production/destructive writes unless confirmed or allowed',
      () {
        const lockedCtx = ResolvedPlayContext(
          credentials: creds,
          allowProductionWrites: false,
        );

        expect(
          () => SafetyGuard.checkWrite(
            context: lockedCtx,
            operation: 'orders.refund',
            isProductionOrDestructive: true,
          ),
          throwsA(isA<SafetyPolicyException>()),
        );

        expect(
          () => SafetyGuard.checkWrite(
            context: lockedCtx,
            operation: 'orders.refund',
            isProductionOrDestructive: true,
            confirmed: true,
          ),
          returnsNormally,
        );

        const allowedCtx = ResolvedPlayContext(
          credentials: creds,
          allowProductionWrites: true,
        );
        expect(
          () => SafetyGuard.checkWrite(
            context: allowedCtx,
            operation: 'orders.refund',
            isProductionOrDestructive: true,
          ),
          returnsNormally,
        );
      },
    );
  });
}
