import 'package:docx_to_text/docx_to_text.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

class OllamaService {
  static const String _baseUrl = 'http://localhost:11434';

  http.Client? _activeClient;
  StreamController<String>? _activeController;
  StreamSubscription? _activeSubscription;
  bool _isGenerating = false;
  final _cleanupLock = <String, bool>{};

  void cancelGeneration() {
    if (!_isGenerating) return;
    print('🛑 Cancelling active generation');
    _cleanup();
  }

  bool supportsThinking(String? modelName) {
    final thinkingModels = [
      //'deepseek',
      //'qwen',
      //'qwq',
    ];
    return thinkingModels.any((tm) => modelName?.toLowerCase().contains(tm)??false);
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
    Duration? timeout,
  }) async* {
    cancelGeneration();

    _activeClient = http.Client();
    _activeController = StreamController<String>.broadcast();
    _isGenerating = true;

    bool hasStartedThinking = false;
    bool hasFinishedThinking = false;

    try {
      final url = Uri.parse('$_baseUrl/api/chat');
      final messages = <Map<String, dynamic>>[];

      if (systemPrompt != null && systemPrompt.isNotEmpty) {
        messages.add({'role': 'system', 'content': systemPrompt});
      }

      String? documentContext;
      if (documents != null && documents.isNotEmpty) {
        final docContents = await Future.wait(
          documents.asMap().entries.map((entry) async {
            final i = entry.key;
            final docPath = entry.value;
            try {
              final content = await processDocument(docPath);
              if (content.isNotEmpty && !content.startsWith('[Error')) {
                final fileName = docPath.split('/').last;
                final buffer = StringBuffer();
                buffer.writeln('═══════════════════════════════════════════════════════════');
                buffer.writeln('DOCUMENT ${i + 1} of ${documents.length}: $fileName');
                buffer.writeln('═══════════════════════════════════════════════════════════');
                buffer.writeln(content);
                buffer.writeln('═══════════════════════════════════════════════════════════');
                buffer.writeln('END OF DOCUMENT ${i + 1}');
                buffer.writeln('═══════════════════════════════════════════════════════════');
                return buffer.toString();
              }
            } catch (e) {
              debugPrint('⚠️ Skipping document $docPath: $e');
            }
            return null;
          }),
        );

        final validDocs = docContents.whereType<String>().toList();
        if (validDocs.isNotEmpty) {
          documentContext = '${validDocs.join('\n\n')}\n';
          print('📄 Processed ${validDocs.length} document(s)');
        }
      }

      List<String>? base64Images;
      if (images != null && images.isNotEmpty) {
        base64Images = await _encodeImages(images);
        if (base64Images.isNotEmpty) {
          print('📷 Encoded ${base64Images.length} image(s)');
        }
      }

      String finalPrompt = prompt;
      if (documentContext != null) {
        final docCount = documents?.length ?? 0;
        final buffer = StringBuffer();
        buffer.writeln('I am providing you with $docCount document(s) below. Please read ALL of them carefully before answering my question.');
        buffer.writeln();
        buffer.write(documentContext);
        buffer.writeln();
        buffer.writeln('USER QUESTION (regarding the documents above): $prompt');
        buffer.writeln();
        buffer.write('IMPORTANT: Base your answer on information from ALL provided documents, not just the first one.');
        finalPrompt = buffer.toString();
      }

      if (messagesArray != null && messagesArray.isNotEmpty) {
        for (int i = 0; i < messagesArray.length; i++) {
          final msg = Map<String, dynamic>.from(messagesArray[i]);

          if (i == messagesArray.length - 1 && msg['role'] == 'user') {
            if (documentContext != null) {
              msg['content'] = '$documentContext\n\n${msg['content']}';
            }
            if (base64Images != null && base64Images.isNotEmpty) {
              msg['images'] = base64Images;
            }
          }
          messages.add(msg);
        }
      } else {
        final userMessage = <String, dynamic>{
          'role': 'user',
          'content': finalPrompt,
        };
        if (base64Images != null && base64Images.isNotEmpty) {
          userMessage['images'] = base64Images;
        }
        messages.add(userMessage);
      }

      print('🔗 Calling Ollama /chat endpoint');
      print('   Model: $model');
      print('   Messages: ${messages.length}');
      print('   Temperature: $temperature');
      print('   Max tokens: $maxTokens');
      print('   Has images: ${base64Images?.isNotEmpty ?? false}');
      print('   Has documents: ${documentContext != null}');

      final modelSupportsThinking = supportsThinking(model);
      final shouldEnableThinking = enableThinking && modelSupportsThinking;

      print('   Model supports thinking: $modelSupportsThinking');
      print('   Thinking enabled: $shouldEnableThinking');

      final requestBody = {
        'model': model,
        'messages': messages,
        'stream': true,
        'options': {
          'temperature': temperature,
          'num_predict': maxTokens,
          'num_ctx': numCtx,
        },
      };

      if (shouldEnableThinking) {
        requestBody['think'] = true;
        print('   ✅ Think mode activated');
      } else if (enableThinking && !modelSupportsThinking) {
        print('   ⚠️ Thinking requested but model does not support it');
      }

      final request = http.Request('POST', url)
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode(requestBody);

      final streamedResponse = timeout != null
          ? await _activeClient!.send(request).timeout(timeout)
          : await _activeClient!.send(request);

      if (streamedResponse.statusCode != 200) {
        final errorBody = await streamedResponse.stream.bytesToString();
        throw Exception(
          'Failed to generate response: ${streamedResponse.statusCode}\n$errorBody',
        );
      }

      // Process stream without debouncing - emit tokens immediately
      _activeSubscription = streamedResponse.stream
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .listen(
            (line) {
          if (line.trim().isEmpty || !_isGenerating) return;

          final controller = _activeController;
          if (controller == null || controller.isClosed) return;

          try {
            final json = jsonDecode(line) as Map<String, dynamic>;

            final thinking = json['message']?['thinking'] as String?;
            final content = json['message']?['content'] as String?;
            final done = json['done'] as bool?;

            bool hasThinking = thinking != null && thinking.isNotEmpty;
            bool hasContent = content != null && content.isNotEmpty;

            if (hasThinking) {
              if (!hasStartedThinking) {
                controller.add('Thinking...');
                hasStartedThinking = true;
                print('🤔 Started thinking...');
              }
              controller.add(thinking);
            }

            if (hasContent && hasStartedThinking && !hasFinishedThinking) {
              controller.add('...done thinking.');
              hasFinishedThinking = true;
              print('✅ Finished thinking, starting response');
            }

            if (hasContent) {
              // Emit content immediately without buffering
              controller.add(content);
            }

            if (done == true) {
              print('✅ Stream completed');
              _cleanup();
            }
          } catch (e) {
            print('⚠️ Error parsing JSON line: $e');
            print('   Line content: $line');
          }
        },
        onError: (error) {
          print('❌ Stream error: $error');
          final controller = _activeController;
          if (controller != null && !controller.isClosed) {
            if (error is! http.ClientException ||
                !error.message.contains('Connection closed')) {
              controller.addError(error);
            }
          }
          _cleanup();
        },
        onDone: () {
          print('✅ Stream done');
          _cleanup();
        },
        cancelOnError: false,
      );

      yield* _activeController!.stream;

    } on http.ClientException catch (e) {
      print('❌ Client error: ${e.message}');
      if (!e.message.contains('Connection closed')) {
        yield 'Error: Connection failed - ${e.message}';
      }
    } on TimeoutException catch (e) {
      print('❌ Timeout: ${e.message}');
      yield 'Error: Request timed out';
    } on FormatException catch (e) {
      print('❌ Format error: $e');
      yield 'Error: Invalid response format';
    } catch (e) {
      print('❌ Error in generateResponse: $e');
      yield 'Error: $e';
    } finally {
      _cleanup();
      print('🧹 Cleanup completed');
    }
  }

  Future<List<String>> _encodeImages(List<String> imagePaths) async {
    final encodedImages = <String>[];

    for (final imagePath in imagePaths) {
      try {
        final file = File(imagePath);
        if (await file.exists()) {
          final extension = imagePath.toLowerCase().substring(imagePath.lastIndexOf('.'));
          final imageExtensions = ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'];

          if (imageExtensions.contains(extension)) {
            final bytes = await file.readAsBytes();
            final base64Image = base64Encode(bytes);
            encodedImages.add(base64Image);
            debugPrint('📷 Encoded image: ${imagePath.split('/').last}');
          } else {
            debugPrint('⚠️ Skipping non-image file: $imagePath');
          }
        } else {
          debugPrint('⚠️ Image file not found: $imagePath');
        }
      } catch (e) {
        debugPrint('❌ Error encoding image $imagePath: $e');
      }
    }

    return encodedImages;
  }

  bool isVisionModel(String modelName) {
    final visionModels = [
      'llava',
      'bakllava',
      'llama3.2-vision',
      'minicpm-v',
      'moondream',
    ];
    return visionModels.any((vm) => modelName.toLowerCase().contains(vm));
  }

  Future<String> processDocument(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        throw Exception('File not found: $filePath');
      }

      final extension = filePath.toLowerCase().substring(filePath.lastIndexOf('.'));

      if (extension == '.txt' || extension == '.md') {
        final content = await file.readAsString();
        return content;
      }

      if (extension == '.pdf') {
        final bytes = await file.readAsBytes();
        final PdfDocument document = PdfDocument(inputBytes: bytes);
        final PdfTextExtractor extractor = PdfTextExtractor(document);
        final String text = extractor.extractText();
        document.dispose();
        return text;
      }

      if (extension == '.docx') {
        final bytes = await file.readAsBytes();
        final text = docxToText(bytes);
        return text;
      }

      debugPrint('⚠️ Unsupported document format: $extension');
      return '[Unsupported format: ${filePath.split('/').last}]';

    } catch (e) {
      debugPrint('❌ Error processing document: $e');
      return '[Error reading document: ${filePath.split('/').last}]';
    }
  }

  void _cleanup() {
    final key = 'cleanup_${DateTime.now().millisecondsSinceEpoch}';
    if (_cleanupLock.isNotEmpty) return;
    _cleanupLock[key] = true;

    try {
      _isGenerating = false;
      _activeSubscription?.cancel();
      _activeSubscription = null;

      if (_activeController?.isClosed == false) {
        _activeController!.close();
      }
      _activeController = null;

      _activeClient?.close();
      _activeClient = null;
    } finally {
      _cleanupLock.clear();
    }
  }

  Future<List<String>> fetchAvailableModels({
    Duration timeout = const Duration(seconds: 10),
  }) async {
    try {
      final url = Uri.parse('$_baseUrl/api/tags');
      final response = await http.get(url).timeout(timeout);

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body) as Map<String, dynamic>;
        final models = (json['models'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>();

        if (models == null) return [];

        return models
            .map((model) => model['name'] as String?)
            .whereType<String>()
            .where((name) => name.isNotEmpty)
            .toList();
      } else {
        print('⚠️ Failed to fetch models: ${response.statusCode}');
        return [];
      }
    } on TimeoutException {
      print('⚠️ Model fetch timed out');
      return [];
    } on http.ClientException catch (e) {
      print('⚠️ Connection error fetching models: ${e.message}');
      return [];
    } catch (e) {
      print('⚠️ Error fetching models: $e');
      return [];
    }
  }

  void dispose() {
    cancelGeneration();
  }
}