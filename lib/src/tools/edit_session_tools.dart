import '../config/profile_store.dart';
import '../config/safety_guard.dart';
import '../mcp/mcp_types.dart';
import '../services/edits_service.dart';
import '../utils/json_helpers.dart';

/// Explicit `edits` session lifecycle tool for grouping multiple publishing
/// changes (binaries, deobfuscation files, track updates, store listings,
/// images) into one atomic Play Console commit.
final class EditSessionTools {
  EditSessionTools({
    required PlayProfileStore profileStore,
    required EditsService editsService,
  }) : _profileStore = profileStore,
       _editsService = editsService;

  final PlayProfileStore _profileStore;
  final EditsService _editsService;

  List<McpToolDefinition> get definitions => <McpToolDefinition>[
    McpToolDefinition(
      name: 'manage_edit_session',
      description:
          'Creates, inspects, validates, commits, or deletes an explicit Android Publisher AppEdit session. Use this when combining multiple changes (e.g. upload AAB + upload mapping + update track + update store listing) into one atomic commit; otherwise, individual write tools auto-manage edits.',
      annotations: const McpToolAnnotations(
        title: 'Manage Edit Session',
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
            'enum': <String>['create', 'get', 'validate', 'commit', 'delete'],
            'description': 'Edit lifecycle action.',
          },
          'package_name': <String, Object?>{
            'type': 'string',
            'description': 'Android packageName (falls back to profile/env).',
          },
          'edit_id': <String, Object?>{
            'type': 'string',
            'description':
                'Existing AppEdit ID (required for get, validate, commit, delete).',
          },
          'changes_not_sent_for_review': <String, Object?>{
            'type': 'boolean',
            'description':
                'For commit: stage changes in Play Console without sending them to review automatically.',
          },
          'changes_in_review_behavior': <String, Object?>{
            'type': 'string',
            'enum': <String>[
              'ERROR_IF_IN_REVIEW',
              'CANCEL_IN_REVIEW_AND_SUBMIT',
            ],
            'description':
                'For commit: behavior when another submission is currently in review (default ERROR_IF_IN_REVIEW).',
          },
          'is_production': <String, Object?>{
            'type': 'boolean',
            'description':
                'Set true when committing staged production track changes.',
          },
          'confirm_production': <String, Object?>{
            'type': 'boolean',
            'description':
                'Explicit confirmation when allow_production_writes is false.',
          },
          'profile': <String, Object?>{
            'type': 'string',
            'description': 'Optional profile ID override.',
          },
        },
        'required': <String>['action'],
      },
      handler: _handleManageEditSession,
    ),
  ];

  Future<Object?> _handleManageEditSession(Map<String, Object?> args) async {
    final ctx = _profileStore.resolveContext(args);
    final packageName = ctx.requirePackageName(args);
    final action = reqString(args, 'action');

    switch (action) {
      case 'create':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'edits.insert ($packageName)',
        );
        return _editsService.createEdit(context: ctx, packageName: packageName);

      case 'get':
        final editId = reqString(args, 'edit_id');
        return _editsService.getEdit(
          context: ctx,
          packageName: packageName,
          editId: editId,
        );

      case 'validate':
        final editId = reqString(args, 'edit_id');
        return _editsService.validateEdit(
          context: ctx,
          packageName: packageName,
          editId: editId,
        );

      case 'commit':
        final editId = reqString(args, 'edit_id');
        return _editsService.commitEdit(
          context: ctx,
          packageName: packageName,
          editId: editId,
          changesNotSentForReview: optBool(args, 'changes_not_sent_for_review'),
          changesInReviewBehavior: optString(
            args,
            'changes_in_review_behavior',
          ),
          isProduction: optBool(args, 'is_production') ?? false,
          confirmProduction:
              (optBool(args, 'confirm_production') ?? false) ||
              (optBool(args, 'confirm_destructive') ?? false),
        );

      case 'delete':
        SafetyGuard.checkWrite(
          context: ctx,
          operation: 'edits.delete ($packageName)',
        );
        final editId = reqString(args, 'edit_id');
        await _editsService.deleteEdit(
          context: ctx,
          packageName: packageName,
          editId: editId,
        );
        return <String, Object?>{
          'deleted': true,
          'edit_id': editId,
          'package_name': packageName,
        };

      default:
        throw ArgumentError('Unsupported manage_edit_session action: $action');
    }
  }
}
