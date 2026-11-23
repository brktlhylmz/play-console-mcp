import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

/// Monetization catalog tools: subscriptions, base plans, subscription offers,
/// modern one-time products (with legacy `inappproducts` read-only fallback),
/// and Play regional price conversion.
final class MonetizationTools {
  MonetizationTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
  }) : _profileStore = profileStore,
       _apiClient = apiClient;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;

  static const List<String> _scopes = <String>[PlayScopes.androidPublisher];
  static const String _defaultRegionsVersion = '2022/02';

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'manage_subscriptions',
      description:
          'Manages Google Play subscriptions and base plans (list, get, create, patch, delete, activate_base_plan, deactivate_base_plan, delete_base_plan, migrate_prices).',
      annotations: const McpToolAnnotations(
        title: 'Manage Subscriptions & Base Plans',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'list',
              'get',
              'create',
              'patch',
              'delete',
              'activate_base_plan',
              'deactivate_base_plan',
              'delete_base_plan',
              'migrate_prices',
            ],
            'description': 'Subscription or base plan action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'product_id': <String, Object?>{
            'type': 'string',
            'description': 'Subscription productId.',
          },
          'base_plan_id': <String, Object?>{
            'type': 'string',
            'description': 'Target basePlanId for base plan actions.',
          },
          'subscription': <String, Object?>{
            'type': 'object',
            'description': 'Subscription JSON payload for create/patch.',
          },
          'regional_price_migrations': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'object'},
            'description':
                'Array of RegionalPriceMigrationConfig for migrate_prices.',
          },
          'regions_version': <String, Object?>{
            'type': 'string',
            'description':
                'Google Play regionsVersion string (default 2022/02).',
          },
          'update_mask': <String, Object?>{
            'type': 'string',
            'description': 'Optional comma-separated updateMask for patch.',
          },
          'allow_missing': <String, Object?>{
            'type': 'boolean',
            'description': 'Allow patch to create if productId does not exist.',
          },
          'latency_tolerance': <String, Object?>{
            'type': 'string',
            'description': 'Optional latencyTolerance enum.',
          },
          'show_archived': <String, Object?>{
            'type': 'boolean',
            'description': 'Include archived subscriptions when listing.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size for list (default 100).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token for list.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for delete, delete_base_plan, deactivate_base_plan, or migrate_prices when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageSubscriptions,
    ),
    McpToolDefinition(
      name: 'manage_subscription_offers',
      description:
          'Manages base plan subscription offers (introductory pricing, free trials, promo codes): list, get, create, patch, activate, deactivate, delete.',
      annotations: const McpToolAnnotations(
        title: 'Manage Subscription Offers',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'list',
              'get',
              'create',
              'patch',
              'activate',
              'deactivate',
              'delete',
            ],
            'description': 'Subscription offer action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'product_id': <String, Object?>{
            'type': 'string',
            'description': 'Subscription productId.',
          },
          'base_plan_id': <String, Object?>{
            'type': 'string',
            'description': 'Parent basePlanId.',
          },
          'offer_id': <String, Object?>{
            'type': 'string',
            'description': 'Subscription offerId.',
          },
          'offer': <String, Object?>{
            'type': 'object',
            'description': 'SubscriptionOffer JSON payload for create/patch.',
          },
          'regions_version': <String, Object?>{
            'type': 'string',
            'description': 'Regions version (default 2022/02).',
          },
          'update_mask': <String, Object?>{
            'type': 'string',
            'description': 'Optional updateMask for patch.',
          },
          'allow_missing': <String, Object?>{
            'type': 'boolean',
            'description': 'Allow patch to create if missing.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size for list (default 100).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token for list.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for delete/deactivate when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action', 'product_id', 'base_plan_id'],
      },
      handler: _handleManageSubscriptionOffers,
    ),
    McpToolDefinition(
      name: 'manage_one_time_products',
      description:
          'Manages modern Google Play One-Time Products (purchaseOptions and offers) — replacing deprecated inappproducts writes — plus legacy_list / legacy_get read fallback.',
      annotations: const McpToolAnnotations(
        title: 'Manage One-Time Products',
        readOnlyHint: false,
        destructiveHint: true,
        idempotentHint: false,
        openWorldHint: true,
      ),
      inputSchema: const <String, Object?>{
        'type': 'object',
        'properties': <String, Object?>{
          'action': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'list',
              'get',
              'patch',
              'delete',
              'update_purchase_options_state',
              'list_offers',
              'activate_offer',
              'deactivate_offer',
              'cancel_offer',
              'legacy_list',
              'legacy_get',
            ],
            'description': 'One-time product action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'product_id': <String, Object?>{
            'type': 'string',
            'description': 'One-time productId (or legacy SKU).',
          },
          'purchase_option_id': <String, Object?>{
            'type': 'string',
            'description': 'Purchase option ID for offer actions.',
          },
          'offer_id': <String, Object?>{
            'type': 'string',
            'description': 'Offer ID for activate/deactivate/cancel_offer.',
          },
          'product': <String, Object?>{
            'type': 'object',
            'description': 'OneTimeProduct JSON payload for patch.',
          },
          'requests': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'object'},
            'description':
                'Array of UpdatePurchaseOptionStateRequest objects for update_purchase_options_state.',
          },
          'regions_version': <String, Object?>{
            'type': 'string',
            'description': 'Regions version (default 2022/02).',
          },
          'update_mask': <String, Object?>{
            'type': 'string',
            'description': 'Optional updateMask for patch.',
          },
          'allow_missing': <String, Object?>{
            'type': 'boolean',
            'description': 'Allow patch to create a new one-time product.',
          },
          'latency_tolerance': <String, Object?>{
            'type': 'string',
            'description': 'Optional latencyTolerance enum.',
          },
          'page_size': <String, Object?>{
            'type': 'integer',
            'description': 'Page size for list actions (default 100).',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for delete/cancel_offer/deactivate_offer when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageOneTimeProducts,
    ),
    McpToolDefinition(
      name: 'convert_region_prices',
      description:
          'Converts a base monetary price (e.g. 9.99 USD) into Google Play regional prices across all supported countries using current exchange rates and local pricing patterns.',
      annotations: const McpToolAnnotations(
        title: 'Convert Regional Play Prices',
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
          'currency_code': <String, Object?>{
            'type': 'string',
            'description': 'ISO 4217 base currency code (e.g. USD, EUR, TRY).',
          },
          'amount': <String, Object?>{
            'type': 'number',
            'description': 'Decimal price amount (e.g. 9.99).',
          },
          'product_tax_category_code': <String, Object?>{
            'type': 'string',
            'description': 'Optional Play productTaxCategoryCode.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['currency_code', 'amount'],
      },
      handler: _handleConvertRegionPrices,
    ),
  ];

  Future<Object?> _handleManageSubscriptions(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);
    final regionsVersion = optString(args, 'regions_version');

    switch (action) {
      case 'list':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/subscriptions',
          query: <String, Object?>{
            'pageSize': optInt(args, 'page_size') ?? 100,
            if (optString(args, 'page_token') case final t?) 'pageToken': t,
            if (optBool(args, 'show_archived') case final sa?)
              'showArchived': sa,
          },
        );

      case 'get':
        final productId = reqString(args, 'product_id');
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}',
        );

      case 'create':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.create ($packageName)',
        );
        final productId = reqString(args, 'product_id');
        final body = optJsonMap(args, 'subscription');
        if (body == null) {
          throw ArgumentError('Missing required "subscription" object.');
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/subscriptions',
          query: <String, Object?>{
            'productId': productId,
            'regionsVersion.version': regionsVersion ?? _defaultRegionsVersion,
          },
          body: body,
        );

      case 'patch':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.patch ($packageName)',
        );
        final productId = reqString(args, 'product_id');
        final body = optJsonMap(args, 'subscription');
        if (body == null) {
          throw ArgumentError('Missing required "subscription" object.');
        }
        return _apiClient.patchJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}',
          query: <String, Object?>{
            'regionsVersion.version': regionsVersion ?? _defaultRegionsVersion,
            if (optString(args, 'update_mask') case final mask?)
              'updateMask': mask,
            if (optBool(args, 'allow_missing') case final am?)
              'allowMissing': am,
            if (optString(args, 'latency_tolerance') case final lt?)
              'latencyTolerance': lt,
          },
          body: body,
        );

      case 'delete':
        final productId = reqString(args, 'product_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.delete ($productId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.deleteJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}',
        );

      case 'activate_base_plan':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.basePlans.activate',
        );
        final productId = reqString(args, 'product_id');
        final basePlanId = reqString(args, 'base_plan_id');
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}/basePlans/${Uri.encodeComponent(basePlanId)}:activate',
          body: const <String, Object?>{},
        );

      case 'deactivate_base_plan':
        final productId = reqString(args, 'product_id');
        final basePlanId = reqString(args, 'base_plan_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.subscriptions.basePlans.deactivate ($productId/$basePlanId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}/basePlans/${Uri.encodeComponent(basePlanId)}:deactivate',
          body: const <String, Object?>{},
        );

      case 'delete_base_plan':
        final productId = reqString(args, 'product_id');
        final basePlanId = reqString(args, 'base_plan_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.subscriptions.basePlans.delete ($productId/$basePlanId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.deleteJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}/basePlans/${Uri.encodeComponent(basePlanId)}',
        );

      case 'migrate_prices':
        final productId = reqString(args, 'product_id');
        final basePlanId = reqString(args, 'base_plan_id');
        final migrations = tryAsJsonList(args['regional_price_migrations']);
        if (migrations == null || migrations.isEmpty) {
          throw ArgumentError(
            'Missing required "regional_price_migrations" array for migrate_prices.',
          );
        }
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.subscriptions.basePlans.migratePrices ($productId/$basePlanId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/subscriptions/${Uri.encodeComponent(productId)}/basePlans/${Uri.encodeComponent(basePlanId)}:migratePrices',
          body: <String, Object?>{
            'packageName': packageName,
            'productId': productId,
            'basePlanId': basePlanId,
            'regionsVersion': <String, Object?>{
              'version': regionsVersion ?? _defaultRegionsVersion,
            },
            'regionalPriceMigrations': migrations,
            if (optString(args, 'latency_tolerance') case final lt?)
              'latencyTolerance': lt,
          },
        );

      default:
        throw ArgumentError('Unsupported manage_subscriptions action: $action');
    }
  }

  Future<Object?> _handleManageSubscriptionOffers(
    Map<String, Object?> args,
  ) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final productId = Uri.encodeComponent(reqString(args, 'product_id'));
    final basePlanId = Uri.encodeComponent(reqString(args, 'base_plan_id'));
    final basePath =
        '/applications/$encodedPkg/subscriptions/$productId/basePlans/$basePlanId/offers';
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);
    final regionsVersion =
        optString(args, 'regions_version') ?? _defaultRegionsVersion;

    switch (action) {
      case 'list':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: basePath,
          query: <String, Object?>{
            'pageSize': optInt(args, 'page_size') ?? 100,
            if (optString(args, 'page_token') case final t?) 'pageToken': t,
          },
        );

      case 'get':
        final offerId = Uri.encodeComponent(reqString(args, 'offer_id'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '$basePath/$offerId',
        );

      case 'create':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.basePlans.offers.create',
        );
        final offerId = reqString(args, 'offer_id');
        final body = optJsonMap(args, 'offer');
        if (body == null) {
          throw ArgumentError('Missing required "offer" object.');
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: basePath,
          query: <String, Object?>{
            'offerId': offerId,
            'regionsVersion.version': regionsVersion,
          },
          body: body,
        );

      case 'patch':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.basePlans.offers.patch',
        );
        final offerId = Uri.encodeComponent(reqString(args, 'offer_id'));
        final body = optJsonMap(args, 'offer');
        if (body == null) {
          throw ArgumentError('Missing required "offer" object.');
        }
        return _apiClient.patchJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '$basePath/$offerId',
          query: <String, Object?>{
            'regionsVersion.version': regionsVersion,
            if (optString(args, 'update_mask') case final mask?)
              'updateMask': mask,
            if (optBool(args, 'allow_missing') case final am?)
              'allowMissing': am,
          },
          body: body,
        );

      case 'activate':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.subscriptions.basePlans.offers.activate',
        );
        final offerId = Uri.encodeComponent(reqString(args, 'offer_id'));
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '$basePath/$offerId:activate',
          body: const <String, Object?>{},
        );

      case 'deactivate':
        final offerId = reqString(args, 'offer_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.subscriptions.basePlans.offers.deactivate ($offerId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '$basePath/${Uri.encodeComponent(offerId)}:deactivate',
          body: const <String, Object?>{},
        );

      case 'delete':
        final offerId = reqString(args, 'offer_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.subscriptions.basePlans.offers.delete ($offerId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.deleteJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '$basePath/${Uri.encodeComponent(offerId)}',
        );

      default:
        throw ArgumentError(
          'Unsupported manage_subscription_offers action: $action',
        );
    }
  }

  Future<Object?> _handleManageOneTimeProducts(
    Map<String, Object?> args,
  ) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);
    final regionsVersion =
        optString(args, 'regions_version') ?? _defaultRegionsVersion;

    switch (action) {
      case 'list':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/oneTimeProducts',
          query: <String, Object?>{
            'pageSize': optInt(args, 'page_size') ?? 100,
            if (optString(args, 'page_token') case final t?) 'pageToken': t,
          },
        );

      case 'get':
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/oneTimeProducts/$productId',
        );

      case 'patch':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.onetimeproducts.patch ($packageName)',
        );
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final body = optJsonMap(args, 'product');
        if (body == null) {
          throw ArgumentError('Missing required "product" object for patch.');
        }
        // Per Google Play Discovery v3, PATCH uses lowercase `/onetimeproducts/`.
        return _apiClient.patchJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/onetimeproducts/$productId',
          query: <String, Object?>{
            'regionsVersion.version': regionsVersion,
            if (optString(args, 'update_mask') case final mask?)
              'updateMask': mask,
            if (optBool(args, 'allow_missing') case final am?)
              'allowMissing': am,
            if (optString(args, 'latency_tolerance') case final lt?)
              'latencyTolerance': lt,
          },
          body: body,
        );

      case 'delete':
        final productId = reqString(args, 'product_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'monetization.onetimeproducts.delete ($productId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.deleteJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/oneTimeProducts/${Uri.encodeComponent(productId)}',
          query: <String, Object?>{
            if (optString(args, 'latency_tolerance') case final lt?)
              'latencyTolerance': lt,
          },
        );

      case 'update_purchase_options_state':
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.onetimeproducts.purchaseOptions.batchUpdateStates',
        );
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final requests = tryAsJsonList(args['requests']);
        if (requests == null || requests.isEmpty) {
          throw ArgumentError('Missing required "requests" array.');
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/oneTimeProducts/$productId/purchaseOptions:batchUpdateStates',
          body: <String, Object?>{'requests': requests},
        );

      case 'list_offers':
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final purchaseOptionId = Uri.encodeComponent(
          reqString(args, 'purchase_option_id'),
        );
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/oneTimeProducts/$productId/purchaseOptions/$purchaseOptionId/offers',
          query: <String, Object?>{
            'pageSize': optInt(args, 'page_size') ?? 100,
            if (optString(args, 'page_token') case final t?) 'pageToken': t,
          },
        );

      case 'activate_offer':
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.onetimeproducts.purchaseOptions.offers.activate',
        );
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final purchaseOptionId = Uri.encodeComponent(
          reqString(args, 'purchase_option_id'),
        );
        final offerId = Uri.encodeComponent(reqString(args, 'offer_id'));
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/oneTimeProducts/$productId/purchaseOptions/$purchaseOptionId/offers/$offerId:activate',
          body: const <String, Object?>{},
        );

      case 'deactivate_offer':
      case 'cancel_offer':
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final purchaseOptionId = Uri.encodeComponent(
          reqString(args, 'purchase_option_id'),
        );
        final offerId = reqString(args, 'offer_id');
        final verb = action == 'deactivate_offer' ? 'deactivate' : 'cancel';
        SafetyGuard.checkWrite(
          context: ctx,
          operation:
              'monetization.onetimeproducts.purchaseOptions.offers.$verb ($offerId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/oneTimeProducts/$productId/purchaseOptions/$purchaseOptionId/offers/${Uri.encodeComponent(offerId)}:$verb',
          body: const <String, Object?>{},
        );

      case 'legacy_list':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/inappproducts',
          query: <String, Object?>{
            'maxResults': optInt(args, 'page_size') ?? 100,
            if (optString(args, 'page_token') case final t?) 'token': t,
          },
        );

      case 'legacy_get':
        final sku = Uri.encodeComponent(reqString(args, 'product_id'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/inappproducts/$sku',
        );

      default:
        throw ArgumentError(
          'Unsupported manage_one_time_products action: $action',
        );
    }
  }

  Future<Object?> _handleConvertRegionPrices(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final currencyCode = reqString(args, 'currency_code').toUpperCase();
    final amount = optDouble(args, 'amount');
    if (amount == null || amount < 0) {
      throw ArgumentError('Missing or negative numeric "amount".');
    }
    final money = toGoogleMoney(amount);
    return _apiClient.postJson(
      credentials: ctx.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/pricing:convertRegionPrices',
      body: <String, Object?>{
        'price': <String, Object?>{
          'currencyCode': currencyCode,
          'units': money.units,
          'nanos': money.nanos,
        },
        if (optString(args, 'product_tax_category_code') case final tax?)
          'productTaxCategoryCode': tax,
      },
    );
  }
}
