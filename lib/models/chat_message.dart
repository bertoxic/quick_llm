class ChatMessage {
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final String? thinkingText;
  final bool isThinking;
  final String? modelName;
  final List<String>? attachedFiles; // File paths for attached files
  final Map<String, dynamic>? details;

  ChatMessage({
    required this.text,
    required this.isUser,
    required this.timestamp,
    this.thinkingText,
    this.isThinking = false,
    this.modelName,
    this.attachedFiles,
    this.details,
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
      'details': details,
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
      details: json['details'] != null
          ? Map<String, dynamic>.from(json['details'] as Map)
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
    Map<String, dynamic>? details,
  }) {
    return ChatMessage(
      text: text ?? this.text,
      isUser: isUser ?? this.isUser,
      timestamp: timestamp ?? this.timestamp,
      thinkingText: thinkingText ?? this.thinkingText,
      isThinking: isThinking ?? this.isThinking,
      modelName: modelName ?? this.modelName,
      attachedFiles: attachedFiles ?? this.attachedFiles,
      details: details ?? this.details,
    );
  }

  int get estimatedTokenCount {
    final source =
        [text, thinkingText ?? ''].where((part) => part.isNotEmpty).join(' ');
    if (source.trim().isEmpty) return 0;
    return (source.trim().split(RegExp(r'\s+')).length * 1.35).ceil();
  }

  // Check if message has image attachments
  bool get hasImages {
    if (attachedFiles == null) return false;
    return attachedFiles!.any((path) {
      final ext = _extension(path);
      return ['.jpg', '.jpeg', '.png', '.gif', '.bmp', '.webp'].contains(ext);
    });
  }

  // Check if message has document attachments
  bool get hasDocuments {
    if (attachedFiles == null) return false;
    return attachedFiles!.any((path) {
      final ext = _extension(path);
      return [
        '.pdf',
        '.txt',
        '.doc',
        '.docx',
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
      ].contains(ext);
    });
  }

  static String _extension(String path) {
    final dotIndex = path.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == path.length - 1) return '';
    return path.substring(dotIndex).toLowerCase();
  }
}
