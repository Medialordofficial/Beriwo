import 'package:flutter/material.dart';

class ChatInput extends StatefulWidget {
  final Function(String) onSend;
  final bool enabled;

  const ChatInput({super.key, required this.onSend, this.enabled = true});

  @override
  State<ChatInput> createState() => _ChatInputState();
}

class _ChatInputState extends State<ChatInput> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  bool _hasText = false;

  void _handleSend() {
    final text = _controller.text.trim();
    if (text.isEmpty || !widget.enabled) return;
    widget.onSend(text);
    _controller.clear();
    setState(() => _hasText = false);
    _focusNode.requestFocus();
  }

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final has = _controller.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Container(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFFFFFFFF),
              borderRadius: BorderRadius.circular(28),
              border: Border.all(
                color: _focusNode.hasFocus
                    ? const Color(0xFF8B5CF6).withValues(alpha: 0.4)
                    : const Color(0xFFE4E4E7),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 20,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Focus(
                    onFocusChange: (_) => setState(() {}),
                    child: TextField(
                      controller: _controller,
                      focusNode: _focusNode,
                      enabled: widget.enabled,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _handleSend(),
                      maxLines: 5,
                      minLines: 1,
                      style: const TextStyle(
                        color: Color(0xFF18181B),
                        fontSize: 15,
                      ),
                      decoration: InputDecoration(
                        hintText: 'Ask Beriwo anything...',
                        hintStyle: TextStyle(
                          color: const Color(0xFFA1A1AA).withValues(alpha: 0.6),
                          fontSize: 15,
                        ),
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.fromLTRB(
                          20,
                          16,
                          8,
                          16,
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 8, bottom: 8),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      gradient: _hasText && widget.enabled
                          ? const LinearGradient(
                              colors: [Color(0xFF8B5CF6), Color(0xFF6D28D9)],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            )
                          : null,
                      color: !_hasText || !widget.enabled
                          ? const Color(0xFFE4E4E7)
                          : null,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(20),
                        onTap: widget.enabled && _hasText ? _handleSend : null,
                        child: Center(
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: _hasText && widget.enabled
                                ? Colors.white
                                : const Color(0xFF71717A),
                          ),
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
}
