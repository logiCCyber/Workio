import 'dart:ui';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:cross_file/cross_file.dart';
import '../services/message_service.dart';
import 'chat_image_viewer_screen.dart';
import 'package:url_launcher/url_launcher.dart';

class AdminChatScreen extends StatefulWidget {
  final String threadId;
  final String workerName;
  final String workerEmail;
  final String avatarUrl;
  final String workerAuthId;

  const AdminChatScreen({
    super.key,
    required this.threadId,
    required this.workerName,
    required this.workerEmail,
    required this.avatarUrl,
    required this.workerAuthId,
  });

  @override
  State<AdminChatScreen> createState() => _AdminChatScreenState();
}

enum _MessageAction {
  reply,
  copy,
  saveImage,
  shareImage,
  downloadFile,
  pin,
  edit,
  delete,
}

class _AdminChatScreenState extends State<AdminChatScreen> {
  final TextEditingController _textCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  DateTime _chatOpenedAt = DateTime.now().toUtc();

  String? _firstUnreadIncomingMessageId;
  bool _unreadBoundaryCaptured = false;

  Future<void> _showAttachSheet() async {
    if (_sending) return;

    await showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) {
        Widget attachItem({
          required IconData icon,
          required String title,
          required VoidCallback onTap,
          Color iconColor = Colors.white,
        }) {
          return Expanded(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(22),
                onTap: onTap,
                child: Ink(
                  height: 96,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Colors.white.withOpacity(0.06),
                        Colors.white.withOpacity(0.025),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.08),
                    ),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF31363E),
                              Color(0xFF232830),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Center(
                          child: Icon(
                            icon,
                            color: iconColor,
                            size: 20,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        title,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 13.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        }

        return SafeArea(
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF1B2028),
                  Color(0xFF12171E),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.34),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    attachItem(
                      icon: Icons.photo_camera_outlined,
                      title: 'Camera',
                      onTap: () async {
                        Navigator.pop(context);
                        await _sendImageFromCamera();
                      },
                    ),
                    const SizedBox(width: 10),
                    attachItem(
                      icon: Icons.photo_library_outlined,
                      title: 'Image',
                      onTap: () async {
                        Navigator.pop(context);
                        await _sendImageFromGallery();
                      },
                    ),
                    const SizedBox(width: 10),
                    attachItem(
                      icon: Icons.attach_file_rounded,
                      title: 'File',
                      onTap: () async {
                        Navigator.pop(context);
                        await _sendFile();
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  RealtimeChannel? _rtChannel;
  Timer? _typingTimer;

  bool _peerOnline = false;
  String _peerActivity = '';

  RealtimeChannel? _appPresenceChannel;
  final Set<String> _appOnlineIds = {};

  bool _sending = false;
  int _lastMessageCount = 0;
  Map<String, dynamic>? _replyToMessage;
  Map<String, dynamic>? _pinnedOverride;
  bool _usePinnedOverride = false;
  final Map<String, GlobalKey> _messageKeys = {};
  List<Map<String, dynamic>> _currentMessages = const [];

  @override
  void initState() {
    super.initState();
    _initRealtime();
    _initAppPresenceWatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToBottom();
    });
  }

  @override
  void dispose() {
    _typingTimer?.cancel();

    final channel = _rtChannel;
    _rtChannel = null;

    if (channel != null) {
      channel.untrack();
      Supabase.instance.client.removeChannel(channel);
    }

    final appCh = _appPresenceChannel;
    _appPresenceChannel = null;

    if (appCh != null) {
      appCh.untrack();
      Supabase.instance.client.removeChannel(appCh);
    }

    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _markReadSafe() async {
    try {
      await MessageService.markThreadRead(widget.threadId);
    } catch (_) {}
  }

  Future<void> _initRealtime() async {
    if (widget.threadId.trim().isEmpty) return;

    final supabase = Supabase.instance.client;
    final myId = supabase.auth.currentUser?.id;
    if (myId == null) return;

    _rtChannel = supabase.channel(
      'chat-thread:${widget.threadId}',
      opts: const RealtimeChannelConfig(
        private: true,
      ),
    );

    _rtChannel!
        .onPresenceSync((payload) {
      _refreshPeerPresence();
    })
        .onPresenceJoin((payload) {
      _refreshPeerPresence();
    })
        .onPresenceLeave((payload) {
      _refreshPeerPresence();
    })
        .onBroadcast(
      event: 'activity',
      callback: (payload) {
        final senderId = (payload['sender_id'] ?? '').toString();
        if (senderId == myId) return;

        if (!mounted) return;
        setState(() {
          final active = payload['active'] == true;
          _peerActivity = active ? (payload['kind'] ?? '').toString() : '';
        });
      },
    );

    _rtChannel!.subscribe((status, [error]) async {
      if (status == RealtimeSubscribeStatus.subscribed) {
        await _rtChannel!.track({
          'auth_user_id': myId,
          'role': 'admin',
          'online_at': DateTime.now().toIso8601String(),
        });
        _refreshPeerPresence();
      }
    });
  }

  PopupMenuItem<_MessageAction> _menuItem({
    required _MessageAction value,
    required IconData icon,
    required String text,
    Color iconColor = Colors.white70,
    Color textColor = Colors.white,
  }) {
    return PopupMenuItem<_MessageAction>(
      value: value,
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: textColor,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _refreshAppPresence() {
    final ids = <String>{};
    final state = _appPresenceChannel?.presenceState() ?? <dynamic>[];

    for (final entry in state) {
      final presences = entry.presences;
      for (final presence in presences) {
        final role = (presence.payload['role'] ?? '').toString().trim().toLowerCase();
        final authUserId = (presence.payload['auth_user_id'] ?? '').toString().trim();

        if (role == 'worker' && authUserId.isNotEmpty) {
          ids.add(authUserId);
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _appOnlineIds
        ..clear()
        ..addAll(ids);
    });
  }

  Future<void> _initAppPresenceWatcher() async {
    final supabase = Supabase.instance.client;

    final ch = supabase.channel(
      'app-presence',
      opts: const RealtimeChannelConfig(private: true),
    );

    ch
        .onPresenceSync((payload) {
      _refreshAppPresence();
    })
        .onPresenceJoin((payload) {
      _refreshAppPresence();
    })
        .onPresenceLeave((payload) {
      _refreshAppPresence();
    });

    ch.subscribe((status, [error]) {
      if (status == RealtimeSubscribeStatus.subscribed) {
        _refreshAppPresence();
      }
    });

    _appPresenceChannel = ch;
  }

  void _refreshPeerPresence() {
    final myId = Supabase.instance.client.auth.currentUser?.id;
    final state = _rtChannel?.presenceState() ?? <dynamic>[];

    var otherOnline = false;

    for (final entry in state) {
      final presences = entry.presences;
      for (final presence in presences) {
        final authUserId =
        (presence.payload['auth_user_id'] ?? '').toString();

        if (authUserId.isNotEmpty && authUserId != myId) {
          otherOnline = true;
        }
      }
    }

    if (!mounted) return;
    setState(() {
      _peerOnline = otherOnline;
      if (!otherOnline) {
        _peerActivity = '';
      }
    });
  }

  Future<void> _sendActivity(String kind, {required bool active}) async {
    final ch = _rtChannel;
    if (ch == null) return;

    final myId = Supabase.instance.client.auth.currentUser?.id;
    if (myId == null) return;

    await ch.sendBroadcastMessage(
      event: 'activity',
      payload: {
        'sender_id': myId,
        'kind': kind,
        'active': active,
        'at': DateTime.now().toIso8601String(),
      },
    );
  }

  void _onTextChanged(String value) {
    final hasText = value.trim().isNotEmpty;

    _typingTimer?.cancel();

    if (!hasText) {
      _sendActivity('typing', active: false);
      return;
    }

    _sendActivity('typing', active: true);

    _typingTimer = Timer(const Duration(milliseconds: 1200), () {
      _sendActivity('typing', active: false);
    });
  }

  String _headerStatusText() {
    if (_peerActivity == 'typing') return 'typing...';
    if (_peerActivity == 'uploading_image') return 'sending photo...';
    if (_peerActivity == 'uploading_file') return 'sending document...';
    return _appOnlineIds.contains(widget.workerAuthId) ? 'Online' : 'Offline';
  }

  bool _isIncomingForDivider(String senderRole) {
    return senderRole.toLowerCase() != 'admin';
  }

  bool _shouldShowNewDivider({
    required DateTime? createdAt,
    required DateTime? prevCreatedAt,
    required String senderRole,
    required String? prevSenderRole,
  }) {
    if (createdAt == null) return false;
    if (!_isIncomingForDivider(senderRole)) return false;
    if (!createdAt.toUtc().isAfter(_chatOpenedAt)) return false;

    if (prevCreatedAt == null) return true;
    if (prevSenderRole == null) return true;
    if (!_isIncomingForDivider(prevSenderRole)) return true;

    return !prevCreatedAt.toUtc().isAfter(_chatOpenedAt);
  }

  void _captureUnreadBoundary(List<Map<String, dynamic>> messages) {
    if (_unreadBoundaryCaptured) return;
    if (messages.isEmpty) return;

    for (final msg in messages) {
      final senderRole = _s(msg['sender_role']).toLowerCase();
      final readAt = msg['read_at'];
      final msgId = _s(msg['id']);

      if (senderRole != 'admin' && readAt == null && msgId.isNotEmpty) {
        _firstUnreadIncomingMessageId = msgId;
        break;
      }
    }

    _unreadBoundaryCaptured = true;
  }

  bool _shouldShowUnreadDivider(Map<String, dynamic> msg) {
    final msgId = _s(msg['id']);
    if (msgId.isEmpty) return false;
    return _firstUnreadIncomingMessageId == msgId;
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() => _sending = true);

    try {
      await _sendActivity('typing', active: false);

      await MessageService.sendAdminMessage(
        threadId: widget.threadId,
        text: text,
        replyToMessageId: _s(_replyToMessage?['id']),
      );

      _textCtrl.clear();
      _clearReply();
      await _markReadSafe();

      if (mounted) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Send failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendImageFromGallery() async {
    if (_sending) return;

    try {
      final file = await MessageService.pickImageFromGallery();
      if (file == null) return;

      if (mounted) {
        await _sendActivity('uploading_image', active: true);
        setState(() => _sending = true);
      }

      await MessageService.sendAdminImageMessage(
        threadId: widget.threadId,
        file: file,
        replyToMessageId: _s(_replyToMessage?['id']),
      );

      _clearReply();
      await _markReadSafe();

      if (mounted) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Image send failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        await _sendActivity('uploading_image', active: false);
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendImageFromCamera() async {
    if (_sending) return;

    try {
      final file = await MessageService.pickImageFromCamera();
      if (file == null) return;

      if (mounted) {
        await _sendActivity('uploading_image', active: true);
        setState(() => _sending = true);
      }

      await MessageService.sendAdminImageMessage(
        threadId: widget.threadId,
        file: file,
        replyToMessageId: _s(_replyToMessage?['id']),
      );

      _clearReply();
      await _markReadSafe();

      if (mounted) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Camera send failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        await _sendActivity('uploading_image', active: false);
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _sendFile() async {
    if (_sending) return;

    try {
      final file = await MessageService.pickAnyFile();
      if (file == null) return;

      if (mounted) {
        await _sendActivity('uploading_file', active: true);
        setState(() => _sending = true);
      }

      await MessageService.sendAdminFileMessage(
        threadId: widget.threadId,
        file: file,
        replyToMessageId: _s(_replyToMessage?['id']),
      );

      _clearReply();
      await _markReadSafe();

      if (mounted) {
        _scrollToBottom();
      }
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'File send failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    } finally {
      if (mounted) {
        await _sendActivity('uploading_file', active: false);
        setState(() => _sending = false);
      }
    }
  }

  Future<void> _openFileUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      if (uri == null) throw Exception('Invalid file url');

      final ok = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!ok) {
        throw Exception('Could not open file');
      }
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Open file failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }


  void _setReplyTo(Map<String, dynamic> msg) {
    if (!mounted) return;
    setState(() {
      _replyToMessage = Map<String, dynamic>.from(msg);
    });
  }

  void _clearReply() {
    if (!mounted) return;
    setState(() {
      _replyToMessage = null;
    });
  }

  GlobalKey _messageKey(String messageId) {
    return _messageKeys.putIfAbsent(messageId, () => GlobalKey());
  }

  void _showAppSnack(
    String text, {
    IconData icon = Icons.check_circle_rounded,
    Color accent = _ChatPalette.green,
  }) {
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        backgroundColor: Colors.transparent,
        margin: const EdgeInsets.fromLTRB(14, 0, 14, 18),
        padding: EdgeInsets.zero,
        duration: const Duration(milliseconds: 2200),
        content: _ChatSnackBarContent(
          text: text,
          icon: icon,
          accent: accent,
        ),
      ),
    );
  }

  String _safeFileName(String raw, {required String fallback}) {
    final cleaned = raw.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return cleaned.isEmpty ? fallback : cleaned;
  }

  String _messageFileName(Map<String, dynamic> msg) {
    final original = _s(msg['file_name']);
    if (original.isNotEmpty) {
      return _safeFileName(original, fallback: original);
    }

    final type = _s(msg['message_type']).toLowerCase();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    if (type == 'image') {
      return 'image_$stamp.jpg';
    }

    return 'file_$stamp.bin';
  }

  Future<Uint8List> _downloadBytes(String url) async {
    final uri = Uri.tryParse(url);
    if (uri == null) throw Exception('Invalid file url');

    final response = await http.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Download failed (${response.statusCode})');
    }

    return response.bodyBytes;
  }

  Future<File> _writeBytesToTemp(Uint8List bytes, String fileName) async {
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}${Platform.pathSeparator}${_safeFileName(fileName, fallback: "temp.bin")}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<File> _writeBytesToDevice(
    Uint8List bytes,
    String fileName, {
    required String folderName,
  }) async {
    Directory baseDir;

    if (Platform.isAndroid) {
      baseDir = await getExternalStorageDirectory() ?? await getApplicationDocumentsDirectory();
    } else {
      baseDir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    }

    final folder = Directory(
      '${baseDir.path}${Platform.pathSeparator}Workio${Platform.pathSeparator}$folderName',
    );

    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }

    final file = File('${folder.path}${Platform.pathSeparator}${_safeFileName(fileName, fallback: "file.bin")}');
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  Future<void> _saveImage(Map<String, dynamic> msg) async {
    final url = _s(msg['media_url']);
    if (url.isEmpty) return;

    try {
      final bytes = await _downloadBytes(url);
      final file = await _writeBytesToDevice(
        bytes,
        _messageFileName(msg),
        folderName: 'images',
      );

      _showAppSnack(
        'Image saved: ${file.path.split(Platform.pathSeparator).last}',
        icon: Icons.download_done_rounded,
        accent: _ChatPalette.green,
      );
    } catch (e) {
      _showAppSnack(
        'Save image failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  Future<void> _shareImage(Map<String, dynamic> msg) async {
    final url = _s(msg['media_url']);
    if (url.isEmpty) return;

    try {
      final bytes = await _downloadBytes(url);
      final file = await _writeBytesToTemp(bytes, _messageFileName(msg));
      await Share.shareXFiles([XFile(file.path)], text: _messageFileName(msg));
    } catch (e) {
      _showAppSnack(
        'Share image failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  Future<void> _downloadFile(Map<String, dynamic> msg) async {
    final url = _s(msg['media_url']);
    if (url.isEmpty) return;

    try {
      final bytes = await _downloadBytes(url);
      final file = await _writeBytesToDevice(
        bytes,
        _messageFileName(msg),
        folderName: 'files',
      );

      _showAppSnack(
        'File downloaded: ${file.path.split(Platform.pathSeparator).last}',
        icon: Icons.download_done_rounded,
        accent: _ChatPalette.blue,
      );
    } catch (e) {
      _showAppSnack(
        'Download file failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  Future<void> _scrollToMessageById(String messageId) async {
    if (messageId.trim().isEmpty || _currentMessages.isEmpty) return;

    final index =
    _currentMessages.indexWhere((item) => _s(item['id']) == messageId);

    if (index < 0) {
      _showAppSnack(
        'Pinned message not found',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
      return;
    }

    final targetKey = _messageKey(messageId);

    Future<bool> tryReveal() async {
      final targetContext = targetKey.currentContext;
      if (targetContext == null) return false;

      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.16,
      );
      return true;
    }

    if (await tryReveal()) return;
    if (!_scrollCtrl.hasClients) return;

    final maxScroll = _scrollCtrl.position.maxScrollExtent;

    // Специально берём более маленькую оценку,
    // чтобы не перелетать цель на первом шаге.
    double offset = (index * 96.0).clamp(0.0, maxScroll);

    await _scrollCtrl.animateTo(
      offset,
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );

    for (int i = 0; i < 7; i++) {
      await Future.delayed(const Duration(milliseconds: 70));

      if (await tryReveal()) return;
      if (!_scrollCtrl.hasClients) return;

      offset = (offset + 420.0).clamp(0.0, maxScroll);

      await _scrollCtrl.animateTo(
        offset,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
      );
    }

    final targetContext = targetKey.currentContext;
    if (targetContext != null) {
      await Scrollable.ensureVisible(
        targetContext,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
        alignment: 0.16,
      );
    } else {
      _showAppSnack(
        'Pinned message not found on screen',
        icon: Icons.info_outline_rounded,
        accent: _ChatPalette.orange,
      );
    }
  }

  String _replyAuthorLabel(Map<String, dynamic>? msg) {
    if (msg == null) return 'Message';

    final role = _s(msg['sender_role']).toLowerCase();
    if (role == 'admin') return 'You';

    final name = widget.workerName.trim();
    return name.isEmpty ? 'Worker' : name;
  }

  String _messagePreview(Map<String, dynamic>? msg) {
    if (msg == null) return 'Original message';

    if (_s(msg['deleted_at']).isNotEmpty) {
      return 'Deleted message';
    }

    final type = _s(msg['message_type']).toLowerCase();
    final body = _s(msg['body']);

    if (type == 'image') {
      return body.isEmpty ? 'Photo' : 'Photo · $body';
    }

    if (type == 'file') {
      final fileName = _s(msg['file_name']);
      return fileName.isEmpty ? 'File' : 'File · $fileName';
    }

    return body.isEmpty ? 'Empty message' : body;
  }

  String _copyValue(Map<String, dynamic> msg) {
    if (_s(msg['deleted_at']).isNotEmpty) return '';
    return _s(msg['body']);
  }

  Future<void> _copyMessage(Map<String, dynamic> msg) async {
    final value = _copyValue(msg);
    if (value.isEmpty) {
      _showAppSnack(
        'Nothing to copy',
        icon: Icons.info_outline_rounded,
        accent: _ChatPalette.orange,
      );
      return;
    }

    await Clipboard.setData(ClipboardData(text: value));
    _showAppSnack(
      'Copied',
      icon: Icons.copy_rounded,
      accent: _ChatPalette.blue,
    );
  }

  Future<void> _pinMessage(Map<String, dynamic> msg) async {
    final messageId = _s(msg['id']);
    if (messageId.isEmpty) return;

    try {
      await MessageService.pinThreadMessage(
        threadId: widget.threadId,
        messageId: messageId,
      );

      if (!mounted) return;
      setState(() {
        _pinnedOverride = Map<String, dynamic>.from(msg);
        _usePinnedOverride = true;
      });

      if (!mounted) return;
      _showAppSnack(
        'Message pinned',
        icon: Icons.push_pin_rounded,
        accent: _ChatPalette.orange,
      );
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Pin failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  Future<void> _unpinMessage() async {
    try {
      await MessageService.unpinThreadMessage(
        threadId: widget.threadId,
      );

      if (!mounted) return;
      setState(() {
        _pinnedOverride = null;
        _usePinnedOverride = true;
      });

      if (!mounted) return;
      _showAppSnack(
        'Pinned message removed',
        icon: Icons.push_pin_rounded,
        accent: _ChatPalette.orange,
      );
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Unpin failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  Future<void> _showMessageActions(
      Map<String, dynamic> msg,
      Offset globalPosition,
      ) async {
    final messageId = _s(msg['id']);
    final messageType = _s(msg['message_type']).toLowerCase();
    final isText = messageType.isEmpty || messageType == 'text';
    final hasMediaUrl = _s(msg['media_url']).isNotEmpty;
    final isDeleted = _s(msg['deleted_at']).isNotEmpty;
    final isMine = _s(msg['sender_role']).toLowerCase() == 'admin';

    if (messageId.isEmpty || isDeleted) return;

    final overlay =
    Overlay.of(context).context.findRenderObject() as RenderBox;

    final selected = await showMenu<_MessageAction>(
      context: context,
      color: const Color(0xFF12171E),
      surfaceTintColor: Colors.transparent,
      shadowColor: Colors.black.withOpacity(0.45),
      elevation: 20,
      menuPadding: const EdgeInsets.symmetric(vertical: 8),
      constraints: const BoxConstraints(
        minWidth: 220,
        maxWidth: 260,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(
          color: Colors.white.withOpacity(0.08),
        ),
      ),
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        overlay.size.width - globalPosition.dx,
        overlay.size.height - globalPosition.dy,
      ),
      items: [
        _menuItem(
          value: _MessageAction.reply,
          icon: Icons.reply_rounded,
          text: 'Reply',
        ),
        if (isText)
          _menuItem(
            value: _MessageAction.copy,
            icon: Icons.copy_rounded,
            text: 'Copy',
          ),
        if (messageType == 'image' && hasMediaUrl)
          _menuItem(
            value: _MessageAction.saveImage,
            icon: Icons.download_rounded,
            text: 'Save image',
          ),
        if (messageType == 'image' && hasMediaUrl)
          _menuItem(
            value: _MessageAction.shareImage,
            icon: Icons.share_rounded,
            text: 'Share image',
          ),
        if (messageType == 'file' && hasMediaUrl)
          _menuItem(
            value: _MessageAction.downloadFile,
            icon: Icons.download_rounded,
            text: 'Download file',
          ),
        _menuItem(
          value: _MessageAction.pin,
          icon: Icons.push_pin_outlined,
          text: 'Pin message',
          iconColor: Colors.amber,
        ),
        if (isMine && isText)
          _menuItem(
            value: _MessageAction.edit,
            icon: Icons.edit_rounded,
            text: 'Edit message',
          ),
        if (isMine)
          _menuItem(
            value: _MessageAction.delete,
            icon: Icons.delete_outline_rounded,
            text: 'Delete message',
            iconColor: Colors.redAccent,
            textColor: Colors.redAccent,
          ),
      ],
    );

    if (selected == null || !mounted) return;

    switch (selected) {
      case _MessageAction.reply:
        _setReplyTo(msg);
        break;
      case _MessageAction.copy:
        await _copyMessage(msg);
        break;
      case _MessageAction.saveImage:
        await _saveImage(msg);
        break;
      case _MessageAction.shareImage:
        await _shareImage(msg);
        break;
      case _MessageAction.downloadFile:
        await _downloadFile(msg);
        break;
      case _MessageAction.pin:
        await _pinMessage(msg);
        break;
      case _MessageAction.edit:
        await _editMessageDialog(msg);
        break;
      case _MessageAction.delete:
        await _deleteMessageConfirm(msg);
        break;
    }
  }

  Future<void> _editMessageDialog(Map<String, dynamic> msg) async {
    final controller = TextEditingController(text: _s(msg['body']));

    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Edit message',
            style: TextStyle(color: Colors.white),
          ),
          content: TextField(
            controller: controller,
            minLines: 1,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Write message...',
              hintStyle: TextStyle(color: Colors.white.withOpacity(0.34)),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide(color: Colors.white.withOpacity(0.16)),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Save'),
            ),
          ],
        );
      },
    );

    if (result == null || result.trim().isEmpty) return;

    try {
      await MessageService.editOwnTextMessage(
        messageId: _s(msg['id']),
        newText: result,
      );

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Edit failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  Future<void> _deleteMessageConfirm(Map<String, dynamic> msg) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF171B22),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text(
            'Delete message',
            style: TextStyle(color: Colors.white),
          ),
          content: const Text(
            'This message will be hidden in chat.',
            style: TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );

    if (ok != true) return;

    try {
      await MessageService.softDeleteOwnMessage(
        messageId: _s(msg['id']),
      );

      if (!mounted) return;
      setState(() {});
    } catch (e) {
      if (!mounted) return;
      _showAppSnack(
        'Delete failed: $e',
        icon: Icons.error_outline_rounded,
        accent: Colors.redAccent,
      );
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_scrollCtrl.hasClients) return;

      _scrollCtrl.jumpTo(_scrollCtrl.position.maxScrollExtent);

      await Future.delayed(const Duration(milliseconds: 120));
      if (!_scrollCtrl.hasClients) return;

      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    });
  }

  String _s(Object? v) => (v ?? '').toString().trim();

  DateTime? _parseDate(Object? v) {
    final s = _s(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  String _fmtDay(DateTime? dt) {
    if (dt == null) return '';
    return '${dt.month}/${dt.day}/${dt.year}';
  }

  bool _isSameDay(DateTime? a, DateTime? b) {
    if (a == null || b == null) return false;
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final bottomInset = mq.viewInsets.bottom;

    return Scaffold(
      backgroundColor: _ChatPalette.bg,
      resizeToAvoidBottomInset: true,
      body: Stack(
        children: [
          const _ChatBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _ChatHeader(
                    workerName: widget.workerName,
                    workerEmail: _headerStatusText(),
                    avatarUrl: widget.avatarUrl,
                    isOnline: _appOnlineIds.contains(widget.workerAuthId),
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                StreamBuilder<Map<String, dynamic>?>(
                  stream: MessageService.watchPinnedMessage(widget.threadId),
                  builder: (context, snapshot) {
                    final pinned = _usePinnedOverride ? _pinnedOverride : snapshot.data;

                    return Column(
                      children: [
                        SizedBox(height: pinned == null ? 12 : 6),
                        if (pinned != null)
                          Padding(
                            padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                            child: _PinnedMessageBar(
                              title: _replyAuthorLabel(pinned),
                              text: _messagePreview(pinned),
                              onTap: () => _scrollToMessageById(_s(pinned['id'])),
                              onUnpin: _unpinMessage,
                            ),
                          ),
                      ],
                    );
                  },
                ),
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(
                        child: StreamBuilder<List<Map<String, dynamic>>>(
                          stream: MessageService.watchMessages(widget.threadId),
                          builder: (context, snapshot) {
                            final messages = snapshot.data ?? <Map<String, dynamic>>[];
                            _currentMessages = messages;
                            final messagesById = <String, Map<String, dynamic>>{
                              for (final item in messages) _s(item['id']): item,
                            };

                            _captureUnreadBoundary(messages);

                            if (messages.length != _lastMessageCount) {
                              _lastMessageCount = messages.length;
                              WidgetsBinding.instance.addPostFrameCallback((_) {
                                _scrollToBottom();
                                _markReadSafe();
                              });
                            }

                            if (snapshot.connectionState == ConnectionState.waiting &&
                                !snapshot.hasData) {
                              return const Center(
                                child: SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.4,
                                    color: _ChatPalette.green,
                                  ),
                                ),
                              );
                            }

                            if (messages.isEmpty) {
                              return const _EmptyChatState();
                            }

                            return ListView.builder(
                              controller: _scrollCtrl,
                              padding: const EdgeInsets.fromLTRB(12, 6, 12, 84),
                              itemCount: messages.length,
                              itemBuilder: (context, index) {
                                final msg = messages[index];
                                final prev = index > 0 ? messages[index - 1] : null;

                                final senderRole = _s(msg['sender_role']);
                                final prevSenderRole = prev == null ? null : _s(prev['sender_role']);

                                final isMine = senderRole == 'admin';
                                final isDeleted = _s(msg['deleted_at']).isNotEmpty;
                                final isEdited = _s(msg['edited_at']).isNotEmpty;
                                final createdAt = _parseDate(msg['created_at']);
                                final prevCreatedAt =
                                prev == null ? null : _parseDate(prev['created_at']);

                                final showDay = !_isSameDay(createdAt, prevCreatedAt);
                                final showNewDivider = _shouldShowNewDivider(
                                  createdAt: createdAt,
                                  prevCreatedAt: prevCreatedAt,
                                  senderRole: senderRole,
                                  prevSenderRole: prevSenderRole,
                                );
                                final showUnreadDivider = _shouldShowUnreadDivider(msg);
                                if (showUnreadDivider) {
                                  debugPrint('ADMIN SHOW unread divider for msgId=${_s(msg['id'])}');
                                }
                                final replyToId = _s(msg['reply_to_message_id']);
                                final repliedMsg =
                                replyToId.isEmpty ? null : messagesById[replyToId];

                                return Column(
                                  key: _messageKey(_s(msg['id'])),
                                  children: [
                                    if (showDay)
                                      Padding(
                                        padding: const EdgeInsets.fromLTRB(0, 8, 0, 12),
                                        child: _DayChip(text: _fmtDay(createdAt)),
                                      ),
                                    if (showUnreadDivider)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
                                        child: _UnreadMessagesDivider(),
                                      ),
                                    if (showNewDivider)
                                      const Padding(
                                        padding: EdgeInsets.fromLTRB(0, 0, 0, 12),
                                        child: _NewMessagesDivider(),
                                      ),
                                    Align(
                                      alignment:
                                      isMine ? Alignment.centerRight : Alignment.centerLeft,
                                      child: GestureDetector(
                                        onLongPressStart: !isDeleted
                                            ? (details) => _showMessageActions(msg, details.globalPosition)
                                            : null,
                                        child: isDeleted
                                            ? _DeletedBubble(
                                          timeText: _fmtTime(createdAt),
                                          isMine: isMine,
                                        )
                                            : ((_s(msg['message_type']).toLowerCase() == 'image') &&
                                            _s(msg['media_url']).isNotEmpty)
                                            ? _ImageBubble(
                                          imageUrl: _s(msg['media_url']),
                                          timeText: _fmtTime(createdAt),
                                          isMine: isMine,
                                          caption: _s(msg['body']),
                                          replyTitle: replyToId.isEmpty
                                              ? null
                                              : _replyAuthorLabel(repliedMsg),
                                          replyText: replyToId.isEmpty
                                              ? null
                                              : _messagePreview(repliedMsg),
                                          onTap: () {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => ChatImageViewerScreen(
                                                  imageUrl: _s(msg['media_url']),
                                                  heroTag: _s(msg['media_url']),
                                                ),
                                              ),
                                            );
                                          },
                                        )
                                            : ((_s(msg['message_type']).toLowerCase() == 'file') &&
                                            _s(msg['media_url']).isNotEmpty)
                                            ? _FileBubble(
                                          fileName: _s(msg['file_name']),
                                          fileUrl: _s(msg['media_url']),
                                          timeText: _fmtTime(createdAt),
                                          isMine: isMine,
                                          mimeType: _s(msg['mime_type']),
                                          fileSize: msg['file_size'],
                                          replyTitle: replyToId.isEmpty
                                              ? null
                                              : _replyAuthorLabel(repliedMsg),
                                          replyText: replyToId.isEmpty
                                              ? null
                                              : _messagePreview(repliedMsg),
                                          onTap: () =>
                                              _openFileUrl(_s(msg['media_url'])),
                                        )
                                            : _MessageBubble(
                                          text: _s(msg['body']),
                                          timeText: _fmtTime(createdAt),
                                          isMine: isMine,
                                          isEdited: isEdited,
                                          replyTitle: replyToId.isEmpty
                                              ? null
                                              : _replyAuthorLabel(repliedMsg),
                                          replyText: replyToId.isEmpty
                                              ? null
                                              : _messagePreview(repliedMsg),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 8),

                                  ],
                                );
                              },
                            );
                          },
                        ),
                      ),
                      const Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        child: _ScrollEdgeBlur.top(),
                      ),
                      const Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: _ScrollEdgeBlur.bottom(),
                      ),
                    ],
                  ),
                ),
                AnimatedPadding(
                  duration: const Duration(milliseconds: 120),
                  padding: EdgeInsets.fromLTRB(
                    12,
                    0,
                    12,
                    12 + (bottomInset > 0 ? 6 : 0),
                  ),
                  child: _Composer(
                    onChanged: _onTextChanged,
                    controller: _textCtrl,
                    sending: _sending,
                    onSend: _send,
                    onAttachTap: _showAttachSheet,
                    replyTitle: _replyAuthorLabel(_replyToMessage),
                    replyText: _replyToMessage == null
                        ? null
                        : _messagePreview(_replyToMessage),
                    onCancelReply: _replyToMessage == null ? null : _clearReply,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatPalette {
  static const bg = Color(0xFF0B0D12);

  static const cardTop = Color(0xFF2F3036);
  static const cardBottom = Color(0xFF24252B);
  static const cardBorder = Color(0xFF3A3B42);

  static const pill = Color(0xFF1F2025);
  static const pillBorder = Color(0xFF34353C);

  static const textMain = Color(0xFFEDEFF6);
  static const textSoft = Color(0xFFB7BCCB);
  static const textMute = Color(0xFF8B90A0);

  static const green = Color(0xFF34D399);
  static const blue = Color(0xFF38BDF8);
  static const orange = Color(0xFFF59E0B);
}

class _ChatBackground extends StatelessWidget {
  const _ChatBackground();

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Container(color: _ChatPalette.bg),
        const Positioned.fill(
          child: IgnorePointer(
            child: _ToolPattern(),
          ),
        ),
      ],
    );
  }
}

class _ToolPattern extends StatelessWidget {
  const _ToolPattern();

  static const List<IconData> _icons = [
    Icons.handyman_rounded,
    Icons.hardware_rounded,
    Icons.build_rounded,
    Icons.construction_rounded,
    Icons.plumbing_rounded,
    Icons.home_repair_service_rounded,
    Icons.electrical_services_rounded,
    Icons.carpenter_rounded,
    Icons.cleaning_services_rounded,
    Icons.format_paint_rounded,
    Icons.roofing_rounded,
    Icons.garage_rounded,
    Icons.foundation_rounded,
    Icons.lock_outline_rounded,
    Icons.settings_rounded,
    Icons.precision_manufacturing_rounded,
    Icons.architecture_rounded,
    Icons.square_foot_rounded,
    Icons.rule_rounded,
    Icons.design_services_rounded,
  ];

  static const List<Offset> _points = [
    Offset(0.08, 0.10),
    Offset(0.28, 0.14),
    Offset(0.52, 0.09),
    Offset(0.77, 0.12),
    Offset(0.16, 0.24),
    Offset(0.41, 0.22),
    Offset(0.68, 0.20),
    Offset(0.86, 0.27),
    Offset(0.09, 0.39),
    Offset(0.31, 0.35),
    Offset(0.56, 0.33),
    Offset(0.79, 0.40),
    Offset(0.14, 0.54),
    Offset(0.39, 0.50),
    Offset(0.63, 0.56),
    Offset(0.86, 0.52),
    Offset(0.10, 0.71),
    Offset(0.34, 0.75),
    Offset(0.60, 0.72),
    Offset(0.83, 0.78),
  ];

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;

        return Stack(
          children: List.generate(_icons.length, (i) {
            final p = _points[i];
            final size = 14.0 + ((i % 4) * 2.0);
            final angle = ((i % 5) - 2) * 0.10;

            return Positioned(
              left: w * p.dx,
              top: h * p.dy,
              child: Transform.rotate(
                angle: angle,
                child: Icon(
                  _icons[i],
                  size: size,
                  color: const Color(0xFF7EAFFF).withOpacity(0.075),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

class _ChatHeader extends StatelessWidget {
  final String workerName;
  final String workerEmail;
  final String avatarUrl;
  final bool isOnline;
  final VoidCallback onBack;

  const _ChatHeader({
    required this.workerName,
    required this.workerEmail,
    required this.avatarUrl,
    required this.isOnline,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF232833),
                Color(0xFF1A1F28),
                Color(0xFF141922),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Row(
            children: [
              _TopIconBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 10),
              _HeaderAvatar(
                avatarUrl: avatarUrl,
                isOnline: isOnline,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      workerName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _ChatPalette.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      workerEmail.isEmpty ? 'Worker chat' : workerEmail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.56),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.3,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.forum_rounded,
                size: 30,
                color: Color(0xFF55A7FF),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ScrollEdgeBlur extends StatelessWidget {
  final bool top;
  final double height;

  const _ScrollEdgeBlur.top({
    this.height = 26,
  }) : top = true;

  const _ScrollEdgeBlur.bottom({
    this.height = 58,
  }) : top = false;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        height: height,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: top
                ? const [0.0, 0.18, 0.45, 0.72, 1.0]
                : const [0.0, 0.12, 0.32, 0.60, 0.82, 1.0],
            colors: top
                ? [
              _ChatPalette.bg.withOpacity(0.92),
              _ChatPalette.bg.withOpacity(0.62),
              _ChatPalette.bg.withOpacity(0.28),
              _ChatPalette.bg.withOpacity(0.10),
              _ChatPalette.bg.withOpacity(0.0),
            ]
                : [
              _ChatPalette.bg.withOpacity(0.0),
              _ChatPalette.bg.withOpacity(0.05),
              _ChatPalette.bg.withOpacity(0.14),
              _ChatPalette.bg.withOpacity(0.34),
              _ChatPalette.bg.withOpacity(0.62),
              _ChatPalette.bg.withOpacity(0.90),
            ],
          ),
        ),
      ),
    );
  }
}

class _TopIconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _TopIconBtn({
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF31363E),
                Color(0xFF232830),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Center(
            child: Icon(
              icon,
              color: Colors.white.withOpacity(0.82),
              size: 19,
            ),
          ),
        ),
      ),
    );
  }
}

class _HeaderAvatar extends StatelessWidget {
  final String avatarUrl;
  final bool isOnline;

  const _HeaderAvatar({
    required this.avatarUrl,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 46,
      height: 46,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: avatarUrl.isEmpty
                ? Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF59E0B).withOpacity(0.14),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withOpacity(0.28),
                ),
              ),
              child: const Center(
                child: Icon(
                  Icons.person_rounded,
                  color: Color(0xFFF59E0B),
                  size: 22,
                ),
              ),
            )
                : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.network(
                avatarUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFF59E0B).withOpacity(0.14),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withOpacity(0.28),
                    ),
                  ),
                  child: const Center(
                    child: Icon(
                      Icons.person_rounded,
                      color: Color(0xFFF59E0B),
                      size: 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            right: -1,
            bottom: -1,
            child: Container(
              width: 13,
              height: 13,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isOnline ? const Color(0xFF34D399) : Colors.grey,
                border: Border.all(
                  color: const Color(0xFF24252B),
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  final String text;

  const _DayChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1D23),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: const Color(0xFF3A404A).withOpacity(0.75),
        ),
      ),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(
            color: Color(0xFF7AB8FF),
            fontWeight: FontWeight.w900,
            fontSize: 11.2,
          ),
        ),
      ),
    );
  }
}

class _NewMessagesDivider extends StatelessWidget {
  const _NewMessagesDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFF55A7FF).withOpacity(0.35),
                ],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF16202C),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFF55A7FF).withOpacity(0.28),
            ),
          ),
          child: const Text(
            'New messages',
            style: TextStyle(
              color: Color(0xFF7AB8FF),
              fontWeight: FontWeight.w900,
              fontSize: 10.8,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFF55A7FF).withOpacity(0.35),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _BubbleTail extends StatelessWidget {
  final bool isMine;
  final List<Color> colors;
  final Color borderColor;

  const _BubbleTail({
    required this.isMine,
    required this.colors,
    required this.borderColor,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: const Size(14, 16),
      painter: _BubbleTailPainter(
        isMine: isMine,
        colors: colors,
        borderColor: borderColor,
      ),
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  final bool isMine;
  final List<Color> colors;
  final Color borderColor;

  _BubbleTailPainter({
    required this.isMine,
    required this.colors,
    required this.borderColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path();

    if (isMine) {
      path.moveTo(0, 0);
      path.quadraticBezierTo(size.width * 0.25, size.height * 0.10, size.width * 0.45, size.height * 0.35);
      path.quadraticBezierTo(size.width * 0.95, size.height * 0.85, size.width, size.height);
      path.lineTo(0, size.height);
      path.close();
    } else {
      path.moveTo(size.width, 0);
      path.quadraticBezierTo(size.width * 0.75, size.height * 0.10, size.width * 0.55, size.height * 0.35);
      path.quadraticBezierTo(size.width * 0.05, size.height * 0.85, 0, size.height);
      path.lineTo(size.width, size.height);
      path.close();
    }

    final rect = Offset.zero & size;
    final fillPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: colors,
      ).createShader(rect);

    final strokePaint = Paint()
      ..color = borderColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawPath(path, fillPaint);
    canvas.drawPath(path, strokePaint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) {
    return oldDelegate.isMine != isMine ||
        oldDelegate.colors != colors ||
        oldDelegate.borderColor != borderColor;
  }
}

class _MessageBubble extends StatelessWidget {
  final String text;
  final String timeText;
  final bool isMine;
  final bool isEdited;
  final String? replyTitle;
  final String? replyText;

  const _MessageBubble({
    required this.text,
    required this.timeText,
    required this.isMine,
    this.isEdited = false,
    this.replyTitle,
    this.replyText,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.76;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 20),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isMine
              ? [
            const Color(0xFF1F3F68),
            const Color(0xFF17304F),
          ]
              : [
                  _ChatPalette.cardTop.withOpacity(0.98),
                  _ChatPalette.cardBottom.withOpacity(0.97),
                ],
        ),
        border: Border.all(
          color: isMine
              ? const Color(0xFF55A7FF).withOpacity(0.22)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyText != null && replyText!.trim().isNotEmpty) ...[
            _ReplyPreview(
              title: replyTitle ?? 'Reply',
              text: replyText!,
            ),
            const SizedBox(height: 8),
          ],
          Text(
            text,
            style: const TextStyle(
              color: _ChatPalette.textMain,
              fontWeight: FontWeight.w700,
              fontSize: 14.2,
              height: 1.34,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isEdited) ...[
                Text(
                  'edited',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.34),
                    fontWeight: FontWeight.w800,
                    fontSize: 10.2,
                  ),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                timeText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontWeight: FontWeight.w800,
                  fontSize: 10.6,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeletedBubble extends StatelessWidget {
  final String timeText;
  final bool isMine;

  const _DeletedBubble({
    required this.timeText,
    required this.isMine,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.76;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 20),
        ),
        color: Colors.white.withOpacity(0.045),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Column(
        crossAxisAlignment:
        isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Text(
            'Message deleted',
            style: TextStyle(
              color: Colors.white.withOpacity(0.44),
              fontWeight: FontWeight.w700,
              fontSize: 13.6,
              fontStyle: FontStyle.italic,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            timeText,
            style: TextStyle(
              color: Colors.white.withOpacity(0.32),
              fontWeight: FontWeight.w800,
              fontSize: 10.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _FileBubble extends StatelessWidget {
  final String fileName;
  final String fileUrl;
  final String timeText;
  final bool isMine;
  final String mimeType;
  final Object? fileSize;
  final String? replyTitle;
  final String? replyText;
  final VoidCallback? onTap;

  const _FileBubble({
    required this.fileName,
    required this.fileUrl,
    required this.timeText,
    required this.isMine,
    required this.mimeType,
    required this.fileSize,
    this.replyTitle,
    this.replyText,
    this.onTap,
  });

  String _fmtBytes(Object? value) {
    final n = value is num ? value.toDouble() : 0.0;
    if (n <= 0) return '';
    if (n < 1024) return '${n.toInt()} B';
    if (n < 1024 * 1024) return '${(n / 1024).toStringAsFixed(1)} KB';
    return '${(n / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  IconData _icon() {
    final m = mimeType.toLowerCase();
    final f = fileName.toLowerCase();

    if (m.contains('pdf') || f.endsWith('.pdf')) {
      return Icons.picture_as_pdf_rounded;
    }
    if (f.endsWith('.doc') || f.endsWith('.docx')) {
      return Icons.description_rounded;
    }
    if (f.endsWith('.xls') || f.endsWith('.xlsx')) {
      return Icons.table_chart_rounded;
    }
    if (f.endsWith('.zip') || f.endsWith('.rar')) {
      return Icons.folder_zip_rounded;
    }
    return Icons.insert_drive_file_rounded;
  }

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.76;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 20),
        ),
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(maxWidth: maxWidth),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(20),
              topRight: const Radius.circular(20),
              bottomLeft: Radius.circular(isMine ? 20 : 6),
              bottomRight: Radius.circular(isMine ? 6 : 20),
            ),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: isMine
                  ? [
                      const Color(0xFF21453B),
                      const Color(0xFF18372F),
                    ]
                  : [
                      _ChatPalette.cardTop.withOpacity(0.98),
                      _ChatPalette.cardBottom.withOpacity(0.97),
                    ],
            ),
            border: Border.all(
              color: isMine
                  ? _ChatPalette.green.withOpacity(0.18)
                  : Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              if (replyText != null && replyText!.trim().isNotEmpty) ...[
                _ReplyPreview(
                  title: replyTitle ?? 'Reply',
                  text: replyText!,
                ),
                const SizedBox(height: 8),
              ],
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _icon(),
                    color: Colors.white.withOpacity(0.82),
                    size: 22,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileName.isEmpty ? 'File' : fileName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _ChatPalette.textMain,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _fmtBytes(fileSize),
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.46),
                            fontWeight: FontWeight.w700,
                            fontSize: 11.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Tap to open',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.56),
                  fontWeight: FontWeight.w800,
                  fontSize: 11.2,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                timeText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.45),
                  fontWeight: FontWeight.w800,
                  fontSize: 10.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;
  final VoidCallback onAttachTap;
  final ValueChanged<String> onChanged;
  final String? replyTitle;
  final String? replyText;
  final VoidCallback? onCancelReply;

  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
    required this.onAttachTap,
    required this.onChanged,
    this.replyTitle,
    this.replyText,
    this.onCancelReply,
  });

  @override
  Widget build(BuildContext context) {
    final hasReply = replyText != null && replyText!.trim().isNotEmpty;

    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _ChatPalette.cardTop.withOpacity(0.97),
                _ChatPalette.cardBottom.withOpacity(0.96),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasReply) ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.14),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white.withOpacity(0.06)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 4,
                        height: 34,
                        decoration: BoxDecoration(
                          color: _ChatPalette.orange,
                          borderRadius: BorderRadius.circular(999),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              replyTitle ?? 'Reply',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _ChatPalette.orange.withOpacity(0.96),
                                fontWeight: FontWeight.w900,
                                fontSize: 12,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              replyText!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.74),
                                fontWeight: FontWeight.w700,
                                fontSize: 12,
                                height: 1.22,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(14),
                          onTap: onCancelReply,
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(14),
                              color: Colors.white.withOpacity(0.04),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.06),
                              ),
                            ),
                            child: Center(
                              child: Icon(
                                Icons.close_rounded,
                                color: Colors.white.withOpacity(0.74),
                                size: 18,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: sending ? null : onAttachTap,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF31363E),
                              Color(0xFF232830),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: const Center(
                          child: Icon(
                            Icons.add_rounded,
                            color: Colors.white70,
                            size: 22,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      onChanged: onChanged,
                      minLines: 1,
                      maxLines: 5,
                      textInputAction: TextInputAction.newline,
                      style: const TextStyle(
                        color: _ChatPalette.textMain,
                        fontWeight: FontWeight.w700,
                      ),
                      decoration: InputDecoration(
                        hintText: hasReply ? 'Write reply...' : 'Write a message...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(0.34),
                          fontWeight: FontWeight.w600,
                        ),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(18),
                      onTap: sending ? null : onSend,
                      child: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(18),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF3E7BFF),
                              Color(0xFF2457D6),
                            ],
                          ),
                          border: Border.all(
                            color: const Color(0xFF55A7FF).withOpacity(0.24),
                          ),
                        ),
                        child: Center(
                          child: sending
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(
                                  Icons.send_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyChatState extends StatelessWidget {
  const _EmptyChatState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _ChatPalette.cardTop.withOpacity(0.97),
                _ChatPalette.cardBottom.withOpacity(0.96),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              Icon(
                Icons.chat_bubble_outline_rounded,
                size: 28,
                color: Colors.white.withOpacity(0.56),
              ),
              const SizedBox(height: 10),
              const Text(
                'No messages yet',
                style: TextStyle(
                  color: _ChatPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Start the conversation with your worker.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.54),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ImageBubble extends StatelessWidget {
  final String imageUrl;
  final String timeText;
  final bool isMine;
  final String caption;
  final String? replyTitle;
  final String? replyText;
  final VoidCallback? onTap;

  const _ImageBubble({
    required this.imageUrl,
    required this.timeText,
    required this.isMine,
    required this.caption,
    this.replyTitle,
    this.replyText,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final maxWidth = MediaQuery.of(context).size.width * 0.76;

    return Container(
      constraints: BoxConstraints(maxWidth: maxWidth),
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(20),
          topRight: const Radius.circular(20),
          bottomLeft: Radius.circular(isMine ? 20 : 6),
          bottomRight: Radius.circular(isMine ? 6 : 20),
        ),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isMine
              ? [
            const Color(0xFF1F3F68),
            const Color(0xFF17304F),
          ]
              : [
            _ChatPalette.cardTop.withOpacity(0.98),
            _ChatPalette.cardBottom.withOpacity(0.97),
          ],
        ),
        border: Border.all(
          color: isMine
              ? const Color(0xFF55A7FF).withOpacity(0.22)
              : Colors.white.withOpacity(0.08),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (replyText != null && replyText!.trim().isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 2, 4, 8),
              child: _ReplyPreview(
                title: replyTitle ?? 'Reply',
                text: replyText!,
              ),
            ),
          ],
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.network(
                  imageUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 180,
                    alignment: Alignment.center,
                    color: Colors.black.withOpacity(0.18),
                    child: Text(
                      'Failed to load image',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          if (caption.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Text(
                caption,
                style: const TextStyle(
                  color: _ChatPalette.textMain,
                  fontWeight: FontWeight.w700,
                  fontSize: 14.2,
                  height: 1.34,
                ),
              ),
            ),
          ],
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: Text(
              timeText,
              style: TextStyle(
                color: Colors.white.withOpacity(0.45),
                fontWeight: FontWeight.w800,
                fontSize: 10.6,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ReplyPreview extends StatelessWidget {
  final String title;
  final String text;

  const _ReplyPreview({
    required this.title,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.14),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withOpacity(0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 4,
            height: 34,
            decoration: BoxDecoration(
              color: const Color(0xFF55A7FF),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: const Color(0xFF7AB8FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 11.8,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    height: 1.22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatSnackBarContent extends StatelessWidget {
  final String text;
  final IconData icon;
  final Color accent;

  const _ChatSnackBarContent({
    required this.text,
    required this.icon,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF1B2028),
                Color(0xFF12171E),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.28),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  color: accent.withOpacity(0.14),
                  border: Border.all(color: accent.withOpacity(0.28)),
                ),
                child: Icon(icon, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    height: 1.22,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PinnedMessageBar extends StatelessWidget {
  final String title;
  final String text;
  final VoidCallback? onTap;
  final VoidCallback? onUnpin;

  const _PinnedMessageBar({
    required this.title,
    required this.text,
    this.onTap,
    this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(20),
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    Color(0xFF232833),
                    Color(0xFF1A1F28),
                    Color(0xFF141922),
                  ],
                ),
                border: Border.all(
                  color: Colors.white.withOpacity(0.08),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.22),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.push_pin_rounded,
                    color: Color(0xFF55A7FF),
                    size: 20,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF55A7FF),
                            fontWeight: FontWeight.w900,
                            fontSize: 12,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          text,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.74),
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            height: 1.22,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (onUnpin != null) ...[
                    const SizedBox(width: 8),
                    Material(
                      color: Colors.transparent,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: onUnpin,
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF343A47),
                                Color(0xFF2A303B),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white.withOpacity(0.08),
                            ),
                          ),
                          child: Center(
                            child: Icon(
                              Icons.close_rounded,
                              color: Colors.white.withOpacity(0.72),
                              size: 18,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnreadMessagesDivider extends StatelessWidget {
  const _UnreadMessagesDivider();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.transparent,
                  const Color(0xFFF59E0B).withOpacity(0.38),
                ],
              ),
            ),
          ),
        ),
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 10),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: const Color(0xFF2B2212),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: const Color(0xFFF59E0B).withOpacity(0.30),
            ),
          ),
          child: const Text(
            'Unread messages',
            style: TextStyle(
              color: Color(0xFFF6BE4A),
              fontWeight: FontWeight.w900,
              fontSize: 10.8,
              letterSpacing: 0.2,
            ),
          ),
        ),
        Expanded(
          child: Container(
            height: 1,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  const Color(0xFFF59E0B).withOpacity(0.38),
                  Colors.transparent,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}