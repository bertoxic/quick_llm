import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:docx_to_text/docx_to_text.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

enum OllamaStreamEventType {
  content,
  thinking,
  toolCall,
  toolResult,
  done,
  error,
}

class OllamaStreamEvent {
  final OllamaStreamEventType type;
  final String delta;
  final Map<String, dynamic>? raw;

  const OllamaStreamEvent._({
    required this.type,
    this.delta = '',
    this.raw,
  });

  const OllamaStreamEvent.content(String delta)
      : this._(type: OllamaStreamEventType.content, delta: delta);

  const OllamaStreamEvent.thinking(String delta)
      : this._(type: OllamaStreamEventType.thinking, delta: delta);

  const OllamaStreamEvent.toolCall(Map<String, dynamic> raw)
      : this._(type: OllamaStreamEventType.toolCall, raw: raw);

  const OllamaStreamEvent.toolResult(Map<String, dynamic> raw)
      : this._(type: OllamaStreamEventType.toolResult, raw: raw);

  const OllamaStreamEvent.done(Map<String, dynamic> raw)
      : this._(type: OllamaStreamEventType.done, raw: raw);

  const OllamaStreamEvent.error(String message, [Map<String, dynamic>? raw])
      : this._(type: OllamaStreamEventType.error, delta: message, raw: raw);

  bool get isContent => type == OllamaStreamEventType.content;
  bool get isThinking => type == OllamaStreamEventType.thinking;
  bool get isToolCall => type == OllamaStreamEventType.toolCall;
  bool get isToolResult => type == OllamaStreamEventType.toolResult;
  bool get isDone => type == OllamaStreamEventType.done;
  bool get isError => type == OllamaStreamEventType.error;
}

typedef OllamaToolExecutor = Future<List<Map<String, dynamic>>> Function(
  List<Map<String, dynamic>> toolCalls,
);

class OllamaService {
  static const String _baseUrl = 'http://localhost:11434';

  http.Client? _activeClient;
  bool _isGenerating = false;
  int _generationId = 0;

  void cancelGeneration() {
    if (!_isGenerating) return;
    debugPrint('Stopping active generation');
    _isGenerating = false;
    _generationId++;
    _activeClient?.close();
    _activeClient = null;
  }

  bool supportsThinking(String? modelName) {
    final normalized = modelName?.toLowerCase() ?? '';
    const thinkingModels = [
      'deepseek',
      'qwen',
      'qwq',
      'gpt-oss',
      'glm',
    ];
    return thinkingModels.any((name) => normalized.contains(name));
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
  }) async* {
    cancelGeneration();

    if (model == null || model.trim().isEmpty) {
      yield const OllamaStreamEvent.error('No model selected.');
      return;
    }

    final generationId = ++_generationId;
    final client = http.Client();
    _activeClient = client;
    _isGenerating = true;

    try {
      final url = Uri.parse('$_baseUrl/api/chat');
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

      final base64Images = await _encodeImages(images);
      final fallbackPrompt = _fallbackPromptForAttachments(
        prompt: prompt,
        hasDocuments: documentContext != null,
        hasImages: base64Images.isNotEmpty,
        hasMedia: attachmentContext != null,
      );

      if (messagesArray != null && messagesArray.isNotEmpty) {
        for (var i = 0; i < messagesArray.length; i++) {
          final msg = Map<String, dynamic>.from(messagesArray[i]);

          if (i == messagesArray.length - 1 && msg['role'] == 'user') {
            msg['content'] = _composePromptWithContext(
              (msg['content'] as String?)?.trim().isNotEmpty == true
                  ? msg['content'] as String
                  : fallbackPrompt,
              documentContext: documentContext,
              attachmentContext: attachmentContext,
            );

            if (base64Images.isNotEmpty) {
              msg['images'] = base64Images;
            }
          }

          messages.add(msg);
        }
      } else {
        final userMessage = <String, dynamic>{
          'role': 'user',
          'content': _composePromptWithContext(
            fallbackPrompt,
            documentContext: documentContext,
            attachmentContext: attachmentContext,
          ),
        };

        if (base64Images.isNotEmpty) {
          userMessage['images'] = base64Images;
        }

        messages.add(userMessage);
      }

      final shouldEnableThinking = enableThinking && supportsThinking(model);
      final options = {
        'temperature': temperature,
        'num_predict': maxTokens,
        'num_ctx': numCtx,
      };
      var toolSchemas =
          tools == null ? const <Map<String, dynamic>>[] : List.of(tools);
      final toolIterations = <Map<String, dynamic>>[];

      for (var iteration = 0;
          iteration <= maxToolIterations &&
              _isGenerating &&
              generationId == _generationId;
          iteration++) {
        final requestBody = <String, dynamic>{
          'model': model,
          'messages': messages,
          'stream': true,
          'options': options,
        };

        if (shouldEnableThinking) {
          requestBody['think'] = true;
        }

        if (toolSchemas.isNotEmpty) {
          requestBody['tools'] = toolSchemas;
        }

        debugPrint('Calling Ollama /api/chat');
        debugPrint('Model: $model');
        debugPrint('Messages: ${messages.length}');
        debugPrint('Images: ${base64Images.length}');
        debugPrint('Documents: ${documents?.length ?? 0}');
        debugPrint('Tools: ${toolSchemas.length}');
        debugPrint('Tool iteration: $iteration');

        final request = http.Request('POST', url)
          ..headers['Content-Type'] = 'application/json'
          ..body = jsonEncode(requestBody);

        final streamedResponse = timeout != null
            ? await client.send(request).timeout(timeout)
            : await client.send(request);

        if (streamedResponse.statusCode != 200) {
          final errorBody = await streamedResponse.stream.bytesToString();
          if (toolSchemas.isNotEmpty &&
              _isToolUnsupportedResponse(
                streamedResponse.statusCode,
                errorBody,
              )) {
            final fallback = {
              'iteration': iteration,
              'tool_fallback': 'disabled_for_model',
              'reason':
                  'Ollama reported that $model does not support native tools. Retrying this turn without tool schemas.',
              'status_code': streamedResponse.statusCode,
            };
            toolIterations.add(fallback);
            toolSchemas = const <Map<String, dynamic>>[];
            yield OllamaStreamEvent.toolResult(fallback);
            continue;
          }
          yield OllamaStreamEvent.error(
            'Ollama returned ${streamedResponse.statusCode}: $errorBody',
            {'status_code': streamedResponse.statusCode, 'body': errorBody},
          );
          return;
        }

        final turnThinking = StringBuffer();
        final turnContent = StringBuffer();
        final turnToolCalls = <Map<String, dynamic>>[];
        Map<String, dynamic>? donePayload;

        await for (final line in streamedResponse.stream
            .transform(utf8.decoder)
            .transform(const LineSplitter())) {
          if (!_isGenerating || generationId != _generationId) break;
          if (line.trim().isEmpty) continue;

          Map<String, dynamic> json;
          try {
            json = jsonDecode(line) as Map<String, dynamic>;
          } catch (e) {
            yield OllamaStreamEvent.error(
                'Could not parse Ollama stream line: $e');
            continue;
          }

          final streamError = json['error'] as String?;
          if (streamError != null && streamError.isNotEmpty) {
            yield OllamaStreamEvent.error(streamError, json);
            continue;
          }

          final message = json['message'];
          if (message is Map<String, dynamic>) {
            final thinking = message['thinking'] as String?;
            final content = message['content'] as String?;
            final toolCalls = _extractToolCalls(message['tool_calls']);

            if (thinking != null && thinking.isNotEmpty) {
              turnThinking.write(thinking);
              yield OllamaStreamEvent.thinking(thinking);
            }

            if (content != null && content.isNotEmpty) {
              turnContent.write(content);
              yield OllamaStreamEvent.content(content);
            }

            if (toolCalls.isNotEmpty) {
              turnToolCalls.addAll(toolCalls);
              yield OllamaStreamEvent.toolCall({
                'iteration': iteration,
                'tool_calls': toolCalls,
              });
            }
          }

          if (json['done'] == true) {
            donePayload = json;
            break;
          }
        }

        if (!_isGenerating || generationId != _generationId) {
          return;
        }

        if (turnThinking.isNotEmpty ||
            turnContent.isNotEmpty ||
            turnToolCalls.isNotEmpty) {
          messages.add({
            'role': 'assistant',
            'content': turnContent.toString(),
            if (turnThinking.isNotEmpty) 'thinking': turnThinking.toString(),
            if (turnToolCalls.isNotEmpty) 'tool_calls': turnToolCalls,
          });
        }

        if (turnToolCalls.isEmpty) {
          yield OllamaStreamEvent.done({
            ...?donePayload,
            '_request': {
              ...?requestMetadata,
              'message_count': messages.length,
              'system_prompt_used':
                  systemPrompt != null && systemPrompt.trim().isNotEmpty,
              'thinking_requested': enableThinking,
              'thinking_enabled': shouldEnableThinking,
              'images_sent': base64Images.length,
              'documents_attached': documents?.length ?? 0,
              'audio_attached': audio?.length ?? 0,
              'videos_attached': videos?.length ?? 0,
              'other_files_attached': otherFiles?.length ?? 0,
              'tool_schema_count': toolSchemas.length,
              'tool_iterations': toolIterations,
              'options': options,
            },
          });
          break;
        }

        if (toolExecutor == null) {
          yield OllamaStreamEvent.error(
            'The model requested a tool, but no tool executor is connected.',
            {'tool_calls': turnToolCalls},
          );
          return;
        }

        if (iteration >= maxToolIterations) {
          yield OllamaStreamEvent.error(
            'Tool loop stopped after $maxToolIterations iterations.',
            {'tool_calls': turnToolCalls},
          );
          return;
        }

        late final List<Map<String, dynamic>> toolMessages;
        String? toolExecutorError;
        try {
          toolMessages = await toolExecutor(turnToolCalls);
        } catch (error) {
          toolExecutorError = '$error';
          toolMessages = turnToolCalls.map((call) {
            final toolName = _toolNameForCall(call);
            return {
              'role': 'tool',
              'tool_name': toolName,
              'content':
                  '$toolName failed: $error. Continue from the available conversation context and explain the tool failure plainly.',
            };
          }).toList();
        }
        for (final toolMessage in toolMessages) {
          messages.add(toolMessage);
        }
        toolIterations.add({
          'iteration': iteration,
          'tool_calls': turnToolCalls,
          if (toolExecutorError != null) 'tool_error': toolExecutorError,
          'tool_results': toolMessages,
        });
        yield OllamaStreamEvent.toolResult({
          'iteration': iteration,
          if (toolExecutorError != null) 'tool_error': toolExecutorError,
          'tool_results': toolMessages,
        });
      }
    } on TimeoutException {
      yield const OllamaStreamEvent.error('Ollama request timed out.');
    } on http.ClientException catch (e) {
      if (_isGenerating) {
        yield OllamaStreamEvent.error('Connection failed: ${e.message}');
      }
    } catch (e) {
      yield OllamaStreamEvent.error('Error: $e');
    } finally {
      if (generationId == _generationId) {
        _cleanup();
      } else {
        client.close();
      }
    }
  }

  bool _isToolUnsupportedResponse(int statusCode, String body) {
    if (statusCode != 400) return false;
    final normalized = body.toLowerCase();
    return normalized.contains('does not support tools') ||
        normalized.contains('do not support tools') ||
        normalized.contains('tool support') ||
        normalized.contains('tools are not supported');
  }

  String _toolNameForCall(Map<String, dynamic> call) {
    final function = call['function'];
    if (function is Map) {
      final name = function['name'];
      if (name != null && '$name'.trim().isNotEmpty) return '$name';
    }
    return 'tool';
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

  List<Map<String, dynamic>> _extractToolCalls(dynamic rawToolCalls) {
    if (rawToolCalls is! List) return const [];

    final toolCalls = <Map<String, dynamic>>[];
    for (final rawCall in rawToolCalls) {
      if (rawCall is Map<String, dynamic>) {
        toolCalls.add(_normalizeToolCall(rawCall, toolCalls.length));
      } else if (rawCall is Map) {
        toolCalls.add(
          _normalizeToolCall(
              Map<String, dynamic>.from(rawCall), toolCalls.length),
        );
      }
    }
    return toolCalls;
  }

  Map<String, dynamic> _normalizeToolCall(
    Map<String, dynamic> raw,
    int fallbackIndex,
  ) {
    final normalized = Map<String, dynamic>.from(raw);
    final function = normalized['function'];
    if (function is Map<String, dynamic>) {
      normalized['function'] = _normalizeToolFunction(function, fallbackIndex);
    } else if (function is Map) {
      normalized['function'] = _normalizeToolFunction(
        Map<String, dynamic>.from(function),
        fallbackIndex,
      );
    }
    normalized['type'] ??= 'function';
    return normalized;
  }

  Map<String, dynamic> _normalizeToolFunction(
    Map<String, dynamic> function,
    int fallbackIndex,
  ) {
    final normalized = Map<String, dynamic>.from(function);
    normalized['index'] ??= fallbackIndex;

    final arguments = normalized['arguments'];
    if (arguments is String && arguments.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(arguments);
        if (decoded is Map<String, dynamic>) {
          normalized['arguments'] = decoded;
        } else if (decoded is Map) {
          normalized['arguments'] = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {
        normalized['arguments'] = {'input': arguments};
      }
    }

    return normalized;
  }

  Future<List<String>> _encodeImages(List<String>? imagePaths) async {
    if (imagePaths == null || imagePaths.isEmpty) return [];

    final encodedImages = <String>[];
    const imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

    for (final imagePath in imagePaths) {
      try {
        final file = File(imagePath);
        if (!await file.exists()) continue;

        final extension = _extension(imagePath);
        if (!imageExtensions.contains(extension)) continue;

        encodedImages.add(base64Encode(await file.readAsBytes()));
      } catch (e) {
        debugPrint('Error encoding image $imagePath: $e');
      }
    }

    return encodedImages;
  }

  bool isVisionModel(String modelName) {
    final normalized = modelName.toLowerCase();
    const visionModels = [
      'llava',
      'bakllava',
      'llama3.2-vision',
      'minicpm-v',
      'moondream',
      'gemma3',
    ];
    return visionModels.any((name) => normalized.contains(name));
  }

  Future<String> processDocument(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final extension = _extension(filePath);
      const textExtensions = [
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
      ];

      if (textExtensions.contains(extension)) {
        return await file.readAsString();
      }

      if (extension == '.pdf') {
        final bytes = await file.readAsBytes();
        final document = PdfDocument(inputBytes: bytes);
        final extractor = PdfTextExtractor(document);
        final text = extractor.extractText();
        document.dispose();
        return text;
      }

      if (extension == '.docx') {
        return docxToText(await file.readAsBytes());
      }

      return '[Unsupported document format: ${_fileName(filePath)}]';
    } catch (e) {
      debugPrint('Error processing document: $e');
      return '[Error reading document: ${_fileName(filePath)}]';
    }
  }

  Future<String?> _buildDocumentContext(List<String>? documents) async {
    if (documents == null || documents.isEmpty) return null;

    final chunks = <String>[];
    for (var i = 0; i < documents.length; i++) {
      final path = documents[i];
      final content = await processDocument(path);
      if (content.trim().isEmpty || content.startsWith('[Error')) continue;

      chunks.add([
        'DOCUMENT ${i + 1} of ${documents.length}: ${_fileName(path)}',
        content,
        'END DOCUMENT ${i + 1}',
      ].join('\n'));
    }

    if (chunks.isEmpty) return null;
    return chunks.join('\n\n');
  }

  Future<String?> _buildAttachmentContext({
    List<String>? audio,
    List<String>? videos,
    List<String>? otherFiles,
  }) async {
    final lines = <String>[];

    Future<void> addFiles(String label, List<String>? paths) async {
      if (paths == null || paths.isEmpty) return;
      for (final path in paths) {
        final file = File(path);
        final exists = await file.exists();
        final size = exists ? await file.length() : null;
        lines.add('- $label: ${_fileName(path)}'
            '${size == null ? '' : ' (${_formatBytes(size)})'}');
      }
    }

    await addFiles('Audio attachment', audio);
    await addFiles('Video attachment', videos);
    await addFiles('File attachment', otherFiles);

    if (lines.isEmpty) return null;
    return [
      'The user attached the following files. Ollama chat can receive image bytes and extracted document text directly; the listed media/binary files are provided as metadata unless a model/tool can interpret them.',
      ...lines,
    ].join('\n');
  }

  String _composePromptWithContext(
    String prompt, {
    String? documentContext,
    String? attachmentContext,
  }) {
    final sections = <String>[];

    if (documentContext != null && documentContext.trim().isNotEmpty) {
      sections.add('Attached document text:\n$documentContext');
    }

    if (attachmentContext != null && attachmentContext.trim().isNotEmpty) {
      sections.add('Attached file metadata:\n$attachmentContext');
    }

    sections.add('User message:\n${prompt.trim()}');
    return sections.join('\n\n');
  }

  String _fallbackPromptForAttachments({
    required String prompt,
    required bool hasDocuments,
    required bool hasImages,
    required bool hasMedia,
  }) {
    if (prompt.trim().isNotEmpty) return prompt.trim();
    if (hasDocuments || hasImages || hasMedia) {
      return 'Please analyze the attached file(s) and respond with the most useful observations.';
    }
    return prompt.trim();
  }

  void _cleanup() {
    _isGenerating = false;
    _activeClient?.close();
    _activeClient = null;
  }

  Future<List<String>> fetchAvailableModels({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/tags');
      final response = await http.get(url).timeout(timeout);

      if (response.statusCode != 200) {
        debugPrint('Failed to fetch models: ${response.statusCode}');
        return [];
      }

      final json = jsonDecode(response.body) as Map<String, dynamic>;
      final models =
          (json['models'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
      if (models == null) return [];

      return models
          .map((model) => model['name'] as String?)
          .whereType<String>()
          .where((name) => name.isNotEmpty)
          .toList();
    } on TimeoutException {
      debugPrint('Model fetch timed out');
      return [];
    } on http.ClientException catch (e) {
      debugPrint('Connection error fetching models: ${e.message}');
      return [];
    } catch (e) {
      debugPrint('Error fetching models: $e');
      return [];
    }
  }

  String _formatBytes(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    return '${size.toStringAsFixed(size >= 10 || unitIndex == 0 ? 0 : 1)} ${units[unitIndex]}';
  }

  String _extension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return '';
    return path.substring(dotIndex).toLowerCase();
  }

  String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;

  void dispose() {
    cancelGeneration();
  }
}
