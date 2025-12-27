class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? thinkingText;
  final bool isThinking;
  final String? modelName;
  final List<String>? attachedFiles; // File paths for attached files

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.thinkingText,
    this.isThinking = false,
    this.modelName,
    this.attachedFiles,
  });

  // Convert to JSON for storage
  Map<String, dynamic> toJson() {
    return {
      'text': text,
      'isUser': isUser,
      'timestamp': timestamp.toIso8601String(),
      'thinkingText': thinkingText,
      'isThinking': isThinking,
      'modelName': modelName,
      'attachedFiles': attachedFiles,
    };
  }

  // Create from JSON
  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      text: json['text'] as String,
      isUser: json['isUser'] as bool,
      timestamp: DateTime.parse(json['timestamp'] as String),
      thinkingText: json['thinkingText'] as String?,
      isThinking: json['isThinking'] as bool? ?? false,
      modelName: json['modelName'] as String?,
      attachedFiles: json['attachedFiles'] != null
          ? List<String>.from(json['attachedFiles'] as List)
          : null,
    );
  }

  // Create a copy with modified fields
  ChatMessage copyWith({
    String? text,
    bool? isUser,
    DateTime? timestamp,
    String? thinkingText,
    bool? isThinking,
    String? modelName,
    List<String>? attachedFiles,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      thinkingText: thinkingText ?? this.thinkingText,
      isThinking: isThinking ?? this.isThinking,
      modelName: modelName ?? this.modelName,
      attachedFiles: attachedFiles ?? this.attachedFiles,
    );
  }

  // Check if message has image attachments
  bool get hasImages {
    if (attachedFiles == null) return false;
    return attachedFiles!.any((path) {
      final ext = path.toLowerCase().substring(path.lastIndexOf('.'));
      return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext);
    });
  }

  // Check if message has document attachments
  bool get hasDocuments {
    if (attachedFiles == null) return false;
    return attachedFiles!.any((path) {
      final ext = path.toLowerCase().substring(path.lastIndexOf('.'));
      return ['.pdf', '.txt', '.doc', '.docx', '.md'].contains(ext);
    });
  }
}