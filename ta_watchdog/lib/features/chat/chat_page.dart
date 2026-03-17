import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
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
    // A slight delay to allow the ListView to build the new item
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

    final chatState = ref.watch(chatProvider);
    final messages = chatState.messages;
    final isGenerating = chatState.isLoading;

    return Column(
      children: [
        Expanded(
          child: ListView.builder(
            controller: _scrollController,
            padding: const EdgeInsets.all(16),
            itemCount: messages.length,
            itemBuilder: (context, index) {
              final msg = messages[index];
              return _buildChatBubble(msg);
            },
          ),
        ),
        _buildInputArea(isGenerating),
      ],
    );
  }

  @override
  void dispose() {
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Widget _buildChatBubble(ChatMessage msg) {
    final isUser = msg.isUser;
    final isLoadingMsg = msg.isLoading;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        decoration: BoxDecoration(
          color: isUser ? Colors.blueGrey : Colors.grey[200],
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
                crossAxisAlignment:
                    isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                children: [
                  MarkdownBody(
                    data: msg.text,
                    styleSheet: MarkdownStyleSheet(
                      p: TextStyle(
                        color: msg.isError
                            ? Colors.redAccent
                            : (isUser ? Colors.white : Colors.black87),
                      ),
                      code: TextStyle(
                        backgroundColor:
                            isUser ? Colors.blueGrey[700] : Colors.grey[300],
                        color: isUser ? Colors.white : Colors.black87,
                      ),
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
                          color: isUser ? Colors.white : Colors.blueGrey[700],
                          decoration: TextDecoration.underline,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }

  Widget _buildInputArea(bool isGenerating) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, -1))],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _textController,
                enabled: !isGenerating,
                decoration: InputDecoration(
                  hintText: 'Ask your WatchDog...',
                  hintStyle: TextStyle(color: Colors.grey[700]),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: Colors.grey[200],
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
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
