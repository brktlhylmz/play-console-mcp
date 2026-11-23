import '../auth/play_auth_provider.dart';
import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../http/play_api_client.dart';

/// Result wrapper produced by [EditsService.withEdit] showing whether the edit
/// was left open (caller-supplied `edit_id`), validated (`dry_run`), or committed.
final class EditExecutionResult<T> {
  const EditExecutionResult({
    required this.editId,
    required this.mode,
    required this.result,
    this.commitResponse,
  });

  final String editId;
  final String mode;
  final T result;
  final Map<String, Object?>? commitResponse;

  Map<String, Object?> toJson([Object? Function(T value)? mapResult]) {
    return <String, Object?>{
      'mode': mode,
      'edit_id': editId,
      'result': mapResult != null ? mapResult(result) : result,
      if (commitResponse != null) 'commit': commitResponse,
    };
  }
}

/// Manages Google Play `edits` transactions cleanly:
/// - Automatically inserts, runs, validates/commits, and cleans up failed edits
///   when `editId` is omitted.
/// - Reuses caller-managed `editId` without committing when part of a batch edit.
/// - Provides [withReadOnlyEdit] for read-only inspection endpoints under `edits.*`.
final class EditsService {
  EditsService(this._api);

  final PlayApiClient _api;

  static const List<String> _scopes = <String>[PlayScopes.androidPublisher];

  /// Creates a new `AppEdit` session.
  Future<Map<String, Object?>> createEdit({
    required ResolvedPlayContext context,
    required String packageName,
  }) {
    final encodedPkg = Uri.encodeComponent(packageName);
    return _api.postJson(
      credentials: context.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/edits',
      body: const <String, Object?>{},
    );
  }

  /// Gets an existing `AppEdit`.
  Future<Map<String, Object?>> getEdit({
    required ResolvedPlayContext context,
    required String packageName,
    required String editId,
  }) {
    final encodedPkg = Uri.encodeComponent(packageName);
    final encodedEdit = Uri.encodeComponent(editId);
    return _api.getJson(
      credentials: context.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/edits/$encodedEdit',
    );
  }

  /// Validates an existing `AppEdit`.
  Future<Map<String, Object?>> validateEdit({
    required ResolvedPlayContext context,
    required String packageName,
    required String editId,
  }) {
    final encodedPkg = Uri.encodeComponent(packageName);
    final encodedEdit = Uri.encodeComponent(editId);
    return _api.postJson(
      credentials: context.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/edits/$encodedEdit:validate',
    );
  }

  /// Commits an existing `AppEdit`.
  Future<Map<String, Object?>> commitEdit({
    required ResolvedPlayContext context,
    required String packageName,
    required String editId,
    bool? changesNotSentForReview,
    String? changesInReviewBehavior,
    bool isProduction = false,
    bool confirmProduction = false,
  }) {
    SafetyGuard.checkWrite(
      context: context,
      operation: 'edits.commit ($packageName)',
      isProductionOrDestructive: isProduction,
      confirmed: confirmProduction,
    );
    final encodedPkg = Uri.encodeComponent(packageName);
    final encodedEdit = Uri.encodeComponent(editId);
    final holdForReview =
        changesNotSentForReview ?? context.defaultChangesNotSentForReview;
    return _api.postJson(
      credentials: context.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/edits/$encodedEdit:commit',
      query: <String, Object?>{
        if (holdForReview) 'changesNotSentForReview': true,
        'changesInReviewBehavior':
            changesInReviewBehavior ?? 'ERROR_IF_IN_REVIEW',
      },
    );
  }

  /// Deletes an existing `AppEdit` (best-effort cleanup).
  Future<void> deleteEdit({
    required ResolvedPlayContext context,
    required String packageName,
    required String editId,
  }) async {
    final encodedPkg = Uri.encodeComponent(packageName);
    final encodedEdit = Uri.encodeComponent(editId);
    await _api.deleteJson(
      credentials: context.credentials,
      scopes: _scopes,
      baseUrl: PlayApiEndpoints.androidPublisher,
      path: '/applications/$encodedPkg/edits/$encodedEdit',
    );
  }

  /// Opens a temporary edit for read-only endpoints (`edits.tracks.list`,
  /// `edits.listings.list`, etc.) and always deletes the temporary edit.
  Future<T> withReadOnlyEdit<T>({
    required ResolvedPlayContext context,
    required String packageName,
    String? existingEditId,
    required Future<T> Function(String editId) action,
  }) async {
    if (existingEditId != null && existingEditId.isNotEmpty) {
      return action(existingEditId);
    }
    final created = await createEdit(
      context: context,
      packageName: packageName,
    );
    final editId = created['id'] as String?;
    if (editId == null || editId.isEmpty) {
      throw StateError('Google Play edits.insert did not return an edit id.');
    }
    try {
      return await action(editId);
    } finally {
      try {
        await deleteEdit(
          context: context,
          packageName: packageName,
          editId: editId,
        );
      } on Object {
        // Ignore best-effort cleanup errors.
      }
    }
  }

  /// Executes a mutating edit operation.
  ///
  /// Checks [SafetyGuard] up front so mutations fail fast before touching any
  /// Google Play API endpoint.
  Future<EditExecutionResult<T>> withEdit<T>({
    required ResolvedPlayContext context,
    required String packageName,
    required String operation,
    String? editId,
    bool dryRun = false,
    bool? changesNotSentForReview,
    String? changesInReviewBehavior,
    bool isProductionOrDestructive = false,
    bool confirmed = false,
    required Future<T> Function(String activeEditId) action,
  }) async {
    SafetyGuard.checkWrite(
      context: context,
      operation: operation,
      isProductionOrDestructive: isProductionOrDestructive,
      confirmed: confirmed,
      dryRun: dryRun,
    );

    if (editId != null && editId.isNotEmpty) {
      final result = await action(editId);
      return EditExecutionResult<T>(
        editId: editId,
        mode: 'staged_in_session',
        result: result,
      );
    }

    final created = await createEdit(
      context: context,
      packageName: packageName,
    );
    final activeEditId = created['id'] as String?;
    if (activeEditId == null || activeEditId.isEmpty) {
      throw StateError('Google Play edits.insert did not return an edit id.');
    }

    try {
      final result = await action(activeEditId);
      if (dryRun) {
        final validated = await validateEdit(
          context: context,
          packageName: packageName,
          editId: activeEditId,
        );
        await deleteEdit(
          context: context,
          packageName: packageName,
          editId: activeEditId,
        );
        return EditExecutionResult<T>(
          editId: activeEditId,
          mode: 'dry_run_validated_and_discarded',
          result: result,
          commitResponse: validated,
        );
      }

      final committed = await commitEdit(
        context: context,
        packageName: packageName,
        editId: activeEditId,
        changesNotSentForReview: changesNotSentForReview,
        changesInReviewBehavior: changesInReviewBehavior,
        isProduction: isProductionOrDestructive,
        confirmProduction: confirmed,
      );
      return EditExecutionResult<T>(
        editId: activeEditId,
        mode: 'committed',
        result: result,
        commitResponse: committed,
      );
    } on Object {
      try {
        await deleteEdit(
          context: context,
          packageName: packageName,
          editId: activeEditId,
        );
      } on Object {
        // Ignore cleanup failure and rethrow original error.
      }
      rethrow;
    }
  }
}
