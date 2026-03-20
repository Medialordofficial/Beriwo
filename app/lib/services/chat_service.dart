import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';
import '../models/chat_message.dart';

class ChatService extends ChangeNotifier {
  final List<ChatMessage> _messages = [];
  String? _conversationId;
  bool _sending = false;
  Map<String, dynamic>? _pendingInterrupt;

  List<ChatMessage> get messages => List.unmodifiable(_messages);
  bool get sending => _sending;
  String? get conversationId => _conversationId;
  Map<String, dynamic>? get pendingInterrupt => _pendingInterrupt;

  void clearChat() {
    _messages.clear();
    _conversationId = null;
    _pendingInterrupt = null;
    notifyListeners();
  }

  Future<void> send(String text, String refreshToken) async {
    if (text.trim().isEmpty) return;

    _messages.add(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: true,
      ),
    );
    _sending = true;
    _pendingInterrupt = null;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/chat'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'message': text,
          'conversationId': _conversationId,
          'refreshToken': refreshToken,
        }),
      );

      if (response.statusCode != 200) {
        _addBotMessage('Something went wrong. Please try again.');
        return;
      }

      final data = jsonDecode(response.body);
      _conversationId = data['conversationId'];

      if (data['interrupt'] != null) {
        _pendingInterrupt = data['interrupt'];
        _addBotMessage(
          'I need access to your Google account to do that. Please connect your account.',
        );
      } else if (data['reply'] != null) {
        _addBotMessage(data['reply']);
      }
    } catch (e) {
      debugPrint('Chat error: $e');
      _addBotMessage('Connection error. Check your network and try again.');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<void> resumeAfterAuth(String refreshToken) async {
    if (_conversationId == null || _pendingInterrupt == null) return;

    _sending = true;
    notifyListeners();

    try {
      final response = await http.post(
        Uri.parse('$apiBaseUrl/conversations/$_conversationId/resume'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'refreshToken': refreshToken,
          'interruptData': _pendingInterrupt?['data'],
        }),
      );

      if (response.statusCode == 200) {
        _pendingInterrupt = null;
        _addBotMessage('Google account connected. Try your request again.');
      }
    } catch (e) {
      debugPrint('Resume error: $e');
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  void _addBotMessage(String text) {
    _messages.add(
      ChatMessage(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        text: text,
        isUser: false,
      ),
    );
  }
}
