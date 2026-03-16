import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/api_client.dart';

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isLoading;
  final bool isError;
  final bool canRetry;
  final String? retryQuery;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isLoading = false,
    this.isError = false,
    this.canRetry = false,
    this.retryQuery,
  });

  factory ChatMessage.loading() {
    return ChatMessage(text: '...', isUser: false, isLoading: true);
  }

  factory ChatMessage.timeoutError(String query) {
    return ChatMessage(
      text: '요청 시간이 초과되었습니다.',
      isUser: false,
      isError: true,
      canRetry: true,
      retryQuery: query,
    );
  }

  factory ChatMessage.error(String message) {
    return ChatMessage(
      text: message,
      isUser: false,
      isError: true,
    );
  }
}

class ChatState {
  final List<ChatMessage> messages;
  final bool isLoading;

  const ChatState({
    required this.messages,
    required this.isLoading,
  });

  factory ChatState.initial() => const ChatState(messages: [], isLoading: false);

  ChatState copyWith({
    List<ChatMessage>? messages,
    bool? isLoading,
  }) {
    return ChatState(
      messages: messages ?? this.messages,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

class ChatNotifier extends Notifier<ChatState> {
  @override
  ChatState build() => ChatState.initial();

  Future<void> sendMessage(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || state.isLoading) return;
    await _send(trimmed, addUser: true);
  }

  Future<void> retryMessage(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty || state.isLoading) return;
    await _send(
      trimmed,
      addUser: false,
      receiveTimeoutOverride: const Duration(minutes: 5),
    );
  }

  Future<void> _send(
    String query, {
    required bool addUser,
    Duration? receiveTimeoutOverride,
  }) async {
    final updated = [
      ...state.messages,
      if (addUser) ChatMessage(text: query, isUser: true),
      ChatMessage.loading(),
    ];
    state = state.copyWith(messages: updated, isLoading: true);

    try {
      final dio = ref.read(dioProvider);
      final response = await dio.post(
        '/api/chat/ask',
        data: {'query': query},
        options: receiveTimeoutOverride != null
            ? Options(receiveTimeout: receiveTimeoutOverride)
            : null,
      );

      String answer = 'No answer received.';
      final data = response.data;
      if (data is Map) {
        if (data['status'] == 'error') {
          answer = data['answer']?.toString() ?? 'Server error.';
        } else {
          answer = data['answer']?.toString() ?? answer;
        }
      }

      final newHistory = List<ChatMessage>.from(state.messages);
      if (newHistory.isNotEmpty && newHistory.last.isLoading) {
        newHistory.removeLast();
      }
      newHistory.add(ChatMessage(text: answer, isUser: false));
      state = state.copyWith(messages: newHistory, isLoading: false);
    } on DioException catch (e) {
      final newHistory = List<ChatMessage>.from(state.messages);
      if (newHistory.isNotEmpty && newHistory.last.isLoading) {
        newHistory.removeLast();
      }
      if (_isTimeout(e)) {
        newHistory.add(ChatMessage.timeoutError(query));
      } else {
        newHistory.add(ChatMessage.error('Error connecting to LLM: ${e.message}'));
      }
      state = state.copyWith(messages: newHistory, isLoading: false);
    } catch (e) {
      final newHistory = List<ChatMessage>.from(state.messages);
      if (newHistory.isNotEmpty && newHistory.last.isLoading) {
        newHistory.removeLast();
      }
      newHistory.add(ChatMessage.error('Error connecting to LLM: $e'));
      state = state.copyWith(messages: newHistory, isLoading: false);
    }
  }

  bool _isTimeout(DioException e) {
    return e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout;
  }
}

final chatProvider = NotifierProvider<ChatNotifier, ChatState>(() {
  return ChatNotifier();
});
