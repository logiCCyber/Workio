class ChatState {
  ChatState._();
  static String? activeThreadId;
  static bool isThreadOpen(String threadId) {
    return activeThreadId == threadId;
  }
}