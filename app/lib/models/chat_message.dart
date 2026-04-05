/// A single execution step in the agent pipeline.
class ExecutionStep {
  final String tool;
  final String label;
  final String status; // pending, running, done, blocked, skipped
  final bool requiresConsent;
  final int? durationMs;
  final String? error;

  const ExecutionStep({
    required this.tool,
    required this.label,
    required this.status,
    this.requiresConsent = false,
    this.durationMs,
    this.error,
  });

  factory ExecutionStep.fromJson(Map<String, dynamic> json) {
    return ExecutionStep(
      tool: json['tool'] ?? '',
      label: json['label'] ?? json['tool'] ?? '',
      status: json['status'] ?? 'pending',
      requiresConsent: json['requiresConsent'] == true,
      durationMs: json['durationMs'] as int?,
      error: json['error'] as String?,
    );
  }
}

/// Which phases of the 3-phase pipeline completed.
class AgentPhases {
  final bool planned;
  final bool executed;
  final bool synthesized;

  const AgentPhases({
    this.planned = false,
    this.executed = false,
    this.synthesized = false,
  });

  factory AgentPhases.fromJson(Map<String, dynamic> json) {
    return AgentPhases(
      planned: json['planned'] == true,
      executed: json['executed'] == true,
      synthesized: json['synthesized'] == true,
    );
  }
}

/// A blocked write operation that needs user consent.
class BlockedWrite {
  final String tool;
  final String label;
  final String? purpose;

  const BlockedWrite({required this.tool, required this.label, this.purpose});

  factory BlockedWrite.fromJson(Map<String, dynamic> json) {
    return BlockedWrite(
      tool: json['tool'] ?? '',
      label: json['label'] ?? json['tool'] ?? '',
      purpose: json['purpose'] as String?,
    );
  }
}

class ChatMessage {
  final String id;
  final String text;
  final bool isUser;
  final DateTime timestamp;
  final List<String> toolsUsed;
  final List<ExecutionStep> executionSteps;
  final AgentPhases? phases;
  final List<BlockedWrite> blockedWrites;

  ChatMessage({
    required this.id,
    required this.text,
    required this.isUser,
    this.toolsUsed = const [],
    this.executionSteps = const [],
    this.phases,
    this.blockedWrites = const [],
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  ChatMessage copyWith({
    String? text,
    List<String>? toolsUsed,
    List<ExecutionStep>? executionSteps,
    AgentPhases? phases,
    List<BlockedWrite>? blockedWrites,
  }) {
    return ChatMessage(
      id: id,
      text: text ?? this.text,
      isUser: isUser,
      toolsUsed: toolsUsed ?? this.toolsUsed,
      executionSteps: executionSteps ?? this.executionSteps,
      phases: phases ?? this.phases,
      blockedWrites: blockedWrites ?? this.blockedWrites,
      timestamp: timestamp,
    );
  }

  factory ChatMessage.fromJson(Map<String, dynamic> json) {
    return ChatMessage(
      id: json['id'] ?? '',
      text: json['text'] ?? '',
      isUser: json['role'] == 'user',
      toolsUsed: (json['toolsUsed'] as List?)?.cast<String>() ?? [],
      executionSteps:
          (json['executionSteps'] as List?)
              ?.map((e) => ExecutionStep.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      phases: json['phases'] != null
          ? AgentPhases.fromJson(json['phases'] as Map<String, dynamic>)
          : null,
      blockedWrites:
          (json['blockedWrites'] as List?)
              ?.map((e) => BlockedWrite.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [],
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'])
          : DateTime.now(),
    );
  }
}
