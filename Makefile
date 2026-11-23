.PHONY: get format format-check analyze test check build-exe activate smoke

get:
	dart pub get

format:
	dart format .

format-check:
	dart format --output=none --set-exit-if-changed .

analyze:
	dart analyze --fatal-infos

test:
	dart test

check: format-check analyze test

build-exe:
	mkdir -p build
	dart compile exe bin/play_console_mcp.dart -o build/play-console-mcp

activate:
	dart pub global activate --source path .

smoke:
	dart run bin/play_console_mcp.dart --version
	dart run bin/play_console_mcp.dart --help
	printf '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"smoke","version":"1.0"}}}\n{"jsonrpc":"2.0","method":"notifications/initialized"}\n{"jsonrpc":"2.0","id":2,"method":"tools/list"}\n{"jsonrpc":"2.0","id":3,"method":"prompts/list"}\n' | dart run bin/play_console_mcp.dart
