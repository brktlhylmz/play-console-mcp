import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../http/play_api_client.dart';
import '../mcp/mcp_types.dart';
import '../utils/json_helpers.dart';

/// User review reading (`reviews.list`, `reviews.get`) and reply (`reviews.reply`)
/// tools for Android Publisher v3.
final class ReviewTools {
  ReviewTools({
    required PlayProfileStore profileStore,
    required PlayApiClient apiClient,
  }) : _profileStore = profileStore,
       _apiClient = apiClient;

  final PlayProfileStore _profileStore;
  final PlayApiClient _apiClient;

  static const List<String> _scopes = <String>[PlayScopes.androidPublisher];
  static const int _maxReplyLength = 350;

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'get_reviews',
      description:
          'Lists recent user reviews (or fetches one review by review_id) with optional translation_language and client-side star rating / unanswered filtering. Note: Google Play reviews API only returns reviews created or modified in the last 7 days; use query_play_gcs_reports for older reviews.',
      annotations: const McpToolAnnotations(
        title: 'Get Play Store Reviews',
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
            'enum': <String>['list', 'get'],
            'description': 'Whether to list reviews or fetch a single review.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'review_id': <String, Object?>{
            'type': 'string',
            'description': 'Required when action is "get".',
          },
          'translation_language': <String, Object?>{
            'type': 'string',
            'description':
                'Target BCP-47 language to auto-translate user comments into (e.g. en, tr).',
          },
          'max_results': <String, Object?>{
            'type': 'integer',
            'description': 'Page size (default 50, max 100).',
          },
          'start_index': <String, Object?>{
            'type': 'integer',
            'description': 'Pagination startIndex.',
          },
          'token': <String, Object?>{
            'type': 'string',
            'description': 'Pagination token.',
          },
          'min_rating': <String, Object?>{
            'type': 'integer',
            'description': 'Client-side filter: minimum star rating (1..5).',
          },
          'max_rating': <String, Object?>{
            'type': 'integer',
            'description': 'Client-side filter: maximum star rating (1..5).',
          },
          'unanswered_only': <String, Object?>{
            'type': 'boolean',
            'description':
                'Client-side filter: return only reviews without a developer reply.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
      },
      handler: _handleGetReviews,
    ),
    McpToolDefinition(
      name: 'reply_to_review',
      description:
          'Posts or updates a developer reply to a Google Play user review. Pre-validates Google Play\'s 350-character reply limit.',
      annotations: const McpToolAnnotations(
        title: 'Reply to Play Store Review',
        readOnlyHint: false,
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
          'review_id': <String, Object?>{
            'type': 'string',
            'description': 'Target reviewId.',
          },
          'reply_text': <String, Object?>{
            'type': 'string',
            'description': 'Reply message text (1 to 350 characters).',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['review_id', 'reply_text'],
      },
      handler: _handleReplyToReview,
    ),
  ];

  Future<Object?> _handleGetReviews(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final encodedPkg = Uri.encodeComponent(packageName);
    final action = optString(args, 'action') ?? 'list';
    final translationLang = optString(args, 'translation_language');

    if (action == 'get') {
      final reviewId = reqString(args, 'review_id');
      return _apiClient.getJson(
        credentials: ctx.credentials,
        scopes: _scopes,
        baseUrl: PlayApiEndpoints.androidPublisher,
        path:
            '/applications/$encodedPkg/reviews/${Uri.encodeComponent(reviewId)}',
        query: <String, Object?>{
          if (translationLang != null) 'translationLanguage': translationLang,
        },
      );
    }

    if (action != 'list') {
      throw ArgumentError('Unsupported get_reviews action: $action');
    }

    final maxResults = optInt(args, 'max_results') ?? 50;
    final startIndex = optInt(args, 'start_index');
    final token = optString(args, 'token');
    final minRating = optInt(args, 'min_rating');
    final maxRating = optInt(args, 'max_rating');
    final unansweredOnly = optBool(args, 'unanswered_only') ?? false;

    final resp = await _apiClient.getJson(
      credentials: ctx.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/reviews',
      query: <String, Object?>{
        'maxResults': maxResults,
        if (startIndex != null) 'startIndex': startIndex,
        if (token != null) 'token': token,
        if (translationLang != null) 'translationLanguage': translationLang,
      },
    );

    final rawReviews = tryAsJsonList(resp['reviews']) ?? const <Object?>[];
    final filtered = <Object?>[];
    for (final item in rawReviews) {
      final review = tryAsJsonMap(item);
      if (review == null) continue;
      final comments = tryAsJsonList(review['comments']) ?? const <Object?>[];
      int? starRating;
      var hasDevReply = false;
      for (final commentItem in comments) {
        final comment = tryAsJsonMap(commentItem);
        if (comment == null) continue;
        final userComment = tryAsJsonMap(comment['userComment']);
        if (userComment != null) {
          starRating ??= optInt(userComment, 'starRating');
        }
        if (tryAsJsonMap(comment['developerComment']) != null) {
          hasDevReply = true;
        }
      }
      if (unansweredOnly && hasDevReply) continue;
      if (minRating != null && (starRating == null || starRating < minRating)) {
        continue;
      }
      if (maxRating != null && (starRating == null || starRating > maxRating)) {
        continue;
      }
      filtered.add(review);
    }

    return <String, Object?>{
      'reviews': filtered,
      'total_returned': filtered.length,
      'total_unfiltered_in_page': rawReviews.length,
      if (resp['tokenPagination'] != null)
        'tokenPagination': resp['tokenPagination'],
      if (resp['pageInfo'] != null) 'pageInfo': resp['pageInfo'],
      'note':
          'Google Play reviews API returns only reviews created or updated within the last 7 days. Use query_play_gcs_reports (category: reviews) for historical archives.',
    };
  }

  Future<Object?> _handleReplyToReview(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final reviewId = reqString(args, 'review_id');
    final replyText = (optRawString(args, 'reply_text') ?? '').trim();
    if (replyText.isEmpty) {
      throw ArgumentError('reply_text cannot be empty.');
    }
    if (replyText.length > _maxReplyLength) {
      throw ArgumentError(
        'reply_text exceeds Google Play $_maxReplyLength-character limit (${replyText.length} chars).',
      );
    }
    SafetyGuard.checkWrite(
      context: ctx,
      operation: 'reviews.reply ($packageName / $reviewId)',
    );
    final encodedPkg = Uri.encodeComponent(packageName);
    final encodedReview = Uri.encodeComponent(reviewId);
    return _apiClient.postJson(
      credentials: ctx.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/reviews/$encodedReview:reply',
      body: <String, Object?>{'replyText': replyText},
    );
  }
}
