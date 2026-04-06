import 'dart:convert';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'dart:html' as html;
import '../config.dart';
import '../models/chat_message.dart';

class ChatService extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  String? _conversationId;
  String? _currentPhase;
  bool _sending = false;
  Map<String, dynamic>? _pendingInterrupt;
  String? _lastInterruptedMessage;
  List<BlockedWrite>? _pendingConsent;
  Map<String, dynamic>? _pendingStepUp;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get sending => _sending;
  String? get conversationId => _conversationId;
  String? get currentPhase => _currentPhase;
  Map<String, dynamic>? get pendingInterrupt => _pendingInterrupt;
  List<BlockedWrite>? get pendingConsent => _pendingConsent;
  Map<String, dynamic>? get pendingStepUp => _pendingStepUp;

  /// Load any interrupted message saved before an OAuth redirect
  void loadPendingMessage() {
    final saved = html.window.localStorage['beriwo_pending_message'];
    if (saved != null && saved.isNotEmpty) {
      _lastInterruptedMessage = saved;
      debugPrint('Loaded pending interrupted message: $saved');
    }
  }

  void clearChat() {
    _messages.clear();
    _conversationId = null;
    _pendingInterrupt = null;
    _lastInterruptedMessage = null;
    _pendingConsent = null;
    _pendingStepUp = null;
    html.window.localStorage.remove('beriwo_pending_message');
    notifyListeners();
  }

  /// Dismiss the pending interrupt and show an error message instead.
  void clearInterrupt([String? errorMessage]) {
    _pendingInterrupt = null;
    _lastInterruptedMessage = null;
    _pendingConsent = null;
    _pendingStepUp = null;
    html.window.localStorage.remove('beriwo_pending_message');
    if (errorMessage != null) {
      _addBotMessage(errorMessage);
    }
    notifyListeners();
  }

  /// Clear the step-up authentication requirement (after successful re-auth).
  void clearStepUp() {
    _pendingStepUp = null;
    notifyListeners();
  }

  Future<void> send(
    String text,
    String refreshToken, {
    String? accessToken,
    bool skipUserMessage = false,
    List<String>? approvedWrites,
  }) async {
    if (text.trim().isEmpty) return;

    if (!skipUserMessage) {
      _messages.add(
        ChatMessage(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          text: text,
          isUser: true,
        ),
      );
    }
    _sending = true;
    _pendingInterrupt = null;
    notifyListeners();

    debugPrint(
      'send: conversationId=$_conversationId, '
      'hasRefresh=${refreshToken.isNotEmpty}, '
      'refreshToken=${refreshToken.isNotEmpty ? '${refreshToken.substring(0, 8)}...' : 'EMPTY'}, '
      'hasAccess=${accessToken != null}',
    );

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/chat'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'message': text,
          'conversationId': _conversationId,
          'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
          'accessToken': accessToken,
          'approvedWrites': ?approvedWrites,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint('send: failed ${response.statusCode}: ${response.body}');
        final statusMsg = response.statusCode == 401
            ? 'Your session has expired. Please sign out and back in.'
            : response.statusCode >= 500
            ? 'The server is temporarily unavailable. Please try again in a moment.'
            : 'Something went wrong (${response.statusCode}). Please try again.';
        _addBotMessage(statusMsg);
        return;
      }

      final data = jsonDecode(response.body);
      debugPrint('send: full response body: ${response.body}');
      // Only update conversationId if server returns a non-null value
      // — prevents losing conversation context if server omits it
      if (data['conversationId'] != null) {
        _conversationId = data['conversationId'];
      }
      debugPrint('send: response conversationId=$_conversationId');

      if (data['stepUpRequired'] != null) {
        _pendingStepUp = data['stepUpRequired'] as Map<String, dynamic>;
        _lastInterruptedMessage = text;
        html.window.localStorage['beriwo_pending_message'] = text;

        final tools =
            (data['stepUpRequired']['tools'] as List?)?.cast<String>() ?? [];
        final toolLabels = tools
            .map((t) {
              switch (t) {
                case 'send_email':
                  return 'Send email';
                case 'reply_to_email':
                  return 'Reply to email';
                case 'delete_calendar_event':
                  return 'Delete calendar event';
                default:
                  return t;
              }
            })
            .join(', ');

        _addBotMessage(
          'This action requires recent authentication. '
          'Please verify your identity to proceed with: $toolLabels.',
        );
      } else if (data['interrupt'] != null) {
        _pendingInterrupt = data['interrupt'];
        _lastInterruptedMessage = text;
        // Persist so it survives the Google OAuth redirect
        html.window.localStorage['beriwo_pending_message'] = text;

        // Include execution steps from the planning phase if available
        final planSteps = _parseExecutionSteps(data);
        final phases = _parsePhases(data);

        _addBotMessage(
          'I need access to your Google account to do that. Please grant access below.',
          toolsUsed: [],
          executionSteps: planSteps,
          phases: phases,
        );
      } else {
        // Parse the new 3-phase response
        final reply = data['reply'] ?? data['response'] ?? data['message'];
        final tools = (data['toolsUsed'] as List?)?.cast<String>() ?? [];
        final execSteps = _parseExecutionSteps(data);
        final phases = _parsePhases(data);
        final blockedWrites = _parseBlockedWrites(data);

        if (blockedWrites.isNotEmpty) {
          _pendingConsent = blockedWrites;
        }

        if (reply != null && reply.toString().trim().isNotEmpty) {
          _addBotMessage(
            reply.toString(),
            toolsUsed: tools,
            executionSteps: execSteps,
            phases: phases,
            blockedWrites: blockedWrites,
          );
        } else {
          debugPrint('send: reply was null/empty, keys: ${data.keys.toList()}');
          _addBotMessage(
            'I received an empty response. Please try rephrasing your question.',
          );
        }
      }
    } catch (e) {
      debugPrint('Chat error: $e');
      _addBotMessage('Connection error. Check your network and try again.');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Stream a message to the agent with live phase updates via SSE.
  /// Falls back to regular [send] if streaming fails.
  Future<void> sendStreaming(
    String text,
    String refreshToken, {
    String? accessToken,
    List<String>? approvedWrites,
  }) async {
    if (text.trim().isEmpty) return;

    _messages.add(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: true,
      ),
    );
    _sending = true;
    _currentPhase = 'planning';
    _pendingInterrupt = null;
    // Save the message text NOW so retryAfterAuth can find it after an interrupt
    _lastInterruptedMessage = text;
    html.window.localStorage['beriwo_pending_message'] = text;
    notifyListeners();

    // Add placeholder bot message that we'll update as events arrive
    final botId = (DateTime.now().millisecondsSinceEpoch + 1).toString();
    _messages.add(
      ChatMessage(
        id: botId,
        text: '',
        isUser: false,
        phases: const AgentPhases(
          planned: false,
          executed: false,
          synthesized: false,
        ),
      ),
    );
    notifyListeners();

    final completer = Completer<void>();
    String sseBuffer = '';

    void processSSE(String chunk) {
      sseBuffer += chunk;
      while (true) {
        final idx = sseBuffer.indexOf('\n\n');
        if (idx == -1) break;
        final block = sseBuffer.substring(0, idx);
        sseBuffer = sseBuffer.substring(idx + 2);

        String? eventName;
        String? data;
        for (final line in block.split('\n')) {
          if (line.startsWith('event: ')) eventName = line.substring(7);
          if (line.startsWith('data: ')) data = line.substring(6);
        }
        if (eventName == null || data == null) continue;

        try {
          final payload = jsonDecode(data) as Map<String, dynamic>;
          _handleStreamEvent(eventName, payload, botId);
        } catch (e) {
          debugPrint('SSE parse error: $e');
        }
      }
    }

    try {
      final xhr = html.HttpRequest();
      xhr.open('POST', '$apiBaseUrl/chat/stream');
      xhr.setRequestHeader('Content-Type', 'application/json');
      if (accessToken != null) {
        xhr.setRequestHeader('Authorization', 'Bearer $accessToken');
      }

      int lastProcessed = 0;

      xhr.onProgress.listen((_) {
        final resp = xhr.responseText ?? '';
        if (lastProcessed < resp.length) {
          processSSE(resp.substring(lastProcessed));
          lastProcessed = resp.length;
        }
      });

      xhr.onLoadEnd.listen((_) {
        final resp = xhr.responseText ?? '';
        if (lastProcessed < resp.length) {
          processSSE(resp.substring(lastProcessed));
        }
        if (!completer.isCompleted) completer.complete();
      });

      xhr.onError.listen((_) {
        if (!completer.isCompleted) completer.complete();
      });

      xhr.send(
        jsonEncode({
          'message': text,
          'conversationId': _conversationId,
          'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
          'accessToken': accessToken,
          'approvedWrites': ?approvedWrites,
        }),
      );

      await completer.future;

      // If streaming produced no response, fall back to regular send
      final botIdx = _messages.indexWhere((m) => m.id == botId);
      if (botIdx >= 0 && _messages[botIdx].text.isEmpty) {
        _messages.removeAt(botIdx);
        _sending = false;
        _currentPhase = null;
        notifyListeners();
        await send(
          text,
          refreshToken,
          accessToken: accessToken,
          skipUserMessage: true,
        );
        return;
      }
    } catch (e) {
      debugPrint('Streaming error: $e, falling back to regular send');
      final botIdx = _messages.indexWhere((m) => m.id == botId);
      if (botIdx >= 0 && _messages[botIdx].text.isEmpty) {
        _messages.removeAt(botIdx);
      }
      _sending = false;
      _currentPhase = null;
      notifyListeners();
      await send(
        text,
        refreshToken,
        accessToken: accessToken,
        skipUserMessage: true,
      );
      return;
    } finally {
      _sending = false;
      _currentPhase = null;
      notifyListeners();
    }
  }

  void _handleStreamEvent(
    String event,
    Map<String, dynamic> payload,
    String botId,
  ) {
    final botIdx = _messages.indexWhere((m) => m.id == botId);
    if (botIdx < 0) return;

    switch (event) {
      case 'started':
        if (payload['conversationId'] != null) {
          _conversationId = payload['conversationId'];
        }
        break;

      case 'phase':
        final name = payload['name'] as String?;
        final status = payload['status'] as String?;
        if (name != null) _currentPhase = name;

        // Update phases on the bot message
        final current =
            _messages[botIdx].phases ??
            const AgentPhases(
              planned: false,
              executed: false,
              synthesized: false,
            );
        AgentPhases updated = current;
        if (name == 'planning' && status == 'done') {
          updated = AgentPhases(
            planned: true,
            executed: current.executed,
            synthesized: current.synthesized,
          );
        } else if (name == 'executing' && status == 'done') {
          updated = AgentPhases(
            planned: current.planned,
            executed: true,
            synthesized: current.synthesized,
          );
        } else if (name == 'synthesizing' && status == 'done') {
          updated = AgentPhases(
            planned: current.planned,
            executed: current.executed,
            synthesized: true,
          );
        }
        _messages[botIdx] = _messages[botIdx].copyWith(phases: updated);
        notifyListeners();
        break;

      case 'interrupt':
        _pendingInterrupt = payload;
        // DO NOT null _lastInterruptedMessage here — retryAfterAuth needs it
        // It was already saved in sendStreaming() before the SSE started
        _messages[botIdx] = _messages[botIdx].copyWith(
          text:
              'I need access to your Google account to do that. Please grant access below.',
        );
        notifyListeners();
        break;

      case 'step_up':
        _pendingStepUp = payload['stepUpRequired'] as Map<String, dynamic>?;
        final suTools =
            (_pendingStepUp?['tools'] as List?)?.cast<String>() ?? [];
        final suLabels = suTools
            .map((t) {
              switch (t) {
                case 'send_email':
                  return 'Send email';
                case 'reply_to_email':
                  return 'Reply to email';
                case 'delete_calendar_event':
                  return 'Delete calendar event';
                default:
                  return t;
              }
            })
            .join(', ');
        _messages[botIdx] = _messages[botIdx].copyWith(
          text:
              'This action requires recent authentication. '
              'Please verify your identity to proceed with: $suLabels.',
        );
        notifyListeners();
        break;

      case 'done':
        if (payload['conversationId'] != null) {
          _conversationId = payload['conversationId'];
        }
        final reply = payload['reply'] ?? '';
        final tools = (payload['toolsUsed'] as List?)?.cast<String>() ?? [];
        final steps =
            (payload['executionSteps'] as List?)
                ?.map((e) => ExecutionStep.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];
        final phases = payload['phases'] != null
            ? AgentPhases.fromJson(payload['phases'] as Map<String, dynamic>)
            : const AgentPhases(
                planned: true,
                executed: true,
                synthesized: true,
              );
        final blocked =
            (payload['blockedWrites'] as List?)
                ?.map((e) => BlockedWrite.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];

        if (blocked.isNotEmpty) _pendingConsent = blocked;

        // Success — clear the interrupted message since it's been answered
        _lastInterruptedMessage = null;
        html.window.localStorage.remove('beriwo_pending_message');

        _messages[botIdx] = _messages[botIdx].copyWith(
          text: reply.toString(),
          toolsUsed: tools,
          executionSteps: steps,
          phases: phases,
          blockedWrites: blocked,
        );
        notifyListeners();
        break;

      case 'error':
        _messages[botIdx] = _messages[botIdx].copyWith(
          text: 'Something went wrong. Please try again.',
        );
        notifyListeners();
        break;
    }
  }

  Future<void> resumeAfterAuth(
    String refreshToken, {
    String? accessToken,
    String? conversationId,
  }) async {
    // Set sending IMMEDIATELY so ChatScreen shows the resuming spinner
    // on the very first rebuild (prevents flash of empty state)
    _sending = true;
    _pendingInterrupt = null;
    notifyListeners();

    final convoId = conversationId ?? _conversationId;
    if (convoId == null) {
      debugPrint('resumeAfterAuth: convoId is null, aborting');
      _addBotMessage(
        'Could not resume — no conversation found. Please try your request again.',
      );
      _sending = false;
      notifyListeners();
      return;
    }

    // If resuming from a redirect (new page load), set the conversation ID
    _conversationId = convoId;

    debugPrint(
      'resumeAfterAuth: calling /conversations/$convoId/resume (hasRefresh=${refreshToken.isNotEmpty}, hasAccess=${accessToken != null})',
    );

    try {
      final response = await http
          .post(
            Uri.parse('$apiBaseUrl/conversations/$convoId/resume'),
            headers: {
              'Content-Type': 'application/json',
              if (accessToken != null) 'Authorization': 'Bearer $accessToken',
            },
            body: jsonEncode({
              'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
              'accessToken': accessToken,
            }),
          )
          .timeout(const Duration(seconds: 30));

      debugPrint(
        'resumeAfterAuth: status=${response.statusCode}, bodyLen=${response.body.length}',
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        debugPrint('resumeAfterAuth: full response body: ${response.body}');
        // Preserve conversationId from resume response
        if (data['conversationId'] != null) {
          _conversationId = data['conversationId'];
        }
        debugPrint('resumeAfterAuth: response conversationId=$_conversationId');

        if (data['interrupt'] != null) {
          _pendingInterrupt = data['interrupt'];
          _addBotMessage(
            'Google authorization is still needed. Please grant access below.',
          );
        } else {
          final reply = data['reply'] ?? data['response'] ?? data['message'];
          final tools = (data['toolsUsed'] as List?)?.cast<String>() ?? [];
          final execSteps = _parseExecutionSteps(data);
          final phases = _parsePhases(data);
          final blockedWrites = _parseBlockedWrites(data);

          if (blockedWrites.isNotEmpty) {
            _pendingConsent = blockedWrites;
          }

          if (reply != null && reply.toString().trim().isNotEmpty) {
            _addBotMessage(
              reply.toString(),
              toolsUsed: tools,
              executionSteps: execSteps,
              phases: phases,
              blockedWrites: blockedWrites,
            );
            _lastInterruptedMessage = null;
            html.window.localStorage.remove('beriwo_pending_message');
          } else if (_lastInterruptedMessage != null) {
            // Resume confirmed connection but didn't answer — auto-retry
            debugPrint(
              'resumeAfterAuth: no reply, auto-retrying: $_lastInterruptedMessage',
            );
            final retryMsg = _lastInterruptedMessage!;
            _lastInterruptedMessage = null;
            html.window.localStorage.remove('beriwo_pending_message');
            _sending = false;
            notifyListeners();
            await send(
              retryMsg,
              refreshToken,
              accessToken: accessToken,
              skipUserMessage: true,
            );
            return; // send() handles _sending = false
          } else {
            debugPrint(
              'resumeAfterAuth: reply was null/empty, keys: ${data.keys.toList()}',
            );
            _addBotMessage('Google account connected. Try your request again.');
          }
        }
      } else {
        debugPrint('Resume failed: ${response.statusCode} ${response.body}');
        _addBotMessage(
          'Something went wrong resuming (${response.statusCode}). Please try your request again.',
        );
      }
    } catch (e) {
      debugPrint('Resume error: $e');
      _addBotMessage('Connection error during resume. Please try again.');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  /// Retry the last interrupted message after Google auth popup completes.
  /// No page redirect happened, so all chat state is preserved.
  Future<void> retryAfterAuth(
    String refreshToken, {
    String? accessToken,
  }) async {
    final message = _lastInterruptedMessage;
    if (message == null || message.isEmpty || _conversationId == null) {
      _pendingInterrupt = null;
      notifyListeners();
      return;
    }

    _pendingInterrupt = null;
    _lastInterruptedMessage = null; // Clear immediately to prevent loops
    html.window.localStorage.remove('beriwo_pending_message');

    _sending = true;
    notifyListeners();

    debugPrint(
      'retryAfterAuth: convoId=$_conversationId, '
      'refreshToken=${refreshToken.isNotEmpty ? '${refreshToken.substring(0, 8)}...' : 'EMPTY'}, '
      'hasAccess=${accessToken != null}',
    );

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/conversations/$_conversationId/resume'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
          'accessToken': accessToken,
        }),
      );

      debugPrint('retryAfterAuth: status=${response.statusCode}');

      if (response.statusCode != 200) {
        debugPrint('retryAfterAuth: body=${response.body}');
        _addBotMessage(
          'Something went wrong after connecting Google (${response.statusCode}). '
          'Please try your request again.',
        );
        return;
      }

      final data = jsonDecode(response.body);
      debugPrint(
        'retryAfterAuth: keys=${data.keys.toList()}, hasInterrupt=${data['interrupt'] != null}',
      );

      if (data['interrupt'] != null) {
        // DO NOT re-set _pendingInterrupt — this prevents the endless loop.
        // The user already connected Google but Token Vault still can't resolve.
        // This is a config issue, not something the user can fix by clicking again.
        debugPrint(
          'retryAfterAuth: STILL interrupted after Google connect — likely Auth0 config issue',
        );
        _addBotMessage(
          'Google connection was authorized but the backend could not retrieve '
          'tokens. This usually means Token Vault or Connected Accounts needs '
          'to be enabled in the Auth0 dashboard. Please check the Auth0 '
          'configuration and try again.',
        );
      } else {
        final reply = data['reply'] ?? data['response'] ?? data['message'];
        final tools = (data['toolsUsed'] as List?)?.cast<String>() ?? [];
        final execSteps = _parseExecutionSteps(data);
        final phases = _parsePhases(data);
        if (reply != null && reply.toString().trim().isNotEmpty) {
          _addBotMessage(
            reply.toString(),
            toolsUsed: tools,
            executionSteps: execSteps,
            phases: phases,
          );
        } else {
          // No reply and no interrupt — try re-sending through /chat
          debugPrint('retryAfterAuth: empty reply, re-sending via /chat');
          _sending = false;
          notifyListeners();
          await send(
            message,
            refreshToken,
            accessToken: accessToken,
            skipUserMessage: true,
          );
          return;
        }
      }
    } catch (e) {
      debugPrint('retryAfterAuth error: $e');
      _addBotMessage('Connection error. Please try your request again.');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void _addBotMessage(
    String text, {
    List<String> toolsUsed = const [],
    List<ExecutionStep> executionSteps = const [],
    AgentPhases? phases,
    List<BlockedWrite> blockedWrites = const [],
  }) {
    _messages.add(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: false,
        toolsUsed: toolsUsed,
        executionSteps: executionSteps,
        phases: phases,
        blockedWrites: blockedWrites,
      ),
    );
  }

  List<ExecutionStep> _parseExecutionSteps(Map<String, dynamic> data) {
    final raw = data['executionSteps'] as List?;
    if (raw == null) return [];
    return raw
        .map((e) => ExecutionStep.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  AgentPhases? _parsePhases(Map<String, dynamic> data) {
    final raw = data['phases'] as Map<String, dynamic>?;
    if (raw == null) return null;
    return AgentPhases.fromJson(raw);
  }

  List<BlockedWrite> _parseBlockedWrites(Map<String, dynamic> data) {
    final raw = data['blockedWrites'] as List?;
    if (raw == null) return [];
    return raw
        .map((e) => BlockedWrite.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Approve blocked write operations and re-execute.
  Future<void> approveWrites(
    String refreshToken, {
    String? accessToken,
    required List<String> approvedTools,
  }) async {
    if (_conversationId == null || approvedTools.isEmpty) return;

    _pendingConsent = null;
    _sending = true;
    notifyListeners();

    debugPrint('approveWrites: tools=${approvedTools.join(", ")}');

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/conversations/$_conversationId/approve'),
        headers: {
          'Content-Type': 'application/json',
          if (accessToken != null) 'Authorization': 'Bearer $accessToken',
        },
        body: jsonEncode({
          'refreshToken': refreshToken.isNotEmpty ? refreshToken : null,
          'accessToken': accessToken,
          'approvedTools': approvedTools,
        }),
      );

      if (response.statusCode != 200) {
        debugPrint(
          'approveWrites: failed ${response.statusCode}: ${response.body}',
        );
        _addBotMessage('Failed to execute approved actions. Please try again.');
        return;
      }

      final data = jsonDecode(response.body);
      if (data['conversationId'] != null) {
        _conversationId = data['conversationId'];
      }

      if (data['interrupt'] != null) {
        _pendingInterrupt = data['interrupt'];
        _addBotMessage('Google authorization is still needed.');
        return;
      }

      final reply = data['reply'] ?? data['response'] ?? '';
      final tools = (data['toolsUsed'] as List?)?.cast<String>() ?? [];
      final execSteps = _parseExecutionSteps(data);
      final phases = _parsePhases(data);

      _addBotMessage(
        reply.toString(),
        toolsUsed: tools,
        executionSteps: execSteps,
        phases: phases,
      );
    } catch (e) {
      debugPrint('approveWrites error: $e');
      _addBotMessage('Connection error. Please try again.');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }
}
