# Security Policy

## Credential & Key Handling

- **Never commit Service Account JSON keys** or personal `~/.config/play_console_mcp/config.json` files to version control.
- `play-console-mcp` enforces `0600` POSIX permissions when saving local configuration files and redacts private keys in diagnostics (`--doctor` / `manage_play_profiles` `doctor`).
- Prefer least-privilege permissions when inviting your Service Account in **Google Play Console > Users and permissions**:
  - Use `read_only: true` (or `PLAY_CONSOLE_READ_ONLY=true`) for monitoring, crash triage, and review reading agents.
  - Keep `allow_production_writes: false` (the default) unless automated production releases, refunds, or subscription cancellations are intentionally required.
  - Use `dry_run: true` to validate edits before committing changes.

## Reporting a Vulnerability

If you discover a security vulnerability (such as credential leakage, unsafe file permissions, or bypasses of safety guards), please report it responsibly via GitHub Security Advisories or by opening a private issue with the maintainers instead of posting sensitive details publicly.
