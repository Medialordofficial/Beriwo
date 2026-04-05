import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import '../models/chat_message.dart';

class MessageBubble extends StatelessWidget {
  final ChatMessage message;

  const MessageBubble({super.key, required this.message});

  static const _toolLabels = {
    'list_emails': ('Gmail', Icons.email_outlined, Color(0xFFEF4444)),
    'read_email': ('Gmail', Icons.email_outlined, Color(0xFFEF4444)),
    'list_upcoming_events': (
      'Calendar',
      Icons.calendar_today_outlined,
      Color(0xFF3B82F6),
    ),
    'create_event': (
      'Calendar',
      Icons.event_available_outlined,
      Color(0xFF3B82F6),
    ),
    'list_drive_files': ('Drive', Icons.folder_outlined, Color(0xFF10B981)),
    'read_drive_file': ('Drive', Icons.description_outlined, Color(0xFF10B981)),
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.isUser;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth > 720;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            constraints: BoxConstraints(
              maxWidth: isWide ? 540 : screenWidth * 0.82,
            ),
            margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 20),
            child: Column(
              crossAxisAlignment: isUser
                  ? CrossAxisAlignment.end
                  : CrossAxisAlignment.start,
              children: [
                // Tool usage badges
                if (!isUser && message.toolsUsed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _buildToolBadges(theme),
                    ),
                  ),
                // Message bubble
                Container(
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                    horizontal: 18,
                  ),
                  decoration: BoxDecoration(
                    gradient: isUser
                        ? const LinearGradient(
                            colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          )
                        : null,
                    color: isUser ? null : const Color(0xFFFFFFFF),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(20),
                      topRight: const Radius.circular(20),
                      bottomLeft: Radius.circular(isUser ? 20 : 6),
                      bottomRight: Radius.circular(isUser ? 6 : 20),
                    ),
                    border: isUser
                        ? null
                        : Border.all(color: const Color(0xFFE4E4E7), width: 1),
                    boxShadow: [
                      if (isUser)
                        BoxShadow(
                          color: const Color(
                            0xFF8B5CF6,
                          ).withValues(alpha: 0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                    ],
                  ),
                  child: isUser
                      ? Text(
                          message.text,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14.5,
                            height: 1.5,
                          ),
                        )
                      : MarkdownBody(
                          data: message.text,
                          selectable: true,
                          styleSheet: MarkdownStyleSheet.fromTheme(theme)
                              .copyWith(
                                p: const TextStyle(
                                  color: Color(0xFF3F3F46),
                                  fontSize: 14.5,
                                  height: 1.6,
                                ),
                                code: TextStyle(
                                  backgroundColor: const Color(0xFFF4F4F5),
                                  color: const Color(0xFF8B5CF6),
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                                codeblockDecoration: BoxDecoration(
                                  color: const Color(0xFFF4F4F5),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: const Color(0xFFE4E4E7),
                                  ),
                                ),
                              ),
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildToolBadges(ThemeData theme) {
    final seen = <String>{};
    final badges = <Widget>[];

    for (final tool in message.toolsUsed) {
      final info = _toolLabels[tool];
      if (info == null) continue;
      final (label, icon, color) = info;
      if (seen.contains(label)) continue;
      seen.add(label);

      badges.add(
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.25), width: 1),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: color),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.3,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return badges;
  }
}
