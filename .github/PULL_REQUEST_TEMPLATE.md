## Summary
Describe what this PR adds or fixes.

## Checklist
- [ ] Keep runtime dependencies restricted to `googleapis_auth` and `http`
- [ ] Preserve `SafetyGuard` checks on production/destructive operations and never log secrets/private keys
- [ ] Keep `stdout` strictly reserved for JSON-RPC 2.0 responses (no `print` / non-JSON output)
- [ ] Add or update deterministic unit tests using `MockClient` (no live Google Play account required)
- [ ] `make check` (`dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos`, `dart test`) passes cleanly
