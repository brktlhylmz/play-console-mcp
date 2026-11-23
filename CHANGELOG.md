## 0.1.0

- Initial public open-source release under MIT License.
- Added unified pure-Dart MCP server (`2025-03-26` & `2024-11-05` stdio JSON-RPC 2.0) with tool annotations (`readOnlyHint`, `destructiveHint`, `idempotentHint`) and 4 built-in MCP prompts.
- Added 25 tools across Android Publisher API v3, Play Developer Reporting API v1beta1, and Google Cloud Storage (`pubsite_prod_rev_*`) bulk CSV reports.
- Added `SafetyGuard` (`read_only`, `allow_production_writes`, `dry_run`), atomic `EditsService`, Google Resumable Media Upload for `.aab`/`.apk`/deobfuscation files, Fastlane metadata sync/export, modern `monetization.onetimeproducts` & `subscriptions`, and UTF-16LE GCS report parsing.
