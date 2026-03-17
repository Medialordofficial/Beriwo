import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import '../services/chat_service.dart';
import '../widgets/chat_input.dart';
import '../widgets/message_bubble.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({super.key});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _scrollController = ScrollController();

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthService>();
    final chat = context.watch<ChatService>();
    final theme = Theme.of(context);

    // Auto-scroll when messages change
    if (chat.messages.isNotEmpty) {
      _scrollToBottom();
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beriwo'),
        centerTitle: true,
        actions: [
          if (chat.messages.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              onPressed: () => chat.clearChat(),
              tooltip: 'Clear chat',
            ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'logout') auth.logout();
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                enabled: false,
                child: Text(
                  auth.user?.email ?? '',
                  style: theme.textTheme.bodySmall,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'logout',
                child: Text('Sign out'),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: CircleAvatar(
                radius: 16,
                backgroundImage: auth.user?.pictureUrl != null
                    ? NetworkImage(auth.user!.pictureUrl.toString())
                    : null,
                child: auth.user?.pictureUrl == null
                    ? const Icon(Icons.person, size: 18)
                    : null,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: chat.messages.isEmpty
                ? _buildEmptyState(theme)
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    itemCount: chat.messages.length +
                        (chat.sending ? 1 : 0) +
                        (chat.pendingInterrupt != null ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index < chat.messages.length) {
                        return MessageBubble(message: chat.messages[index]);
                      }
                      if (chat.pendingInterrupt != null &&
                          index == chat.messages.length) {
                        return _buildConnectButton(auth, chat);
                      }
                      return _buildTypingIndicator(theme);
                    },
                  ),
          ),
          ChatInput(
            enabled: !chat.sending,
            onSend: (text) {
              if (auth.refreshToken != null) {
                chat.send(text, auth.refreshToken!);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.chat_bubble_outline_rounded,
              size: 64,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              'Beriwo',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your Google services assistant.\nAsk about emails, calendar, or files.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                _suggestionChip('Show my recent emails'),
                _suggestionChip("What's on my calendar today?"),
                _suggestionChip('Find files in Drive'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChip(String text) {
    final auth = context.read<AuthService>();
    final chat = context.read<ChatService>();

    return ActionChip(
      label: Text(text),
      onPressed: () {
        if (auth.refreshToken != null) {
          chat.send(text, auth.refreshToken!);
        }
      },
    );
  }

  Widget _buildConnectButton(AuthService auth, ChatService chat) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ElevatedButton.icon(
        onPressed: () {
          if (auth.refreshToken != null) {
            chat.resumeAfterAuth(auth.refreshToken!);
          }
        },
        icon: const Icon(Icons.link_rounded),
        label: const Text('Connect Google Account'),
      ),
    );
  }

  Widget _buildTypingIndicator(ThemeData theme) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
          ),
        ),
        child: SizedBox(
          width: 40,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(3, (i) {
              return TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: Duration(milliseconds: 600 + i * 200),
                builder: (_, value, child) => Opacity(
                  opacity: 0.3 + 0.7 * value,
                  child: child,
                ),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.onSurfaceVariant,
                    shape: BoxShape.circle,
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
