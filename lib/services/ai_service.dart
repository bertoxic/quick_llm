import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../models/ai_provider.dart';
import '../utils/text_tool_call_parser.dart';
import 'ollama_service.dart';

/// One streaming interface for Ollama and OpenAI-compatible servers.
///
/// The OpenAI-compatible route covers OpenAI, LM Studio, vLLM, LocalAI,
/// OpenRouter, Groq, Together, and other servers that implement
/// `/v1/models` plus `/v1/chat/completions`.
class AiService {
  AiService(AiProviderConfig configuration) : _configuration = configuration {
    _ollama = OllamaService(baseUrl: configuration.normalizedEndpoint);
  }

  AiProviderConfig _configuration;
  late OllamaService _ollama;
  http.Client? _activeOpenAiClient;
  bool _isOpenAiGenerating = false;
  int _openAiGenerationId = 0;

  AiProviderConfig get configuration => _configuration;

  void configure(AiProviderConfig configuration) {
    final hasChanged = configuration.kind != _configuration.kind ||
        configuration.normalizedEndpoint != _configuration.normalizedEndpoint ||
        configuration.apiKey != _configuration.apiKey;
    if (!hasChanged) return;

    cancelGeneration();
    _configuration = configuration;
    _ollama.dispose();
    _ollama = OllamaService(baseUrl: configuration.normalizedEndpoint);
  }

  void cancelGeneration() {
    _ollama.cancelGeneration();
    _isOpenAiGenerating = false;
    _openAiGenerationId++;
    _activeOpenAiClient?.close();
    _activeOpenAiClient = null;
  }

  void dispose() {
    cancelGeneration();
    _ollama.dispose();
  }

  bool supportsThinking(String? modelName) {
    return _ollama.supportsThinking(modelName);
  }

  bool isVisionModel(String modelName) => _ollama.isVisionModel(modelName);

  Future<List<String>> fetchAvailableModels({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    if (_configuration.kind == AiProviderKind.ollama) {
      return _ollama.fetchAvailableModels(timeout: timeout);
    }

    try {
      final response = await http
          .get(
            Uri.parse(_configuration.modelEndpoint),
            headers: _headers,
          )
          .timeout(timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Failed to fetch ${_configuration.displayName} models: '
          '${response.statusCode}',
        );
        return const [];
      }

      final decoded = jsonDecode(response.body);
      if (decoded is! Map) return const [];
      final data = decoded['data'];
      if (data is! List) return const [];

      final models = data
          .whereType<Map>()
          .map((item) => '${item['id'] ?? item['name'] ?? ''}'.trim())
          .where((model) => model.isNotEmpty)
          .toSet()
          .toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
      return models;
    } catch (error) {
      debugPrint(
          'Could not fetch ${_configuration.displayName} models: $error');
      return const [];
    }
  }

  Stream<OllamaStreamEvent> generateChatResponse({
    required String? model,
    required String prompt,
    List<Map<String, String>>? messagesArray,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 2048,
    int numCtx = 18193,
    bool enableThinking = true,
    List<String>? images,
    List<String>? documents,
    List<String>? audio,
    List<String>? videos,
    List<String>? otherFiles,
    List<Map<String, dynamic>>? tools,
    OllamaToolExecutor? toolExecutor,
    int maxToolIterations = 32,
    Duration? timeout,
    Map<String, dynamic>? requestMetadata,
  }) {
    if (_configuration.kind == AiProviderKind.ollama) {
      return _ollama.generateChatResponse(
        model: model,
        prompt: prompt,
        messagesArray: messagesArray,
        systemPrompt: systemPrompt,
        temperature: temperature,
        maxTokens: maxTokens,
        numCtx: numCtx,
        enableThinking: enableThinking,
        images: images,
        documents: documents,
        audio: audio,
        videos: videos,
        otherFiles: otherFiles,
        tools: tools,
        toolExecutor: toolExecutor,
        maxToolIterations: maxToolIterations,
        timeout: timeout,
        requestMetadata: requestMetadata,
      );
    }

    return _generateOpenAiCompatibleResponse(
      model: model,
      prompt: prompt,
      messagesArray: messagesArray,
      systemPrompt: systemPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
      enableThinking: enableThinking,
      images: images,
      documents: documents,
      audio: audio,
      videos: videos,
      otherFiles: otherFiles,
      tools: tools,
      toolExecutor: toolExecutor,
      maxToolIterations: maxToolIterations,
      timeout: timeout,
      requestMetadata: requestMetadata,
    );
  }

  Stream<String> generateResponse({
    required String? model,
    required String prompt,
    List<Map<String, String>>? messagesArray,
    String? systemPrompt,
    double temperature = 0.7,
    int maxTokens = 2048,
    int numCtx = 18193,
    bool enableThinking = true,
    List<String>? images,
    List<String>? documents,
    List<Map<String, dynamic>>? tools,
    OllamaToolExecutor? toolExecutor,
    int maxToolIterations = 4,
    Duration? timeout,
  }) async* {
    var hasStartedThinking = false;
    var hasFinishedThinking = false;

    await for (final event in generateChatResponse(
      model: model,
      prompt: prompt,
      messagesArray: messagesArray,
      systemPrompt: systemPrompt,
      temperature: temperature,
      maxTokens: maxTokens,
      numCtx: numCtx,
      enableThinking: enableThinking,
      images: images,
      documents: documents,
      tools: tools,
      toolExecutor: toolExecutor,
      maxToolIterations: maxToolIterations,
      timeout: timeout,
    )) {
      if (event.isThinking) {
        if (!hasStartedThinking) {
          yield 'Thinking...';
          hasStartedThinking = true;
        }
        yield event.delta;
      } else if (event.isContent) {
        if (hasStartedThinking && !hasFinishedThinking) {
          yield '...done thinking.';
          hasFinishedThinking = true;
        }
        yield event.delta;
      } else if (event.isError) {
        yield event.delta;
      }
    }
  }

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'Accept': 'text/event-stream, application/json',
        if (_configuration.apiKey.trim().isNotEmpty)
          'Authorization': 'Bearer ${_configuration.apiKey.trim()}',
      };

  Stream<OllamaStreamEvent> _generateOpenAiCompatibleResponse({
    required String? model,
    required String prompt,
    List<Map<String, String>>? messagesArray,
    String? systemPrompt,
    required double temperature,
    required int maxTokens,
    required bool enableThinking,
    List<String>? images,
    List<String>? documents,
    List<String>? audio,
    List<String>? videos,
    List<String>? otherFiles,
    List<Map<String, dynamic>>? tools,
    OllamaToolExecutor? toolExecutor,
    required int maxToolIterations,
    Duration? timeout,
    Map<String, dynamic>? requestMetadata,
  }) async* {
    if (model == null || model.trim().isEmpty) {
      yield const OllamaStreamEvent.error('No model selected.');
      return;
    }

    cancelGeneration();
    final generationId = ++_openAiGenerationId;
    final client = http.Client();
    _activeOpenAiClient = client;
    _isOpenAiGenerating = true;

    try {
      final messages = await _buildOpenAiMessages(
        prompt: prompt,
        messagesArray: messagesArray,
        systemPrompt: systemPrompt,
        images: images,
        documents: documents,
        audio: audio,
        videos: videos,
        otherFiles: otherFiles,
      );
      var toolSchemas = tools == null
          ? <Map<String, dynamic>>[]
          : List<Map<String, dynamic>>.from(tools);
      final toolIterations = <Map<String, dynamic>>[];

      for (var iteration = 0;
          iteration <= maxToolIterations &&
              _isOpenAiGenerating &&
              generationId == _openAiGenerationId;
          iteration++) {
        final requestBody = <String, dynamic>{
          'model': model.trim(),
          'messages': messages,
          'stream': true,
          'temperature': temperature,
          'max_tokens': maxTokens,
          if (toolSchemas.isNotEmpty) 'tools': toolSchemas,
        };

        final request = http.Request(
          'POST',
          Uri.parse(_configuration.chatEndpoint),
        )
          ..headers.addAll(_headers)
          ..body = jsonEncode(requestBody);

        final streamedResponse = timeout != null
            ? await client.send(request).timeout(timeout)
            : await client.send(request);
        if (streamedResponse.statusCode < 200 ||
            streamedResponse.statusCode >= 300) {
          final body = await streamedResponse.stream.bytesToString();
          if (toolSchemas.isNotEmpty && _isToolUnsupported(body)) {
            final fallback = {
              'iteration': iteration,
              'tool_fallback': 'disabled_for_model',
              'reason':
                  '${_configuration.displayName} reported that $model does not support native tools. Retrying without tool schemas.',
              'status_code': streamedResponse.statusCode,
            };
            toolIterations.add(fallback);
            toolSchemas = <Map<String, dynamic>>[];
            yield OllamaStreamEvent.toolResult(fallback);
            continue;
          }
          yield OllamaStreamEvent.error(
            '${_configuration.displayName} returned '
            '${streamedResponse.statusCode}: ${_shortError(body)}',
            {'status_code': streamedResponse.statusCode, 'body': body},
          );
          return;
        }

        final turnContent = StringBuffer();
        final turnThinking = StringBuffer();
        final toolCallsByIndex = <int, Map<String, dynamic>>{};
        Map<String, dynamic>? finalPayload;

        await for (final line in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!_isOpenAiGenerating || generationId != _openAiGenerationId) {
            break;
          }
          final payload = _payloadFromSseLine(line);
          if (payload == null) continue;
          if (payload == '[DONE]') break;

          final decoded = _decodePayload(payload);
          if (decoded == null) continue;
          if (decoded['error'] != null) {
            yield OllamaStreamEvent.error('${decoded['error']}', decoded);
            continue;
          }
          finalPayload = decoded;
          final choices = decoded['choices'];
          if (choices is! List || choices.isEmpty || choices.first is! Map) {
            continue;
          }
          final choice = Map<String, dynamic>.from(choices.first as Map);
          final delta = choice['delta'] is Map
              ? Map<String, dynamic>.from(choice['delta'] as Map)
              : choice['message'] is Map
                  ? Map<String, dynamic>.from(choice['message'] as Map)
                  : const <String, dynamic>{};

          final thinking = _stringContent(
            delta['reasoning_content'] ??
                delta['reasoning'] ??
                delta['thinking'],
          );
          if (enableThinking && thinking.isNotEmpty) {
            turnThinking.write(thinking);
            yield OllamaStreamEvent.thinking(thinking);
          }

          final content = _stringContent(delta['content']);
          if (content.isNotEmpty) {
            turnContent.write(content);
            yield OllamaStreamEvent.content(content);
          }

          final rawToolCalls = delta['tool_calls'];
          if (rawToolCalls is List) {
            _mergeOpenAiToolCalls(toolCallsByIndex, rawToolCalls);
          }
        }

        if (!_isOpenAiGenerating || generationId != _openAiGenerationId) {
          return;
        }

        var canonicalToolCalls = toolCallsByIndex.entries
            .map((entry) => _canonicalToolCall(entry.value, entry.key))
            .toList();
        var outgoingToolCalls = toolCallsByIndex.entries
            .map((entry) => _openAiToolCall(entry.value, entry.key))
            .toList();
        if (canonicalToolCalls.isEmpty && toolSchemas.isNotEmpty) {
          final textToolCall = TextToolCallParser.extract(
            content: turnContent.toString(),
            toolSchemas: toolSchemas,
            iteration: iteration,
          );
          if (textToolCall.hasToolCalls) {
            canonicalToolCalls = textToolCall.toolCalls;
            outgoingToolCalls =
                canonicalToolCalls.map(_canonicalToOpenAiToolCall).toList();
            turnContent
              ..clear()
              ..write(textToolCall.cleanedContent);
            yield OllamaStreamEvent.contentReplacement(
              textToolCall.cleanedContent,
            );
            yield OllamaStreamEvent.toolCall({
              'iteration': iteration,
              'tool_calls': canonicalToolCalls,
              'protocol': 'text_tool_code_compatibility',
            });
          }
        }
        if (turnContent.isNotEmpty ||
            turnThinking.isNotEmpty ||
            canonicalToolCalls.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'content': turnContent.toString(),
            if (canonicalToolCalls.isNotEmpty) 'tool_calls': outgoingToolCalls,
          });
        }

        if (canonicalToolCalls.isEmpty) {
          yield OllamaStreamEvent.done({
            ...?finalPayload,
            '_request': {
              ...?requestMetadata,
              'provider': _configuration.displayName,
              'provider_kind': _configuration.kind.name,
              'endpoint': _configuration.normalizedEndpoint,
              'message_count': messages.length,
              'system_prompt_used':
                  systemPrompt != null && systemPrompt.trim().isNotEmpty,
              'thinking_requested': enableThinking,
              'documents_attached': documents?.length ?? 0,
              'images_attached': images?.length ?? 0,
              'tool_schema_count': toolSchemas.length,
              'tool_iterations': toolIterations,
            },
          });
          return;
        }

        yield OllamaStreamEvent.toolCall({
          'iteration': iteration,
          'tool_calls': canonicalToolCalls,
        });
        if (toolExecutor == null) {
          yield OllamaStreamEvent.error(
            'The model requested a tool, but no tool executor is connected.',
            {'tool_calls': canonicalToolCalls},
          );
          return;
        }
        if (iteration >= maxToolIterations) {
          yield OllamaStreamEvent.error(
            'Tool loop stopped after $maxToolIterations iterations.',
            {'tool_calls': canonicalToolCalls},
          );
          return;
        }

        late final List<Map<String, dynamic>> toolMessages;
        String? toolExecutorError;
        try {
          toolMessages = await toolExecutor(canonicalToolCalls);
        } catch (error) {
          toolExecutorError = '$error';
          toolMessages = canonicalToolCalls
              .map(
                (call) => {
                  'role': 'tool',
                  'tool_name': _toolName(call),
                  'content': '${_toolName(call)} failed: $error',
                },
              )
              .toList();
        }

        for (var index = 0; index < canonicalToolCalls.length; index++) {
          final result = index < toolMessages.length
              ? toolMessages[index]
              : <String, dynamic>{
                  'content':
                      '${_toolName(canonicalToolCalls[index])} returned no result.',
                };
          messages.add({
            'role': 'tool',
            'tool_call_id': '${canonicalToolCalls[index]['id']}',
            'content': '${result['content'] ?? ''}',
          });
        }

        final details = {
          'iteration': iteration,
          'tool_calls': canonicalToolCalls,
          if (toolExecutorError != null) 'tool_error': toolExecutorError,
          'tool_results': toolMessages,
        };
        toolIterations.add(details);
        yield OllamaStreamEvent.toolResult(details);
      }
    } on TimeoutException {
      yield OllamaStreamEvent.error(
        '${_configuration.displayName} request timed out.',
      );
    } on http.ClientException catch (error) {
      if (_isOpenAiGenerating) {
        yield OllamaStreamEvent.error('Connection failed: ${error.message}');
      }
    } catch (error) {
      yield OllamaStreamEvent.error('Error: $error');
    } finally {
      if (generationId == _openAiGenerationId) {
        _isOpenAiGenerating = false;
        _activeOpenAiClient?.close();
        _activeOpenAiClient = null;
      } else {
        client.close();
      }
    }
  }

  Future<List<Map<String, dynamic>>> _buildOpenAiMessages({
    required String prompt,
    List<Map<String, String>>? messagesArray,
    String? systemPrompt,
    List<String>? images,
    List<String>? documents,
    List<String>? audio,
    List<String>? videos,
    List<String>? otherFiles,
  }) async {
    final messages = <Map<String, dynamic>>[];
    if (systemPrompt != null && systemPrompt.trim().isNotEmpty) {
      messages.add({'role': 'system', 'content': systemPrompt.trim()});
    }

    final documentContext = await _buildDocumentContext(documents);
    final attachmentContext = await _buildAttachmentContext(
      audio: audio,
      videos: videos,
      otherFiles: otherFiles,
    );
    final imageUrls = await _encodeImageUrls(images);
    final fallbackPrompt = prompt.trim().isNotEmpty
        ? prompt.trim()
        : (documentContext != null ||
                attachmentContext != null ||
                imageUrls.isNotEmpty)
            ? 'Please analyze the attached file(s) and respond with the most useful observations.'
            : '';

    final history = messagesArray == null
        ? <Map<String, String>>[]
        : List<Map<String, String>>.from(messagesArray);
    if (history.isEmpty) {
      messages.add(
        _openAiUserMessage(
          _composePrompt(
            fallbackPrompt,
            documentContext: documentContext,
            attachmentContext: attachmentContext,
          ),
          imageUrls,
        ),
      );
      return messages;
    }

    for (var index = 0; index < history.length; index++) {
      final item = history[index];
      final role = item['role'] == 'assistant' ? 'assistant' : 'user';
      final isLatestUser = index == history.length - 1 && role == 'user';
      final content = isLatestUser
          ? _composePrompt(
              item['content']?.trim().isNotEmpty == true
                  ? item['content']!.trim()
                  : fallbackPrompt,
              documentContext: documentContext,
              attachmentContext: attachmentContext,
            )
          : item['content'] ?? '';
      messages.add(
        isLatestUser
            ? _openAiUserMessage(content, imageUrls)
            : {
                'role': role,
                'content': content,
              },
      );
    }
    return messages;
  }

  Map<String, dynamic> _openAiUserMessage(
    String text,
    List<String> imageUrls,
  ) {
    if (imageUrls.isEmpty) return {'role': 'user', 'content': text};
    return {
      'role': 'user',
      'content': [
        {'type': 'text', 'text': text},
        ...imageUrls.map(
          (url) => {
            'type': 'image_url',
            'image_url': {'url': url},
          },
        ),
      ],
    };
  }

  Future<List<String>> _encodeImageUrls(List<String>? imagePaths) async {
    if (imagePaths == null || imagePaths.isEmpty) return const [];
    final urls = <String>[];
    const allowed = {'.jpg', '.jpeg', '.png', '.gif', '.webp'};
    for (final path in imagePaths) {
      try {
        final file = File(path);
        final extension = _extension(path);
        if (!allowed.contains(extension) || !await file.exists()) continue;
        final mime = extension == '.jpg' || extension == '.jpeg'
            ? 'image/jpeg'
            : extension == '.png'
                ? 'image/png'
                : extension == '.gif'
                    ? 'image/gif'
                    : 'image/webp';
        urls.add('data:$mime;base64,${base64Encode(await file.readAsBytes())}');
      } catch (error) {
        debugPrint('Error encoding image $path: $error');
      }
    }
    return urls;
  }

  Future<String?> _buildDocumentContext(List<String>? documents) async {
    if (documents == null || documents.isEmpty) return null;
    final sections = <String>[];
    for (var index = 0; index < documents.length; index++) {
      final text = await _readDocument(documents[index]);
      if (text.trim().isEmpty || text.startsWith('[Error')) continue;
      // Protect remote-provider requests from accidentally sending an
      // unbounded file while still making substantial documents useful.
      final trimmed = text.length > 120000
          ? '${text.substring(0, 120000)}\n\n[Document truncated for this request.]'
          : text;
      sections.add(
        'DOCUMENT ${index + 1} of ${documents.length}: '
        '${_fileName(documents[index])}\n$trimmed\nEND DOCUMENT ${index + 1}',
      );
    }
    return sections.isEmpty ? null : sections.join('\n\n');
  }

  Future<String> _readDocument(String path) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        return '[Error reading document: ${_fileName(path)}]';
      }
      const textExtensions = {
        '.txt',
        '.md',
        '.csv',
        '.tsv',
        '.json',
        '.yaml',
        '.yml',
        '.xml',
        '.html',
        '.htm',
        '.log',
        '.rtf',
      };
      final extension = _extension(path);
      if (textExtensions.contains(extension)) return file.readAsString();
      if (extension == '.pdf') {
        final document = PdfDocument(inputBytes: await file.readAsBytes());
        final text = PdfTextExtractor(document).extractText();
        document.dispose();
        return text;
      }
      if (extension == '.docx') return docxToText(await file.readAsBytes());
      return '[Unsupported document format: ${_fileName(path)}]';
    } catch (error) {
      debugPrint('Error reading document $path: $error');
      return '[Error reading document: ${_fileName(path)}]';
    }
  }

  Future<String?> _buildAttachmentContext({
    List<String>? audio,
    List<String>? videos,
    List<String>? otherFiles,
  }) async {
    final lines = <String>[];
    Future<void> collect(String label, List<String>? paths) async {
      if (paths == null) return;
      for (final path in paths) {
        final file = File(path);
        final bytes = await file.exists() ? await file.length() : null;
        lines.add(
            '- $label: ${_fileName(path)}${bytes == null ? '' : ' ($bytes bytes)'}');
      }
    }

    await collect('Audio attachment', audio);
    await collect('Video attachment', videos);
    await collect('File attachment', otherFiles);
    if (lines.isEmpty) return null;
    return [
      'The following non-text attachments are available as metadata. '
          'Explain any limitation rather than claiming to have inspected binary media.',
      ...lines,
    ].join('\n');
  }

  String _composePrompt(
    String prompt, {
    String? documentContext,
    String? attachmentContext,
  }) {
    return [
      if (documentContext != null) 'Attached document text:\n$documentContext',
      if (attachmentContext != null)
        'Attached file metadata:\n$attachmentContext',
      'User message:\n$prompt',
    ].join('\n\n');
  }

  String? _payloadFromSseLine(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty ||
        trimmed.startsWith('event:') ||
        trimmed.startsWith(':')) {
      return null;
    }
    return trimmed.startsWith('data:') ? trimmed.substring(5).trim() : trimmed;
  }

  Map<String, dynamic>? _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) return decoded;
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      debugPrint('Could not parse OpenAI-compatible stream payload.');
    }
    return null;
  }

  void _mergeOpenAiToolCalls(
    Map<int, Map<String, dynamic>> target,
    List<dynamic> rawCalls,
  ) {
    for (var fallbackIndex = 0;
        fallbackIndex < rawCalls.length;
        fallbackIndex++) {
      final raw = rawCalls[fallbackIndex];
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final index =
          map['index'] is num ? (map['index'] as num).toInt() : fallbackIndex;
      final current = target.putIfAbsent(index, () => {'index': index});
      if (map['id'] != null) current['id'] = '${map['id']}';
      current['type'] = '${map['type'] ?? current['type'] ?? 'function'}';
      final rawFunction = map['function'];
      if (rawFunction is Map) {
        final function = Map<String, dynamic>.from(rawFunction);
        final currentFunction = current.putIfAbsent(
          'function',
          () => <String, dynamic>{'arguments': ''},
        ) as Map<String, dynamic>;
        if ('${function['name'] ?? ''}'.isNotEmpty) {
          currentFunction['name'] = '${function['name']}';
        }
        if (function['arguments'] != null) {
          currentFunction['arguments'] =
              '${currentFunction['arguments'] ?? ''}${function['arguments']}';
        }
      }
    }
  }

  Map<String, dynamic> _openAiToolCall(Map<String, dynamic> raw, int index) {
    final function = raw['function'] is Map
        ? Map<String, dynamic>.from(raw['function'] as Map)
        : <String, dynamic>{};
    return {
      'id': '${raw['id'] ?? 'call_$index'}',
      'type': 'function',
      'function': {
        'name': '${function['name'] ?? 'tool'}',
        'arguments': '${function['arguments'] ?? '{}'}',
      },
    };
  }

  Map<String, dynamic> _canonicalToolCall(Map<String, dynamic> raw, int index) {
    final oaiCall = _openAiToolCall(raw, index);
    final function = Map<String, dynamic>.from(oaiCall['function'] as Map);
    final rawArguments = '${function['arguments'] ?? ''}';
    Map<String, dynamic> arguments = const {};
    if (rawArguments.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawArguments);
        if (decoded is Map) arguments = Map<String, dynamic>.from(decoded);
      } catch (_) {
        arguments = {'input': rawArguments};
      }
    }
    return {
      'id': oaiCall['id'],
      'type': 'function',
      'function': {
        'name': function['name'],
        'arguments': arguments,
      },
    };
  }

  Map<String, dynamic> _canonicalToOpenAiToolCall(
    Map<String, dynamic> call,
  ) {
    final function = call['function'] is Map
        ? Map<String, dynamic>.from(call['function'] as Map)
        : <String, dynamic>{};
    final arguments = function['arguments'];
    return {
      'id': '${call['id'] ?? 'call'}',
      'type': 'function',
      'function': {
        'name': '${function['name'] ?? 'tool'}',
        'arguments':
            arguments is String ? arguments : jsonEncode(arguments ?? {}),
      },
    };
  }

  String _toolName(Map<String, dynamic> call) {
    final function = call['function'];
    return function is Map && '${function['name'] ?? ''}'.trim().isNotEmpty
        ? '${function['name']}'
        : 'tool';
  }

  String _stringContent(dynamic value) {
    if (value is String) return value;
    if (value is List) {
      return value
          .whereType<Map>()
          .map((part) => '${part['text'] ?? part['content'] ?? ''}')
          .join();
    }
    return value == null ? '' : '$value';
  }

  bool _isToolUnsupported(String body) {
    final normalized = body.toLowerCase();
    return normalized.contains('does not support tools') ||
        normalized.contains('tool support') ||
        normalized.contains('tools are not supported') ||
        normalized.contains('unsupported parameter') &&
            normalized.contains('tools');
  }

  String _shortError(String body) {
    final compact = body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length > 800 ? '${compact.substring(0, 800)}…' : compact;
  }

  String _extension(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot).toLowerCase();
  }

  String _fileName(String path) {
    final separator = Platform.pathSeparator;
    final normalized =
        path.replaceAll('\\', separator).replaceAll('/', separator);
    final index = normalized.lastIndexOf(separator);
    return index == -1 ? normalized : normalized.substring(index + 1);
  }
}
