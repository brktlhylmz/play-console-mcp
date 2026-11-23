import 'dart:convert';

/// Strongly typed helpers for reading JSON objects and MCP tool arguments
/// without dynamic calls.
Map<String, Object?> asJsonMap(Object? value, {String? fieldName}) {
  if (value is Map<String, Object?>) {
    return value;
  }
  if (value is Map) {
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      if (entry.key case final String k) {
        result[k] = entry.value;
      }
    }
    return result;
  }
  throw FormatException(
    fieldName == null
        ? 'Expected JSON object.'
        : 'Expected "$fieldName" to be a JSON object.',
  );
}

/// Converts [value] to a typed map if it is a [Map], otherwise returns `null`.
Map<String, Object?>? tryAsJsonMap(Object? value) {
  if (value is Map) {
    return asJsonMap(value);
  }
  return null;
}

/// Converts [value] to a `List<Object?>` if it is a [List], otherwise `null`.
List<Object?>? tryAsJsonList(Object? value) {
  if (value is List<Object?>) {
    return value;
  }
  if (value is List) {
    return List<Object?>.from(value);
  }
  return null;
}

/// Reads an optional non-empty string parameter from [args].
String? optString(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isNotEmpty) {
      return trimmed;
    }
  }
  return null;
}

/// Reads an optional string parameter from [args], preserving whitespace and
/// empty strings if explicitly supplied as a [String].
String? optRawString(Map<String, Object?> args, String key) {
  final value = args[key];
  return value is String ? value : null;
}

/// Reads a required non-empty string parameter from [args].
String reqString(Map<String, Object?> args, String key) {
  final value = optString(args, key);
  if (value == null) {
    throw ArgumentError.value(
      args[key],
      key,
      'Missing required non-empty string parameter "$key".',
    );
  }
  return value;
}

/// Reads an optional integer parameter from [args] (accepts `int`, `num`, or
/// numeric strings).
int? optInt(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    return int.tryParse(value.trim());
  }
  return null;
}

/// Reads a required integer parameter from [args].
int reqInt(Map<String, Object?> args, String key) {
  final value = optInt(args, key);
  if (value == null) {
    throw ArgumentError.value(
      args[key],
      key,
      'Missing required integer parameter "$key".',
    );
  }
  return value;
}

/// Reads an optional double parameter from [args].
double? optDouble(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is double) {
    return value;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    return double.tryParse(value.trim());
  }
  return null;
}

/// Reads an optional boolean parameter from [args].
bool? optBool(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value is bool) {
    return value;
  }
  if (value is String) {
    final lower = value.trim().toLowerCase();
    if (lower == 'true') return true;
    if (lower == 'false') return false;
  }
  return null;
}

/// Reads an optional list of non-empty strings from [args].
List<String>? optStringList(Map<String, Object?> args, String key) {
  final list = tryAsJsonList(args[key]);
  if (list == null) return null;
  final out = <String>[];
  for (final item in list) {
    if (item is String && item.trim().isNotEmpty) {
      out.add(item.trim());
    } else if (item is int) {
      out.add(item.toString());
    } else {
      throw ArgumentError.value(
        item,
        key,
        'Expected all elements of "$key" to be non-empty strings.',
      );
    }
  }
  return out;
}

/// Reads an optional list of integers (or integer strings, e.g. version codes).
List<int>? optIntList(Map<String, Object?> args, String key) {
  final list = tryAsJsonList(args[key]);
  if (list == null) return null;
  final out = <int>[];
  for (final item in list) {
    final parsed = switch (item) {
      final int i => i,
      final num n => n.toInt(),
      final String s => int.tryParse(s.trim()),
      _ => null,
    };
    if (parsed == null) {
      throw ArgumentError.value(
        item,
        key,
        'Expected all elements of "$key" to be integers.',
      );
    }
    out.add(parsed);
  }
  return out;
}

/// Reads an optional JSON object parameter from [args].
Map<String, Object?>? optJsonMap(Map<String, Object?> args, String key) {
  final value = args[key];
  if (value == null) return null;
  return asJsonMap(value, fieldName: key);
}

/// Encodes [data] as indented JSON for readable MCP tool responses.
String prettyJson(Object? data) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(data);
}

/// Converts a decimal monetary [amount] into Google's `Money` (`units` string
/// and `nanos` int) without floating-point drift.
({String units, int nanos}) toGoogleMoney(double amount) {
  final totalNanos = (amount * 1000000000).round();
  final units = totalNanos ~/ 1000000000;
  final nanos = totalNanos % 1000000000;
  return (units: units.toString(), nanos: nanos);
}

/// Parses a `DateTime` formatted as `YYYY-MM-DD`.
({int year, int month, int day}) parseIsoDate(
  String value, {
  String? fieldName,
}) {
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value.trim());
  if (match == null) {
    throw ArgumentError.value(
      value,
      fieldName ?? 'date',
      'Expected YYYY-MM-DD date format (got "$value").',
    );
  }
  final year = int.parse(match.group(1)!);
  final month = int.parse(match.group(2)!);
  final day = int.parse(match.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) {
    throw ArgumentError.value(
      value,
      fieldName ?? 'date',
      'Calendar date out of range: "$value".',
    );
  }
  return (year: year, month: month, day: day);
}
