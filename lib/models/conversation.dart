import 'chat_message.dart';

/// Represents a complete conversation with multiple messages
/// Each conversation has a title, list of messages, and creation timestamp
class Conversation {
  /// Display title for the conversation (usually derived from first message)
  String title;

  /// All messages in this conversation (user and AI messages)
  List<ChatMessage> messages;

  /// When this conversation was created
  DateTime timestamp;

  Conversation({
    required this.title,
    required this.messages,
    required this.timestamp,
  });

  /// Converts the conversation to a JSON map for storage
  Map<String, dynamic> toJson() => {
    'title': title,
    'messages': messages.map((m) => m.toJson()).toList(),
    'timestamp': timestamp.toIso8601String(),
  };

  /// Creates a Conversation from a JSON map
  factory Conversation.fromJson(Map<String, dynamic> json) => Conversation(
    title: json['title'] as String,
    messages: (json['messages'] as List)
        .map((m) => ChatMessage.fromJson(m as Map<String, dynamic>))
        .toList(),
    timestamp: DateTime.parse(json['timestamp'] as String),
  );

  /// Creates a copy of this conversation with optional field replacements
  Conversation copyWith({
    String? title,
    List<ChatMessage>? messages,
    DateTime? timestamp,
  }) {
    return Conversation(
      title: title ?? this.title,
      messages: messages ?? List.from(this.messages),
      timestamp: timestamp ?? this.timestamp,
    );
  }

  /// Returns the number of messages in this conversation
  int get messageCount => messages.length;

  /// Returns true if this conversation has no messages
  bool get isEmpty => messages.isEmpty;

  /// Returns true if this conversation has messages
  bool get isNotEmpty => messages.isNotEmpty;

  /// Gets the last message in the conversation, or null if empty
  ChatMessage? get lastMessage => messages.isEmpty ? null : messages.last;

  /// Gets the first message in the conversation, or null if empty
  ChatMessage? get firstMessage => messages.isEmpty ? null : messages.first;

  /// Adds a new message to this conversation
  void addMessage(ChatMessage message) {
    messages.add(message);
  }

  /// Removes a message at the specified index
  void removeMessageAt(int index) {
    if (index >= 0 && index < messages.length) {
      messages.removeAt(index);
    }
  }

  /// Removes all messages from the specified index onwards
  void removeMessagesFrom(int index) {
    if (index >= 0 && index < messages.length) {
      messages.removeRange(index, messages.length);
    }
  }

  /// Clears all messages from the conversation
  void clearMessages() {
    messages.clear();
  }

  /// Gets all user messages in this conversation
  List<ChatMessage> get userMessages =>
      messages.where((m) => m.isUser).toList();

  /// Gets all AI messages in this conversation
  List<ChatMessage> get aiMessages =>
      messages.where((m) => !m.isUser).toList();

  /// Returns the total character count of all messages
  int get totalCharacterCount =>
      messages.fold(0, (sum, msg) => sum + msg.text.length);

  @override
  String toString() {
    return 'Conversation(title: $title, messageCount: $messageCount, timestamp: $timestamp)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Conversation &&
        other.title == title &&
        other.timestamp == timestamp &&
        _listEquals(other.messages, messages);
  }

  @override
  int get hashCode => Object.hash(title, timestamp, messages);

  /// Helper method to compare lists
  bool _listEquals(List a, List b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}