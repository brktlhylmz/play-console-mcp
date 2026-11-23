import 'profile_store.dart';

/// Thrown when an operation violates read-only or production-write safety
/// guards.
final class SafetyPolicyException implements Exception {
  const SafetyPolicyException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Enforces read-only and production/destructive operation safeguards before
/// mutating Google Play Console state.
final class SafetyGuard {
  const SafetyGuard._();

  /// Verifies whether [operation] is permitted under [context].
  ///
  /// When [isProductionOrDestructive] is `true`, either
  /// `context.allowProductionWrites` must be enabled (via profile or
  /// `PLAY_CONSOLE_ALLOW_PRODUCTION_WRITES=true`) or [confirmed] must be `true`
  /// (`confirm_production: true` / `confirm_destructive: true`), unless
  /// [dryRun] is `true`.
  static void checkWrite({
    required ResolvedPlayContext context,
    required String operation,
    bool isProductionOrDestructive = false,
    bool confirmed = false,
    bool dryRun = false,
  }) {
    if (dryRun) {
      // Dry runs validate edits and roll them back without committing.
      return;
    }

    if (context.readOnly) {
      throw SafetyPolicyException(
        'Blocked "$operation": read-only mode is enabled '
        '(profile.read_only=true or PLAY_CONSOLE_READ_ONLY=true). '
        'Disable read-only mode or pass dry_run: true if validating an edit.',
      );
    }

    if (isProductionOrDestructive &&
        !context.allowProductionWrites &&
        !confirmed) {
      throw SafetyPolicyException(
        'Blocked "$operation": production/destructive writes are disabled by default. '
        'Either pass confirm_production: true (or confirm_destructive: true) after explicit confirmation, '
        'enable allow_production_writes on the profile, or set PLAY_CONSOLE_ALLOW_PRODUCTION_WRITES=true.',
      );
    }
  }
}
