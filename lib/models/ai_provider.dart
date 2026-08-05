enum AiProviderKind {
  ollama,
  openAiCompatible,
}

/// A connection profile for an AI inference server.
///
/// API keys intentionally stay in memory. The non-sensitive profile fields are
/// persisted so users only need to enter a secret again when they restart the
/// app, rather than leaving it in the general preferences database.
class AiProviderConfig {
  final AiProviderKind kind;
  final String name;
  final String endpoint;
  final String apiKey;

  const AiProviderConfig({
    required this.kind,
    required this.name,
    required this.endpoint,
    this.apiKey = '',
  });

  factory AiProviderConfig.ollama() => const AiProviderConfig(
        kind: AiProviderKind.ollama,
        name: 'Ollama',
        endpoint: 'http://localhost:11434',
      );

  factory AiProviderConfig.openAiCompatible() => const AiProviderConfig(
        kind: AiProviderKind.openAiCompatible,
        name: 'OpenAI-compatible',
        endpoint: 'https://api.openai.com/v1',
      );

  factory AiProviderConfig.fromPreferences(Map<String, dynamic> preferences) {
    final kindName = '${preferences['providerKind'] ?? 'ollama'}';
    final kind = AiProviderKind.values.firstWhere(
      (value) => value.name == kindName,
      orElse: () => AiProviderKind.ollama,
    );
    final fallback = kind == AiProviderKind.ollama
        ? AiProviderConfig.ollama()
        : AiProviderConfig.openAiCompatible();
    final storedName = '${preferences['providerName'] ?? ''}'.trim();
    final storedEndpoint = '${preferences['providerEndpoint'] ?? ''}'.trim();

    return AiProviderConfig(
      kind: kind,
      name: storedName.isEmpty ? fallback.name : storedName,
      endpoint: storedEndpoint.isEmpty ? fallback.endpoint : storedEndpoint,
    );
  }

  bool get needsApiKey => kind == AiProviderKind.openAiCompatible;

  String get displayName => name.trim().isEmpty
      ? (kind == AiProviderKind.ollama ? 'Ollama' : 'OpenAI-compatible')
      : name.trim();

  String get normalizedEndpoint {
    final trimmed = endpoint.trim().replaceFirst(RegExp(r'/+$'), '');
    final fallback = kind == AiProviderKind.ollama
        ? 'http://localhost:11434'
        : 'https://api.openai.com/v1';
    return trimmed.isEmpty ? fallback : trimmed;
  }

  String get modelEndpoint {
    if (kind == AiProviderKind.ollama) {
      return '$normalizedEndpoint/api/tags';
    }
    return normalizedEndpoint.endsWith('/v1')
        ? '$normalizedEndpoint/models'
        : '$normalizedEndpoint/v1/models';
  }

  String get chatEndpoint {
    if (kind == AiProviderKind.ollama) {
      return '$normalizedEndpoint/api/chat';
    }
    return normalizedEndpoint.endsWith('/v1')
        ? '$normalizedEndpoint/chat/completions'
        : '$normalizedEndpoint/v1/chat/completions';
  }

  AiProviderConfig copyWith({
    AiProviderKind? kind,
    String? name,
    String? endpoint,
    String? apiKey,
  }) {
    return AiProviderConfig(
      kind: kind ?? this.kind,
      name: name ?? this.name,
      endpoint: endpoint ?? this.endpoint,
      apiKey: apiKey ?? this.apiKey,
    );
  }

  Map<String, dynamic> toPreferenceValues() => {
        'providerKind': kind.name,
        'providerName': displayName,
        'providerEndpoint': normalizedEndpoint,
      };
}
