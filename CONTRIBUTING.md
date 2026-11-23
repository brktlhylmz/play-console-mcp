# Contributing to play-console-mcp

Thank you for your interest in contributing to **play-console-mcp**!

## Development Setup

1. Clone the repository:
   ```bash
   git clone https://github.com/brktlhylmz/play-console-mcp.git
   cd play-console-mcp
   ```
2. Install dependencies:
   ```bash
   make get
   ```
3. Run formatting check, static analysis, and unit tests:
   ```bash
   make check
   ```

## Guidelines

- **Minimal Runtime Dependencies**: Keep runtime dependencies restricted to `googleapis_auth` and `http`. Do not introduce heavyweight code-generated mega-packages or platform-specific FFI dependencies.
- **Safety & Privacy First**: Never log OAuth tokens or Service Account private key fields, never write non-JSON-RPC output to `stdout`, and preserve `SafetyGuard` checks on all production/destructive endpoints.
- **Deterministic Tests**: Every new tool action must include deterministic unit tests using `package:http/testing.dart` (`MockClient`) and temporary directories without requiring live Google Play credentials.
- **Formatting & Lints**: Ensure `make check` (`dart format --output=none --set-exit-if-changed .`, `dart analyze --fatal-infos`, and `dart test`) passes with zero warnings before opening a Pull Request.
