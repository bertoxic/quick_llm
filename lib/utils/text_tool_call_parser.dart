import 'dart:convert';

/// Converts the narrowly-scoped `tool_code name(...)` convention used by some
/// otherwise non-tool-capable models into the same call shape used by Ollama.
///
/// Only names advertised in the current request's tool schemas are accepted.
/// This is deliberately not a general code parser: ordinary prose and unknown
/// functions stay untouched and can never reach a local executor.
class TextToolCallExtraction {
  final String cleanedContent;
  final List<Map<String, dynamic>> toolCalls;

  const TextToolCallExtraction({
    required this.cleanedContent,
    required this.toolCalls,
  });

  bool get hasToolCalls => toolCalls.isNotEmpty;
}

class TextToolCallParser {
  static TextToolCallExtraction extract({
    required String content,
    required List<Map<String, dynamic>> toolSchemas,
    required int iteration,
  }) {
    if (content.trim().isEmpty || toolSchemas.isEmpty) {
      return TextToolCallExtraction(
        cleanedContent: content,
        toolCalls: const [],
      );
    }

    final registeredNames = toolSchemas
        .map((schema) => schema['function'])
        .whereType<Map>()
        .map((function) => '${function['name'] ?? ''}'.trim().toLowerCase())
        .where((name) => name.isNotEmpty)
        .toSet();
    if (registeredNames.isEmpty) {
      return TextToolCallExtraction(
        cleanedContent: content,
        toolCalls: const [],
      );
    }

    final marker = RegExp(
      r'\btool_code\s*(?:[:\-]\s*|\s+)([A-Za-z_][A-Za-z0-9_]*)\s*\(',
      caseSensitive: false,
    );
    final removals = <({int start, int end})>[];
    final calls = <Map<String, dynamic>>[];

    for (final match in marker.allMatches(content)) {
      final toolName = match.group(1)!.toLowerCase();
      if (!registeredNames.contains(toolName)) continue;

      final openParen = content.indexOf('(', match.start);
      final closeParen = _matchingParen(content, openParen);
      if (closeParen == null) continue;

      final arguments = _argumentsFor(
        toolName,
        content.substring(openParen + 1, closeParen),
      );
      calls.add({
        'id': 'text_tool_${iteration}_${calls.length}',
        'type': 'function',
        'function': {
          'name': toolName,
          'arguments': arguments,
        },
      });

      var start = match.start;
      var end = closeParen + 1;
      // Gemma occasionally prefixes its pseudo protocol with `""tool_code`.
      // Those quotes are part of the protocol, not the answer.
      if (start >= 2 && content.substring(start - 2, start) == '""') {
        start -= 2;
      }
      while (end < content.length &&
          (content[end] == ';' ||
              content[end] == ' ' ||
              content[end] == '\t')) {
        end++;
      }
      // Models often wrap this protocol in a fenced code block.
      if (content.startsWith('```', end)) end += 3;
      if (start > 0 && end < content.length) {
        final before = content[start - 1];
        final after = content[end];
        if ((before == '"' || before == "'") && before == after) {
          start--;
          end++;
        }
      }
      removals.add((start: start, end: end));
    }

    if (calls.isEmpty) {
      return TextToolCallExtraction(
        cleanedContent: content,
        toolCalls: const [],
      );
    }

    var cleaned = content;
    for (final removal in removals.reversed) {
      cleaned = cleaned.replaceRange(removal.start, removal.end, '');
    }
    cleaned = cleaned.replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
    return TextToolCallExtraction(cleanedContent: cleaned, toolCalls: calls);
  }

  static int? _matchingParen(String value, int openParen) {
    if (openParen < 0) return null;
    var depth = 0;
    String? quote;
    var escaped = false;
    for (var index = openParen; index < value.length; index++) {
      final character = value[index];
      if (quote != null) {
        if (escaped) {
          escaped = false;
        } else if (character == '\\') {
          escaped = true;
        } else if (character == quote) {
          quote = null;
        }
        continue;
      }
      if (character == '"' || character == "'") {
        quote = character;
      } else if (character == '(') {
        depth++;
      } else if (character == ')') {
        depth--;
        if (depth == 0) return index;
      }
    }
    return null;
  }

  static Map<String, dynamic> _argumentsFor(String toolName, String raw) {
    final value = raw.trim();
    if (value.isEmpty) return const {};

    try {
      final decoded = jsonDecode(value);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
      if (decoded is String) return {_defaultArgumentName(toolName): decoded};
    } catch (_) {
      // The common `tool_code search("terms")` form is handled below.
    }

    final unquoted = _unquote(value);
    return {_defaultArgumentName(toolName): unquoted};
  }

  static String _defaultArgumentName(String toolName) {
    switch (toolName) {
      case 'calculator':
        return 'expression';
      case 'web_search':
      case 'local_document_search':
        return 'query';
      case 'web_scraper_reader':
      case 'webpage_reader':
        return 'url';
      case 'shell_command_runner':
        return 'command';
      case 'multi_step_planner':
        return 'task';
      case 'tool_router':
        return 'request';
      case 'mind_map_generator':
      case 'mind_map_tool':
        return 'topic';
      case 'workflow_automation':
        return 'objective';
      default:
        return 'input';
    }
  }

  static String _unquote(String value) {
    if (value.length >= 2 &&
        ((value.startsWith('"') && value.endsWith('"')) ||
            (value.startsWith("'") && value.endsWith("'")))) {
      return value.substring(1, value.length - 1);
    }
    return value;
  }
}
