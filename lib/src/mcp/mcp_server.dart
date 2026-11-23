import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../utils/json_helpers.dart';
import 'mcp_types.dart';

/// Pure-Dart JSON-RPC 2.0 MCP server over `stdin`/`stdout`.
///
/// Diagnostics are never written to `stdout`, preserving clean stdio framing.
final class McpServer {
  McpServer({
    required this.name,
    required this.version,
    this.instructions,
    List<McpToolDefinition> tools = const <McpToolDefinition>[],
    List<McpPromptDefinition> prompts = const <McpPromptDefinition>[],
  }) {
    for (final tool in tools) {
      registerTool(tool);
    }
    for (final prompt in prompts) {
      registerPrompt(prompt);
    }
  }

  static const String latestProtocolVersion = '2025-03-26';
  static const List<String> supportedProtocolVersions = <String>[
    '2025-03-26',
    '2024-11-05',
  ];

  final String name;
  final String version;
  final String? instructions;

  final List<McpToolDefinition> _tools = <McpToolDefinition>[];
  final Map<String, McpToolDefinition> _toolsByName =
      <String, McpToolDefinition>{};
  final List<McpPromptDefinition> _prompts = <McpPromptDefinition>[];
  final Map<String, McpPromptDefinition> _promptsByName =
      <String, McpPromptDefinition>{};

  void registerTool(McpToolDefinition tool) {
    if (_toolsByName.containsKey(tool.name)) {
      throw StateError('Duplicate MCP tool registration: ${tool.name}');
    }
    _tools.add(tool);
    _toolsByName[tool.name] = tool;
  }

  void registerPrompt(McpPromptDefinition prompt) {
    if (_promptsByName.containsKey(prompt.name)) {
      throw StateError('Duplicate MCP prompt registration: ${prompt.name}');
    }
    _prompts.add(prompt);
    _promptsByName[prompt.name] = prompt;
  }

  List<McpToolDefinition> get tools =>
      List<McpToolDefinition>.unmodifiable(_tools);

  List<McpPromptDefinition> get prompts =>
      List<McpPromptDefinition>.unmodifiable(_prompts);

  /// Runs the stdio JSON-RPC loop until [input] closes.
  Future<void> serve({Stream<List<int>>? input, StringSink? output}) async {
    final byteStream = input ?? stdin;
    final outSink = output ?? stdout;
    final lines = byteStream
        .transform(utf8.decoder)
        .transform(const LineSplitter());

    await for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;

      final Object? decoded;
      try {
        decoded = jsonDecode(trimmed);
      } on FormatException catch (e) {
        _writeError(outSink, null, -32700, 'Parse error: ${e.message}');
        continue;
      }

      final message = tryAsJsonMap(decoded);
      if (message == null) continue;

      final method = optString(message, 'method');
      final hasId = message.containsKey('id') && message['id'] != null;
      if (method == null) continue;

      // JSON-RPC notifications (no id) must not receive a response.
      if (!hasId) {
        continue;
      }

      final id = message['id']!;
      final params =
          tryAsJsonMap(message['params']) ?? const <String, Object?>{};

      try {
        final result = await _dispatch(method, params);
        _writeResult(outSink, id, result);
      } on _JsonRpcException catch (e) {
        _writeError(outSink, id, e.code, e.message);
      } on Object catch (e) {
        _writeError(outSink, id, -32603, 'Internal error: $e');
      }
    }
  }

  Future<Map<String, Object?>> _dispatch(
    String method,
    Map<String, Object?> params,
  ) async {
    switch (method) {
      case 'initialize':
        final requestedVersion = optString(params, 'protocolVersion');
        final negotiatedVersion =
            requestedVersion != null &&
                supportedProtocolVersions.contains(requestedVersion)
            ? requestedVersion
            : latestProtocolVersion;
        return <String, Object?>{
          'protocolVersion': negotiatedVersion,
          'capabilities': <String, Object?>{
            'tools': const <String, Object?>{},
            if (_prompts.isNotEmpty) 'prompts': const <String, Object?>{},
          },
          'serverInfo': <String, Object?>{'name': name, 'version': version},
          if (instructions != null && instructions!.isNotEmpty)
            'instructions': instructions,
        };

      case 'ping':
        return const <String, Object?>{};

      case 'tools/list':
        return <String, Object?>{
          'tools': _tools.map((t) => t.toListJson()).toList(growable: false),
        };

      case 'tools/call':
        final toolName = optString(params, 'name');
        if (toolName == null) {
          throw const _JsonRpcException(-32602, 'Missing tool name.');
        }
        final tool = _toolsByName[toolName];
        if (tool == null) {
          throw _JsonRpcException(-32602, 'Unknown tool: $toolName');
        }
        final toolArgs =
            tryAsJsonMap(params['arguments']) ?? const <String, Object?>{};
        try {
          final output = await tool.handler(toolArgs);
          final text = output is String ? output : prettyJson(output);
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': text},
            ],
            'isError': false,
          };
        } on Object catch (e) {
          return <String, Object?>{
            'content': <Object?>[
              <String, Object?>{'type': 'text', 'text': 'Error: $e'},
            ],
            'isError': true,
          };
        }

      case 'prompts/list':
        return <String, Object?>{
          'prompts': _prompts
              .map((p) => p.toListJson())
              .toList(growable: false),
        };

      case 'prompts/get':
        final promptName = optString(params, 'name');
        if (promptName == null) {
          throw const _JsonRpcException(-32602, 'Missing prompt name.');
        }
        final prompt = _promptsByName[promptName];
        if (prompt == null) {
          throw _JsonRpcException(-32602, 'Unknown prompt: $promptName');
        }
        final promptArgs =
            tryAsJsonMap(params['arguments']) ?? const <String, Object?>{};
        final result = await prompt.handler(promptArgs);
        return result.toJson();

      default:
        throw _JsonRpcException(-32601, 'Method not found: $method');
    }
  }

  void _writeResult(StringSink sink, Object id, Map<String, Object?> result) {
    sink.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'result': result,
      }),
    );
  }

  void _writeError(StringSink sink, Object? id, int code, String message) {
    sink.writeln(
      jsonEncode(<String, Object?>{
        'jsonrpc': '2.0',
        'id': id,
        'error': <String, Object?>{'code': code, 'message': message},
      }),
    );
  }
}

final class _JsonRpcException implements Exception {
  const _JsonRpcException(this.code, this.message);

  final int code;
  final String message;
}
