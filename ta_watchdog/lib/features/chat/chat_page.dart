import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'chat_provider.dart';

class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({super.key});

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends ConsumerState<ChatPage> {
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  void _sendMessage() {
    final text = _textController.text.trim();
    if (text.isNotEmpty && !ref.read(chatProvider).isLoading) {
      ref.read(chatProvider.notifier).sendMessage(text);
      _textController.clear();
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<ChatState>(chatProvider, (prev, next) {
      if ((prev?.messages.length ?? 0) != next.messages.length) {
        _scrollToBottom();
      }
    });

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;

    return Column(
      children: [
        Expanded(
          child: RefreshIndicator(
            onRefresh: () async {
              await ref.read(chatProvider.notifier).reloadHistory();
              if (mounted) {
                _scrollToBottom();
              }
            },
            child: ListView.builder(
              controller: _scrollController,
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              itemCount: messages.isEmpty ? 1 : messages.length,
              itemBuilder: (context, index) {
                if (messages.isEmpty) {
                  return const SizedBox(
                    height: 300,
                    child: Center(child: Text('아래로 당겨 대화를 새로고침하세요.')),
                  );
                }
                return _buildChatBubble(messages[index], isDark);
              },
            ),
          ),
        ),
        _buildInputArea(chatState.isLoading, isDark),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildChatBubble(ChatMessage msg, bool isDark) {
    final isUser = msg.isUser;
    final isLoadingMsg = msg.isLoading;
    final bubbleColor = isUser
        ? (isDark ? const Color(0xFF2D3C5A) : Colors.blueGrey)
        : (isDark ? const Color(0xFF1A2742) : Colors.grey[200]!);
    final textColor = msg.isError
        ? Colors.redAccent
        : (isDark ? Colors.white : (isUser ? Colors.white : Colors.black87));

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onLongPress: isLoadingMsg
            ? null
            : () async {
                await Clipboard.setData(ClipboardData(text: msg.text));
                if (!mounted) return;
                ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('메시지를 복사했습니다.')));
              },
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.all(12),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: bubbleColor,
            borderRadius: BorderRadius.circular(16).copyWith(
              bottomLeft: isUser ? const Radius.circular(16) : Radius.zero,
              bottomRight: isUser ? Radius.zero : const Radius.circular(16),
            ),
          ),
          child: isLoadingMsg
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Column(
                  crossAxisAlignment: isUser
                      ? CrossAxisAlignment.end
                      : CrossAxisAlignment.start,
                  children: [
                    MarkdownBody(
                      data: msg.text,
                      styleSheet: MarkdownStyleSheet(
                        p: TextStyle(color: textColor),
                        code: TextStyle(
                          backgroundColor: isDark
                              ? const Color(0xFF314366)
                              : (isUser
                                    ? Colors.blueGrey[700]
                                    : Colors.grey[300]),
                          color: textColor,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      DateFormat('MM/dd HH:mm').format(msg.createdAt),
                      style: TextStyle(
                        color: (isDark ? Colors.white70 : Colors.black54),
                        fontSize: 11,
                      ),
                    ),
                    if (msg.canRetry && msg.retryQuery != null) ...[
                      const SizedBox(height: 6),
                      GestureDetector(
                        onTap: () => ref
                            .read(chatProvider.notifier)
                            .retryMessage(msg.retryQuery!),
                        child: Text(
                          'Retry (5 min)',
                          style: TextStyle(
                            color: isDark
                                ? Colors.lightBlue[200]
                                : (isUser
                                      ? Colors.white
                                      : Colors.blueGrey[700]),
                            decoration: TextDecoration.underline,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }

  Widget _buildInputArea(bool isGenerating, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -1),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !isGenerating,
                style: TextStyle(color: isDark ? Colors.white : Colors.black87),
                decoration: InputDecoration(
                  hintText: 'Ask your WatchDog...',
                  hintStyle: TextStyle(
                    color: isDark ? Colors.white60 : Colors.grey[700],
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: isDark
                      ? const Color(0xFF1A2742)
                      : Colors.grey[200],
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 10,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              decoration: const BoxDecoration(
                color: Colors.blueGrey,
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.send, color: Colors.white),
                onPressed: isGenerating ? null : _sendMessage,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
