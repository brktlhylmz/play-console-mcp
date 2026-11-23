import 'dart:async';

/// Handler invoked when an MCP client executes a tool.
typedef McpToolHandler = Future<Object?> Function(Map<String, Object?> args);

/// Handler invoked when an MCP client retrieves a prompt template.
typedef McpPromptHandler =
    FutureOr<McpPromptResult> Function(Map<String, Object?> args);

/// Optional MCP `ToolAnnotations` hints (introduced in protocol `2025-03-26`).
final class McpToolAnnotations {
  const McpToolAnnotations({
    this.title,
    this.readOnlyHint,
    this.destructiveHint,
    this.idempotentHint,
    this.openWorldHint = true,
  });

  final String? title;
  final bool? readOnlyHint;
  final bool? destructiveHint;
  final bool? idempotentHint;
  final bool? openWorldHint;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      if (title != null) 'title': title,
      if (readOnlyHint != null) 'readOnlyHint': readOnlyHint,
      if (destructiveHint != null) 'destructiveHint': destructiveHint,
      if (idempotentHint != null) 'idempotentHint': idempotentHint,
      if (openWorldHint != null) 'openWorldHint': openWorldHint,
    };
  }
}

/// Describes one MCP tool registered on the server.
final class McpToolDefinition {
  const McpToolDefinition({
    required this.name,
    required this.description,
    required this.inputSchema,
    required this.handler,
    this.annotations,
  });

  final String name;
  final String description;
  final Map<String, Object?> inputSchema;
  final McpToolHandler handler;
  final McpToolAnnotations? annotations;

  Map<String, Object?> toListJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'inputSchema': inputSchema,
      if (annotations != null) 'annotations': annotations!.toJson(),
    };
  }
}

/// Argument specification for an MCP prompt.
final class McpPromptArgument {
  const McpPromptArgument({
    required this.name,
    required this.description,
    this.required = false,
  });

  final String name;
  final String description;
  final bool required;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'required': required,
    };
  }
}

/// Message item returned by `prompts/get`.
final class McpPromptMessage {
  const McpPromptMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'role': role,
      'content': <String, Object?>{'type': 'text', 'text': text},
    };
  }
}

/// Output returned by [McpPromptHandler].
final class McpPromptResult {
  const McpPromptResult({required this.description, required this.messages});

  final String description;
  final List<McpPromptMessage> messages;

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'description': description,
      'messages': messages.map((m) => m.toJson()).toList(growable: false),
    };
  }
}

/// Describes a reusable MCP prompt registered on the server.
final class McpPromptDefinition {
  const McpPromptDefinition({
    required this.name,
    required this.description,
    required this.arguments,
    required this.handler,
  });

  final String name;
  final String description;
  final List<McpPromptArgument> arguments;
  final McpPromptHandler handler;

  Map<String, Object?> toListJson() {
    return <String, Object?>{
      'name': name,
      'description': description,
      'arguments': arguments.map((a) => a.toJson()).toList(growable: false),
    };
  }
}
