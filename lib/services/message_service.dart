import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:typed_data';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'app_push_service.dart';

class MessageService {
  MessageService._();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  static String _id(Object? v) => (v ?? '').toString().trim();
  static String? _idOrNull(Object? v) {
    final s = _id(v);
    return s.isEmpty ? null : s;
  }

  static Future<Map<String, dynamic>?> _fetchThreadPushInfo(String threadId) async {
    final cleanThreadId = threadId.trim();
    if (cleanThreadId.isEmpty) return null;

    final row = await _supabase
        .from('message_threads')
        .select('''
        id,
        admin_auth_id,
        worker_auth_id,
        workers(
          id,
          name,
          email,
          auth_user_id
        )
      ''')
        .eq('id', cleanThreadId)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  static String _messagePushBody({
    required String messageType,
    String? text,
    String? fileName,
  }) {
    final type = messageType.trim().toLowerCase();

    if (type == 'image') return 'Sent a photo';
    if (type == 'file') {
      final name = _id(fileName);
      return name.isEmpty ? 'Sent a file' : 'Sent a file: $name';
    }

    final body = _id(text);
    if (body.isEmpty) return 'New message';
    if (body.length <= 90) return body;
    return '${body.substring(0, 90)}...';
  }

  static Future<void> _sendChatPush({
    required String threadId,
    required String senderRole, // admin | worker
    required String messageType, // text | image | file
    String? text,
    String? fileName,
  }) async {
    try {
      debugPrint('CHAT PUSH START role=$senderRole thread=$threadId type=$messageType');
      final thread = await _fetchThreadPushInfo(threadId);
      debugPrint('CHAT PUSH THREAD = $thread');
      if (thread == null) return;

      final cleanSenderRole = senderRole.trim().toLowerCase();

      final adminAuthId = _id(thread['admin_auth_id']);
      final workerAuthId = _id(thread['worker_auth_id']);

      debugPrint('CHAT PUSH adminAuthId=$adminAuthId workerAuthId=$workerAuthId');

      final workerMap = thread['workers'] is Map
          ? Map<String, dynamic>.from(thread['workers'] as Map)
          : <String, dynamic>{};

      final workerName = _id(workerMap['name']).isNotEmpty
          ? _id(workerMap['name'])
          : 'Worker';

      final pushBody = _messagePushBody(
        messageType: messageType,
        text: text,
        fileName: fileName,
      );

      if (cleanSenderRole == 'admin') {
        if (workerAuthId.isEmpty) return;

        debugPrint('CHAT PUSH SEND TO WORKER = $workerAuthId');

        await AppPushService.send(
          toUserId: workerAuthId,
          role: 'worker',
          title: 'Message • Admin',
          body: pushBody,
          data: {
            'type': 'chat',
            'thread_id': threadId,
            'sender_role': 'admin',
            'chat_message_type': messageType,
          },
        );
        return;
      }

      if (cleanSenderRole == 'worker') {
        if (adminAuthId.isEmpty) return;

        debugPrint('CHAT PUSH SEND TO ADMIN = $adminAuthId');

        await AppPushService.send(
          toUserId: adminAuthId,
          role: 'admin',
          title: 'Message • $workerName',
          body: pushBody,
          data: {
            'type': 'chat',
            'thread_id': threadId,
            'sender_role': 'worker',
            'chat_message_type': messageType,
            'worker_auth_id': workerAuthId,
          },
        );
      }
    } catch (e) {
      debugPrint('CHAT PUSH ERROR: $e');
    }
  }

  // =========================================================
  // THREADS
  // =========================================================

  static Future<Map<String, dynamic>> getOrCreateAdminThread({
    required String workerId,
    required String workerAuthId,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) {
      throw Exception('No authenticated admin');
    }

    final existing = await _supabase
        .from('message_threads')
        .select()
        .eq('admin_auth_id', adminId)
        .eq('worker_id', workerId)
        .maybeSingle();

    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    final inserted = await _supabase
        .from('message_threads')
        .insert({
      'admin_auth_id': adminId,
      'worker_id': workerId,
      'worker_auth_id': workerAuthId,
    })
        .select()
        .single();

    return Map<String, dynamic>.from(inserted);
  }

  static Future<Map<String, dynamic>> getOrCreateWorkerThread() async {
    final workerAuthId = _supabase.auth.currentUser?.id;
    if (workerAuthId == null) {
      throw Exception('No authenticated worker');
    }

    final worker = await _supabase
        .from('workers')
        .select('id, owner_admin_id, auth_user_id')
        .eq('auth_user_id', workerAuthId)
        .single();

    final workerMap = Map<String, dynamic>.from(worker);
    final workerId = _id(workerMap['id']);
    final adminAuthId = _id(workerMap['owner_admin_id']);

    final existing = await _supabase
        .from('message_threads')
        .select()
        .eq('worker_auth_id', workerAuthId)
        .eq('worker_id', workerId)
        .maybeSingle();

    if (existing != null) {
      return Map<String, dynamic>.from(existing);
    }

    final inserted = await _supabase
        .from('message_threads')
        .insert({
      'admin_auth_id': adminAuthId,
      'worker_id': workerId,
      'worker_auth_id': workerAuthId,
    })
        .select()
        .single();

    return Map<String, dynamic>.from(inserted);
  }

  static Future<List<Map<String, dynamic>>> fetchAdminThreads() async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return [];

    final rows = await _supabase
        .from('message_threads')
        .select('''
          id,
          admin_auth_id,
          worker_id,
          worker_auth_id,
          created_at,
          updated_at,
          last_message_at,
          workers!inner(
            id,
            name,
            email,
            avatar_url,
            auth_user_id,
            owner_admin_id
          )
        ''')
        .eq('admin_auth_id', adminId)
        .order('last_message_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<Map<String, dynamic>?> fetchWorkerThread() async {
    final workerAuthId = _supabase.auth.currentUser?.id;
    if (workerAuthId == null) return null;

    final rows = await _supabase
        .from('message_threads')
        .select('''
          id,
          admin_auth_id,
          worker_id,
          worker_auth_id,
          created_at,
          updated_at,
          last_message_at,
          workers!inner(
            id,
            name,
            email,
            avatar_url,
            auth_user_id,
            owner_admin_id
          )
        ''')
        .eq('worker_auth_id', workerAuthId)
        .order('last_message_at', ascending: false)
        .limit(1);

    if (rows is List && rows.isNotEmpty) {
      return Map<String, dynamic>.from(rows.first as Map);
    }

    return null;
  }

  static Stream<List<Map<String, dynamic>>> watchAdminThreads() {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) {
      return Stream.value(<Map<String, dynamic>>[]);
    }

    return _supabase
        .from('message_threads')
        .stream(primaryKey: ['id'])
        .eq('admin_auth_id', adminId)
        .order('last_message_at', ascending: false)
        .asyncMap((rows) async {
      final threads = rows.map((e) => Map<String, dynamic>.from(e)).toList();

      if (threads.isEmpty) return <Map<String, dynamic>>[];

      final workerIds = threads
          .map((t) => _id(t['worker_id']))
          .where((e) => e.isNotEmpty)
          .toSet()
          .toList();

      final workersRows = await _supabase
          .from('workers')
          .select('id, name, email, avatar_url, auth_user_id, owner_admin_id')
          .inFilter('id', workerIds);

      final workerById = <String, Map<String, dynamic>>{};
      for (final row in (workersRows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        workerById[_id(map['id'])] = map;
      }

      final authIds = workerById.values
          .map((w) => _id(w['auth_user_id']))
          .where((e) => e.isNotEmpty)
          .toList();

      final activeRows = authIds.isEmpty
          ? <dynamic>[]
          : await _supabase
          .from('work_logs')
          .select('user_id')
          .inFilter('user_id', authIds)
          .isFilter('end_time', null);

      final onlineAuthIds = <String>{};
      for (final row in (activeRows as List)) {
        final map = Map<String, dynamic>.from(row as Map);
        final userId = _id(map['user_id']);
        if (userId.isNotEmpty) {
          onlineAuthIds.add(userId);
        }
      }

      final result = <Map<String, dynamic>>[];
      for (final t in threads) {
        final worker = workerById[_id(t['worker_id'])] ?? <String, dynamic>{};

        result.add({
          ...t,
          'workers': {
            ...worker,
            'on_shift': onlineAuthIds.contains(_id(worker['auth_user_id'])),
          },
        });
      }
      return result;
    });
  }



  static Stream<Map<String, dynamic>?> watchWorkerThread() {
    final workerAuthId = _supabase.auth.currentUser?.id;
    if (workerAuthId == null) {
      return Stream.value(null);
    }

    return _supabase
        .from('message_threads')
        .stream(primaryKey: ['id'])
        .eq('worker_auth_id', workerAuthId)
        .order('last_message_at', ascending: false)
        .map((rows) {
      if (rows.isEmpty) return null;
      return Map<String, dynamic>.from(rows.first);
    });
  }


  static Stream<Map<String, dynamic>?> watchPinnedMessage(String threadId) {
    if (threadId.trim().isEmpty) {
      return Stream.value(null);
    }

    return _supabase
        .from('message_threads')
        .stream(primaryKey: ['id'])
        .eq('id', threadId)
        .asyncMap((rows) async {
      if (rows.isEmpty) return null;

      final thread = Map<String, dynamic>.from(rows.first);
      final pinnedMessageId = _id(thread['pinned_message_id']);
      if (pinnedMessageId.isEmpty) return null;

      final message = await _supabase
          .from('messages')
          .select()
          .eq('id', pinnedMessageId)
          .maybeSingle();

      if (message == null) return null;
      return Map<String, dynamic>.from(message);
    });
  }

  static Future<void> pinThreadMessage({
    required String threadId,
    required String messageId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final message = await _supabase
        .from('messages')
        .select('id, thread_id, deleted_at')
        .eq('id', messageId)
        .maybeSingle();

    if (message == null) {
      throw Exception('Message not found');
    }

    final messageMap = Map<String, dynamic>.from(message);
    if (_id(messageMap['thread_id']) != threadId) {
      throw Exception('Message does not belong to this thread');
    }
    if (_id(messageMap['deleted_at']).isNotEmpty) {
      throw Exception('Deleted message cannot be pinned');
    }

    await _supabase.from('message_threads').update({
      'pinned_message_id': messageId,
      'pinned_at': DateTime.now().toUtc().toIso8601String(),
      'pinned_by': userId,
    }).eq('id', threadId);
  }

  static Future<void> unpinThreadMessage({
    required String threadId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    await _supabase.from('message_threads').update({
      'pinned_message_id': null,
      'pinned_at': null,
      'pinned_by': null,
    }).eq('id', threadId);
  }

  // =========================================================
  // MESSAGES
  // =========================================================

  static Stream<List<Map<String, dynamic>>> watchMessages(String threadId) {
    return _supabase
        .from('messages')
        .stream(primaryKey: ['id'])
        .eq('thread_id', threadId)
        .order('created_at', ascending: true)
        .map((rows) => rows.map((e) => Map<String, dynamic>.from(e)).toList());
  }

  static Future<List<Map<String, dynamic>>> fetchMessages(String threadId) async {
    final rows = await _supabase
        .from('messages')
        .select()
        .eq('thread_id', threadId)
        .order('created_at', ascending: true);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Future<void> sendAdminMessage({
    required String threadId,
    required String text,
    String? replyToMessageId,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) throw Exception('No authenticated admin');

    final body = text.trim();
    if (body.isEmpty) return;

    await _supabase.from('messages').insert({
      'thread_id': threadId,
      'sender_auth_id': adminId,
      'sender_role': 'admin',
      'body': body,
      'reply_to_message_id': _idOrNull(replyToMessageId),
    });

    await _sendChatPush(
      threadId: threadId,
      senderRole: 'admin',
      messageType: 'text',
      text: body,
    );
  }

  static Future<void> sendWorkerMessage({
    required String threadId,
    required String text,
    String? replyToMessageId,
  }) async {
    final workerId = _supabase.auth.currentUser?.id;
    if (workerId == null) throw Exception('No authenticated worker');

    final body = text.trim();
    if (body.isEmpty) return;

    await _supabase.from('messages').insert({
      'thread_id': threadId,
      'sender_auth_id': workerId,
      'sender_role': 'worker',
      'body': body,
      'reply_to_message_id': _idOrNull(replyToMessageId),
    });

    await _sendChatPush(
      threadId: threadId,
      senderRole: 'worker',
      messageType: 'text',
      text: body,
    );
  }

  static Future<void> markThreadRead(String threadId) async {
    final myId = _supabase.auth.currentUser?.id;
    if (myId == null || threadId.trim().isEmpty) return;

    await _supabase.rpc(
      'mark_thread_read',
      params: {'p_thread_id': threadId},
    );
  }

  static Future<int> countUnreadForAdminThread(String threadId) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return 0;

    final rows = await _supabase
        .from('messages')
        .select('id')
        .eq('thread_id', threadId)
        .neq('sender_auth_id', adminId)
        .isFilter('read_at', null);

    return (rows as List).length;
  }

  static Future<int> countUnreadForWorkerThread(String threadId) async {
    final workerId = _supabase.auth.currentUser?.id;
    if (workerId == null) return 0;

    final rows = await _supabase
        .from('messages')
        .select('id')
        .eq('thread_id', threadId)
        .neq('sender_auth_id', workerId)
        .isFilter('read_at', null);

    return (rows as List).length;
  }

  static Future<List<Map<String, dynamic>>> fetchAdminWorkers() async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return [];

    final rows = await _supabase
        .from('workers')
        .select('id, name, email, avatar_url, auth_user_id, owner_admin_id')
        .eq('owner_admin_id', adminId)
        .order('name', ascending: true);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((w) => _id(w['auth_user_id']).isNotEmpty)
        .toList();
  }

  static Stream<int> watchAdminUnreadCount() {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) {
      return Stream.value(0);
    }

    return watchAdminThreads().asyncMap((threads) async {
      if (threads.isEmpty) return 0;

      var total = 0;
      for (final t in threads) {
        final threadId = _id(t['id']);
        if (threadId.isEmpty) continue;
        total += await countUnreadForAdminThread(threadId);
      }
      return total;
    });
  }

  // =========================================================
  // IMAGE PICK / UPLOAD
  // =========================================================

  static Future<XFile?> pickImageFromGallery() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
  }

  static Future<XFile?> pickImageFromCamera() async {
    return _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
    );
  }

  static Future<Map<String, dynamic>> uploadChatImage(XFile file) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No authenticated user');
    }

    final bytes = await file.readAsBytes();
    final originalName = file.name.trim().isEmpty ? 'image.jpg' : file.name.trim();
    final ext = p.extension(originalName).toLowerCase().replaceFirst('.', '');
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}.$safeExt';
    final path = 'messages/$userId/$fileName';

    await _supabase.storage.from('chat-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _guessImageMime(safeExt),
      ),
    );

    final publicUrl = _supabase.storage.from('chat-media').getPublicUrl(path);

    return {
      'media_url': publicUrl,
      'media_path': path,
      'file_name': originalName,
      'mime_type': _guessImageMime(safeExt),
      'file_size': bytes.length,
      'message_type': 'image',
    };
  }

  static Future<void> sendAdminImageMessage({
    required String threadId,
    required XFile file,
    String? replyToMessageId,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) throw Exception('No authenticated admin');

    final upload = await uploadChatImage(file);

    await _supabase.from('messages').insert({
      'thread_id': threadId,
      'sender_auth_id': adminId,
      'sender_role': 'admin',
      'body': '',
      'message_type': 'image',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      'reply_to_message_id': _idOrNull(replyToMessageId),
    });

    await _sendChatPush(
      threadId: threadId,
      senderRole: 'admin',
      messageType: 'image',
      fileName: upload['file_name']?.toString(),
    );
  }

  static Future<void> sendWorkerImageMessage({
    required String threadId,
    required XFile file,
    String? replyToMessageId,
  }) async {
    final workerId = _supabase.auth.currentUser?.id;
    if (workerId == null) throw Exception('No authenticated worker');

    final upload = await uploadChatImage(file);

    await _supabase.from('messages').insert({
      'thread_id': threadId,
      'sender_auth_id': workerId,
      'sender_role': 'worker',
      'body': '',
      'message_type': 'image',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      'reply_to_message_id': _idOrNull(replyToMessageId),
    });

    await _sendChatPush(
      threadId: threadId,
      senderRole: 'worker',
      messageType: 'image',
      fileName: upload['file_name']?.toString(),
    );
  }

  static String _guessImageMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'gif':
        return 'image/gif';
      case 'heic':
        return 'image/heic';
      case 'heif':
        return 'image/heif';
      case 'jpg':
      case 'jpeg':
      default:
        return 'image/jpeg';
    }
  }

  static Future<void> editOwnTextMessage({
    required String messageId,
    required String newText,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final text = newText.trim();
    if (text.isEmpty) {
      throw Exception('Message cannot be empty');
    }

    await _supabase
        .from('messages')
        .update({
      'body': text,
      'edited_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', messageId)
        .eq('sender_auth_id', userId)
        .eq('message_type', 'text')
        .isFilter('deleted_at', null);
  }

  static Future<void> softDeleteOwnMessage({
    required String messageId,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final row = await _supabase
        .from('messages')
        .select('media_path')
        .eq('id', messageId)
        .eq('sender_auth_id', userId)
        .maybeSingle();

    final mediaPath = _id(row?['media_path']);

    if (mediaPath.isNotEmpty) {
      try {
        await _supabase.storage.from('chat-media').remove([mediaPath]);
      } catch (_) {}
    }

    await _supabase
        .from('messages')
        .update({
      'body': '',
      'media_url': null,
      'media_path': null,
      'file_name': null,
      'mime_type': null,
      'file_size': null,
      'deleted_at': DateTime.now().toUtc().toIso8601String(),
      'deleted_by': userId,
    })
        .eq('id', messageId)
        .eq('sender_auth_id', userId)
        .isFilter('deleted_at', null);
  }

  // =========================================================
  // FILE PICK / UPLOAD
  // =========================================================

  static Future<PlatformFile?> pickAnyFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  static Future<Map<String, dynamic>> uploadChatFile(PlatformFile file) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) {
      throw Exception('No authenticated user');
    }

    final bytes = file.bytes;
    if (bytes == null || bytes.isEmpty) {
      throw Exception('Could not read file bytes');
    }

    if (bytes.length > 20 * 1024 * 1024) {
      throw Exception('File is too large. Max 20 MB.');
    }

    final originalName =
    file.name.trim().isEmpty ? 'file.bin' : file.name.trim();

    final ext = p.extension(originalName).toLowerCase().replaceFirst('.', '');
    final safeExt = ext.isEmpty ? 'bin' : ext;

    final base = p.basenameWithoutExtension(originalName).trim();
    final safeBase = base.isEmpty
        ? 'file'
        : base.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');

    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}_${safeBase}.$safeExt';

    final path = 'messages/$userId/files/$fileName';

    await _supabase.storage.from('chat-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _guessFileMime(safeExt),
      ),
    );

    final publicUrl = _supabase.storage.from('chat-media').getPublicUrl(path);

    return {
      'media_url': publicUrl,
      'media_path': path,
      'file_name': originalName,
      'mime_type': _guessFileMime(safeExt),
      'file_size': bytes.length,
      'message_type': 'file',
    };
  }

  static Future<void> sendAdminFileMessage({
    required String threadId,
    required PlatformFile file,
    String? replyToMessageId,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) throw Exception('No authenticated admin');

    final upload = await uploadChatFile(file);

    await _supabase.from('messages').insert({
      'thread_id': threadId,
      'sender_auth_id': adminId,
      'sender_role': 'admin',
      'body': '',
      'message_type': 'file',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      'reply_to_message_id': _idOrNull(replyToMessageId),
    });

    await _sendChatPush(
      threadId: threadId,
      senderRole: 'admin',
      messageType: 'file',
      fileName: upload['file_name']?.toString(),
    );
  }

  static Future<void> sendWorkerFileMessage({
    required String threadId,
    required PlatformFile file,
    String? replyToMessageId,
  }) async {
    final workerId = _supabase.auth.currentUser?.id;
    if (workerId == null) throw Exception('No authenticated worker');

    final upload = await uploadChatFile(file);

    await _supabase.from('messages').insert({
      'thread_id': threadId,
      'sender_auth_id': workerId,
      'sender_role': 'worker',
      'body': '',
      'message_type': 'file',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      'reply_to_message_id': _idOrNull(replyToMessageId),
    });

    await _sendChatPush(
      threadId: threadId,
      senderRole: 'worker',
      messageType: 'file',
      fileName: upload['file_name']?.toString(),
    );
  }

  static String _guessFileMime(String ext) {
    switch (ext.toLowerCase()) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'txt':
        return 'text/plain';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'webp':
        return 'image/webp';
      case 'mp4':
        return 'video/mp4';
      case 'mov':
        return 'video/quicktime';
      default:
        return 'application/octet-stream';
    }
  }

}