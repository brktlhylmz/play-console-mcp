import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

/// Purchase verification/entitlement tools (Subscriptions v2, Products v2/v1,
/// Voided Purchases) and Order lookup/refund tools.
final class PurchaseOrderTools {
  PurchaseOrderTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
  }) : _profileStore = profileStore,
       _apiClient = apiClient;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;

  static const List<String> _scopes = <String>[PlayScopes.androidPublisher];

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'manage_purchases',
      description:
          'Verifies and manages Google Play purchases: get/cancel/defer/revoke subscriptions v2, inspect products v2/v1, acknowledge or consume one-time purchases, and list voided purchases.',
      annotations: const McpToolAnnotations(
        title: 'Manage Purchases & Entitlements',
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
              'get_subscription_v2',
              'cancel_subscription_v2',
              'defer_subscription_v2',
              'revoke_subscription_v2',
              'get_product_v2',
              'get_product_legacy',
              'acknowledge_product',
              'consume_product',
              'list_voided_purchases',
            ],
            'description': 'Purchase inspection or entitlement action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'token': <String, Object?>{
            'type': 'string',
            'description': 'Google Play purchaseToken.',
          },
          'product_id': <String, Object?>{
            'type': 'string',
            'description':
                'Required for get_product_legacy, acknowledge_product, consume_product.',
          },
          'cancellation_type': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'USER_REQUESTED_STOP_RENEWALS',
              'DEVELOPER_REQUESTED_STOP_PAYMENTS',
            ],
            'description':
                'Optional cancellationType for cancel_subscription_v2.',
          },
          'deferral_context': <String, Object?>{
            'type': 'object',
            'description':
                'For defer_subscription_v2: DeferSubscriptionPurchaseRequest body (deferralContext).',
          },
          'revocation_context': <String, Object?>{
            'type': 'object',
            'description':
                'For revoke_subscription_v2: RevokeSubscriptionPurchaseRequest body (revocationContext).',
          },
          'developer_payload': <String, Object?>{
            'type': 'string',
            'description': 'Optional developerPayload for acknowledge_product.',
          },
          'start_time': <String, Object?>{
            'type': 'string',
            'description':
                'For list_voided_purchases: epoch millis string startTime.',
          },
          'end_time': <String, Object?>{
            'type': 'string',
            'description':
                'For list_voided_purchases: epoch millis string endTime.',
          },
          'max_results': <String, Object?>{
            'type': 'integer',
            'description': 'Page size for list_voided_purchases.',
          },
          'page_token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token for list_voided_purchases.',
          },
          'type': <String, Object?>{
            'type': 'integer',
            'description':
                'For list_voided_purchases: 0 (in-app + subs) or 1 (only subs).',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for cancel_subscription_v2 / revoke_subscription_v2 when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManagePurchases,
    ),
    McpToolDefinition(
      name: 'manage_orders',
      description:
          'Fetches single or batch Google Play orders, issues refunds (with optional entitlement revocation), or submits chargeback review preferences.',
      annotations: const McpToolAnnotations(
        title: 'Manage Orders & Refunds',
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
            'enum': <String>['get', 'batch_get', 'refund', 'review_refund'],
            'description': 'Order operation.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'order_id': <String, Object?>{
            'type': 'string',
            'description': 'Single orderId (e.g. GPA.1234-5678-9012-34567).',
          },
          'order_ids': <String, Object?>{
            'type': 'array',
            'items': <String, Object?>{'type': 'string'},
            'description': 'Order IDs array for batch_get.',
          },
          'revoke': <String, Object?>{
            'type': 'boolean',
            'description':
                'For refund: whether to also revoke access/entitlement.',
          },
          'review_body': <String, Object?>{
            'type': 'object',
            'description':
                'OrdersReviewRefundRequest payload for review_refund.',
          },
          'confirm_destructive': <String, Object?>{
            'type': 'boolean',
            'description':
                'Required for refund when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageOrders,
    ),
  ];

  Future<Object?> _handleManagePurchases(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);

    switch (action) {
      case 'get_subscription_v2':
        final token = Uri.encodeComponent(reqString(args, 'token'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/subscriptionsv2/tokens/$token',
        );

      case 'cancel_subscription_v2':
        final token = Uri.encodeComponent(reqString(args, 'token'));
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'purchases.subscriptionsv2.cancel ($packageName)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        final cancelType = optString(args, 'cancellation_type');
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/subscriptionsv2/tokens/$token:cancel',
          body: <String, Object?>{
            if (cancelType != null)
              'cancellationContext': <String, Object?>{
                'cancellationType': cancelType,
              },
          },
        );

      case 'defer_subscription_v2':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'purchases.subscriptionsv2.defer ($packageName)',
        );
        final token = Uri.encodeComponent(reqString(args, 'token'));
        final body = optJsonMap(args, 'deferral_context');
        if (body == null) {
          throw ArgumentError(
            'Missing required "deferral_context" object for defer_subscription_v2.',
          );
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/subscriptionsv2/tokens/$token:defer',
          body: body,
        );

      case 'revoke_subscription_v2':
        final token = Uri.encodeComponent(reqString(args, 'token'));
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'purchases.subscriptionsv2.revoke ($packageName)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/subscriptionsv2/tokens/$token:revoke',
          body:
              optJsonMap(args, 'revocation_context') ??
              const <String, Object?>{},
        );

      case 'get_product_v2':
        final token = Uri.encodeComponent(reqString(args, 'token'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/purchases/productsv2/tokens/$token',
        );

      case 'get_product_legacy':
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final token = Uri.encodeComponent(reqString(args, 'token'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/products/$productId/tokens/$token',
        );

      case 'acknowledge_product':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'purchases.products.acknowledge ($packageName)',
        );
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final token = Uri.encodeComponent(reqString(args, 'token'));
        final devPayload = optString(args, 'developer_payload');
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/products/$productId/tokens/$token:acknowledge',
          body: <String, Object?>{
            if (devPayload != null) 'developerPayload': devPayload,
          },
        );

      case 'consume_product':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'purchases.products.consume ($packageName)',
        );
        final productId = Uri.encodeComponent(reqString(args, 'product_id'));
        final token = Uri.encodeComponent(reqString(args, 'token'));
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/purchases/products/$productId/tokens/$token:consume',
        );

      case 'list_voided_purchases':
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/purchases/voidedpurchases',
          query: <String, Object?>{
            if (optString(args, 'start_time') case final st?) 'startTime': st,
            if (optString(args, 'end_time') case final et?) 'endTime': et,
            if (optInt(args, 'max_results') case final mr?) 'maxResults': mr,
            if (optString(args, 'page_token') case final pt?) 'token': pt,
            if (optInt(args, 'type') case final typeVal?) 'type': typeVal,
          },
        );

      default:
        throw ArgumentError('Unsupported manage_purchases action: $action');
    }
  }

  Future<Object?> _handleManageOrders(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = reqString(args, 'action');
    final confirmed =
        (optBool(args, 'confirm_destructive') ?? false) ||
        (optBool(args, 'confirm_production') ?? false);

    switch (action) {
      case 'get':
        final orderId = Uri.encodeComponent(reqString(args, 'order_id'));
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/orders/$orderId',
        );

      case 'batch_get':
        final orderIds = optStringList(args, 'order_ids');
        if (orderIds == null || orderIds.isEmpty) {
          throw ArgumentError('Missing required "order_ids" array.');
        }
        return _apiClient.getJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/orders:batchGet',
          query: <String, Object?>{'orderIds': orderIds},
        );

      case 'refund':
        final orderId = reqString(args, 'order_id');
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'orders.refund ($orderId)',
          isProductionOrDestructive: true,
          confirmed: confirmed,
        );
        final revoke = optBool(args, 'revoke');
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path:
              '/applications/$encodedPkg/orders/${Uri.encodeComponent(orderId)}:refund',
          query: <String, Object?>{if (revoke != null) 'revoke': revoke},
        );

      case 'review_refund':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'orders.reviewrefund ($packageName)',
        );
        final orderId = Uri.encodeComponent(reqString(args, 'order_id'));
        final body = optJsonMap(args, 'review_body');
        if (body == null) {
          throw ArgumentError(
            'Missing required "review_body" object for review_refund.',
          );
        }
        return _apiClient.postJson(
          credentials: ctx.credentials,
          scopes: _scopes,
          baseUrl: PlayApiEndpoints.androidPublisher,
          path: '/applications/$encodedPkg/orders/$orderId:reviewrefund',
          body: body,
        );

      default:
        throw ArgumentError('Unsupported manage_orders action: $action');
    }
  }
}
