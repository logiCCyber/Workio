import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'app_push_service.dart';

class TaskService {
  TaskService();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  static String _s(Object? v) => (v ?? '').toString().trim();

  static String _shortText(String value, {int max = 90}) {
    final text = value.trim();
    if (text.length <= max) return text;
    return '${text.substring(0, max)}...';
  }

  static String _prettyStatus(String status) {
    switch (status.trim().toLowerCase()) {
      case 'todo':
        return 'To do';
      case 'in_progress':
        return 'In progress';
      case 'done':
        return 'Done';
      case 'cancelled':
        return 'Cancelled';
      case 'blocked':
        return 'Blocked';
      case 'not_needed':
        return 'Not needed';
      case 'partial':
        return 'Partially done';
      default:
        return status.trim().isEmpty ? 'Updated' : status.trim();
    }
  }

  static String _taskPushTitleForStatus({
    required String status,
    String? workerName,
  }) {
    final clean = status.trim().toLowerCase();
    final by = workerName == null || workerName.trim().isEmpty
        ? ''
        : ' by ${workerName.trim()}';

    switch (clean) {
      case 'done':
        return 'Task • Completed$by';
      case 'cancelled':
        return 'Task • Cancelled$by';
      case 'in_progress':
        return 'Task • Started$by';
      case 'needs_review':
        return 'Task • Needs review$by';
      default:
        return 'Task • Status changed$by';
    }
  }

  static String _taskPushTitleForUpdate({
    required List<String> changedParts,
    String? workerName,
  }) {
    final hasStatus = changedParts.any(
          (e) => e.trim().toLowerCase().startsWith('status'),
    );

    if (hasStatus) {
      return _taskPushTitleForStatus(
        status: '',
        workerName: workerName,
      );
    }

    final by = workerName == null || workerName.trim().isEmpty
        ? ''
        : ' by ${workerName.trim()}';

    if (changedParts.any((e) => e.toLowerCase().contains('due'))) {
      return 'Task • Due date changed$by';
    }

    if (changedParts.any((e) => e.toLowerCase().contains('priority'))) {
      return 'Task • Priority changed$by';
    }

    if (changedParts.any((e) => e.toLowerCase().contains('note'))) {
      return 'Task • Note updated$by';
    }

    return 'Task • Updated$by';
  }

  static String _taskPushStatusBody({
    required String taskTitle,
    required String status,
  }) {
    final title = taskTitle.trim().isEmpty ? 'Task' : taskTitle.trim();
    return '$title • ${_prettyStatus(status)}';
  }

  // =========================================================
  // ATTACHMENTS
  // =========================================================

  static bool _isProofAttachmentUpload({
    required Map<String, dynamic> upload,
    String? proofSubtaskId,
    String? proofKind,
    Map<String, dynamic>? proofMeta,
  }) {
    final fileName = _s(upload['file_name']).toLowerCase();
    final mediaPath = _s(upload['media_path']).toLowerCase();

    if (_s(proofSubtaskId).isNotEmpty) return true;
    if (_s(proofKind).isNotEmpty) return true;
    if (proofMeta != null && proofMeta.isNotEmpty) return true;

    return fileName.startsWith('proof__') || mediaPath.contains('proof__');
  }

  static Future<String> _attachmentWorkerName(String workerAuthId) async {
    final id = workerAuthId.trim();
    if (id.isEmpty) return 'Worker';

    try {
      final row = await _supabase
          .from('workers')
          .select('name, email')
          .eq('auth_user_id', id)
          .maybeSingle();

      if (row == null) return 'Worker';

      final map = Map<String, dynamic>.from(row as Map);
      final name = _s(map['name']);
      if (name.isNotEmpty) return name;

      final email = _s(map['email']);
      if (email.isNotEmpty) return email;

      return 'Worker';
    } catch (_) {
      return 'Worker';
    }
  }

  static Future<void> _notifyTaskAttachmentUploaded({
    required String taskId,
    required String uploadedByRole, // admin | worker
    required String attachmentType, // image | file
    required Map<String, dynamic> upload,
    String? proofSubtaskId,
    String? proofKind,
    Map<String, dynamic>? proofMeta,
  }) async {
    try {
      // ✅ proof photo от checklist не пушим второй раз
      if (_isProofAttachmentUpload(
        upload: upload,
        proofSubtaskId: proofSubtaskId,
        proofKind: proofKind,
        proofMeta: proofMeta,
      )) {
        return;
      }

      final task = await _fetchTaskById(taskId);
      if (task == null) return;

      final cleanRole = uploadedByRole.trim().toLowerCase();
      final cleanType = attachmentType.trim().toLowerCase();

      final isImage = cleanType == 'image';
      final eventType = isImage ? 'photo_added' : 'file_added';

      final taskTitle = _s(task['title']).isEmpty ? 'Task' : _s(task['title']);
      final fileName = _s(upload['file_name']);
      final bodyFile = fileName.isEmpty
          ? (isImage ? 'Photo' : 'File')
          : fileName;

      try {
        await _insertTaskEvent(
          taskId: taskId,
          actorRole: cleanRole,
          eventType: eventType,
          meta: {
            'attachment_type': cleanType,
            'file_name': fileName,
          },
        );
      } catch (e) {
        debugPrint('TASK ATTACHMENT EVENT ERROR: $e');
      }

      if (cleanRole == 'worker') {
        final adminAuthId = _s(task['admin_auth_id']);
        if (adminAuthId.isEmpty) return;

        final workerName = await _attachmentWorkerName(_s(task['worker_auth_id']));

        await AppPushService.send(
          toUserId: adminAuthId,
          role: 'admin',
          title: isImage
              ? 'Task • Photo uploaded by $workerName'
              : 'Task • File uploaded by $workerName',
          body: '$taskTitle • $bodyFile',
          data: {
            'type': 'task',
            'task_id': taskId,
            'event_type': eventType,
            'attachment_type': cleanType,
            'uploaded_by_role': 'worker',
          },
        );

        return;
      }

      if (cleanRole == 'admin') {
        final workerAuthId = _s(task['worker_auth_id']);
        if (workerAuthId.isEmpty) return;

        await AppPushService.send(
          toUserId: workerAuthId,
          role: 'worker',
          title: isImage
              ? 'Task • Photo uploaded'
              : 'Task • File uploaded',
          body: '$taskTitle • $bodyFile',
          data: {
            'type': 'task',
            'task_id': taskId,
            'event_type': eventType,
            'attachment_type': cleanType,
            'uploaded_by_role': 'admin',
          },
        );
      }
    } catch (e) {
      debugPrint('TASK ATTACHMENT PUSH ERROR: $e');
    }
  }

  static Future<String> _workerDisplayName(String workerAuthId) async {
    final id = workerAuthId.trim();
    if (id.isEmpty) return 'Worker';

    try {
      final row = await _supabase
          .from('workers')
          .select('name, email')
          .eq('auth_user_id', id)
          .maybeSingle();

      if (row == null) return 'Worker';

      final map = Map<String, dynamic>.from(row as Map);
      final name = _s(map['name']);
      if (name.isNotEmpty) return name;

      final email = _s(map['email']);
      if (email.isNotEmpty) return email;

      return 'Worker';
    } catch (_) {
      return 'Worker';
    }
  }

  static Future<void> _pushTaskToWorker({
    required Map<String, dynamic> task,
    required String title,
    required String body,
    required String eventType,
    Map<String, dynamic>? extraData,
  }) async {
    final workerAuthId = _s(task['worker_auth_id']);
    final taskId = _s(task['id']);

    if (workerAuthId.isEmpty || taskId.isEmpty) return;

    await AppPushService.send(
      toUserId: workerAuthId,
      role: 'worker',
      title: title,
      body: _shortText(body),
      data: {
        'type': 'task',
        'task_id': taskId,
        'event_type': eventType,
        ...?extraData,
      },
    );
  }

  static Future<void> _pushTaskToAdmin({
    required Map<String, dynamic> task,
    required String title,
    required String body,
    required String eventType,
    Map<String, dynamic>? extraData,
  }) async {
    final adminAuthId = _s(task['admin_auth_id']);
    final taskId = _s(task['id']);

    if (adminAuthId.isEmpty || taskId.isEmpty) return;

    await AppPushService.send(
      toUserId: adminAuthId,
      role: 'admin',
      title: title,
      body: _shortText(body),
      data: {
        'type': 'task',
        'task_id': taskId,
        'event_type': eventType,
        ...?extraData,
      },
    );
  }

  static final RegExp _checklistRegExp =
  RegExp(r'^\s*(?:\d+[.):]|[-•])\s+(.+?)\s*$');

  static List<String> extractChecklistItems(String text) {
    return text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .map((line) {
      final match = _checklistRegExp.firstMatch(line);
      return match == null ? '' : (match.group(1) ?? '').trim();
    })
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static String stripChecklistFromDescription(String text) {
    final lines = text
        .split('\n')
        .map((e) => e.trimRight())
        .where((e) => e.trim().isNotEmpty)
        .where((line) => !_checklistRegExp.hasMatch(line))
        .toList();

    return lines.join('\n').trim();
  }


  static String? _nullableTrim(String? value) {
    final trimmed = (value ?? '').trim();
    return trimmed.isEmpty ? null : trimmed;
  }

  static bool _sameNullableText(String? a, String? b) {
    return _nullableTrim(a) == _nullableTrim(b);
  }

  static bool _sameDueValue(Object? oldValue, DateTime? newValue) {
    final oldDt = DateTime.tryParse(_s(oldValue))?.toUtc();
    final newDt = newValue?.toUtc();

    if (oldDt == null && newDt == null) return true;
    if (oldDt == null || newDt == null) return false;

    return oldDt.isAtSameMomentAs(newDt);
  }

  static bool _sameChecklist(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].trim() != b[i].trim()) return false;
    }
    return true;
  }

  static Map<String, dynamic> _cleanMeta(Map<String, dynamic>? input) {
    final source = input ?? const <String, dynamic>{};
    final out = <String, dynamic>{};

    source.forEach((key, value) {
      if (value == null) return;
      if (value is String && value.trim().isEmpty) return;
      out[key] = value;
    });

    return out;
  }

  static Future<Map<String, dynamic>?> _fetchTaskById(String taskId) async {
    final row = await _supabase
        .from('worker_tasks')
        .select()
        .eq('id', taskId)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  static Future<Map<String, dynamic>?> _fetchSubtaskById(String subtaskId) async {
    final row = await _supabase
        .from('task_subtasks')
        .select()
        .eq('id', subtaskId)
        .maybeSingle();

    if (row == null) return null;
    return Map<String, dynamic>.from(row as Map);
  }

  static Future<String> _resolveActorRoleForTask(String taskId) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return 'system';

    final task = await _fetchTaskById(taskId);
    if (task == null) return 'system';

    if (_s(task['admin_auth_id']) == userId) return 'admin';
    if (_s(task['worker_auth_id']) == userId) return 'worker';
    return 'system';
  }

  static Future<void> _insertTaskEvent({
    required String taskId,
    required String actorRole,
    required String eventType,
    Map<String, dynamic>? meta,
  }) async {
    final cleanTaskId = taskId.trim();
    if (cleanTaskId.isEmpty) return;

    final actorAuthId = _supabase.auth.currentUser?.id;
    if (actorAuthId == null || actorAuthId.trim().isEmpty) return;

    final cleanActorRole = actorRole.trim().isEmpty
        ? 'system'
        : actorRole.trim().toLowerCase();

    final cleanEventType = eventType.trim();
    if (cleanEventType.isEmpty) return;

    final cleanMeta = _cleanMeta(meta);

    await _supabase.from('task_events').insert({
      'task_id': cleanTaskId,
      'actor_auth_id': actorAuthId,
      'actor_role': cleanActorRole,
      'event_type': cleanEventType,
      'meta': cleanMeta,
      'seen_by_admin_at': cleanActorRole == 'admin'
          ? DateTime.now().toUtc().toIso8601String()
          : null,
      'seen_by_worker_at': cleanActorRole == 'worker'
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    });
  }

  static Future<List<String>> _fetchAdminTaskIds({
    bool includeArchived = true,
  }) async {
    final tasks = await fetchAdminTasks(includeArchived: includeArchived);
    return tasks
        .map((e) => _s(e['id']))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  static Future<List<String>> _fetchWorkerTaskIds({
    bool includeArchived = true,
  }) async {
    final tasks = await fetchWorkerTasks(includeArchived: includeArchived);
    return tasks
        .map((e) => _s(e['id']))
        .where((e) => e.isNotEmpty)
        .toList();
  }

  // =========================================================
  // WORKERS
  // =========================================================

  static Future<List<Map<String, dynamic>>> fetchAdminWorkers() async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return [];

    final rows = await _supabase
        .from('workers')
        .select('id, name, email, avatar_url, auth_user_id, owner_admin_id, is_active, access_mode')
        .eq('owner_admin_id', adminId)
        .order('name', ascending: true);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((w) => _s(w['auth_user_id']).isNotEmpty)
        .toList();
  }


  // =========================================================
  // TASKS - ADMIN
  // =========================================================

  static Future<List<Map<String, dynamic>>> fetchAdminTasks({
    String? workerId,
    bool includeArchived = false,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return [];

    var query = _supabase
        .from('worker_tasks')
        .select('''
          id,
          admin_auth_id,
          worker_id,
          worker_auth_id,
          title,
          description,
          status,
          priority,
          due_at,
          completed_at,
          worker_note,
          sort_order,
          is_archived,
          created_at,
          updated_at,
          workers!inner(
            id,
            name,
            email,
            avatar_url,
            auth_user_id,
            owner_admin_id
          )
        ''')
        .eq('admin_auth_id', adminId);

    if (!includeArchived) {
      query = query.eq('is_archived', false);
    }

    if (workerId != null && workerId.trim().isNotEmpty) {
      query = query.eq('worker_id', workerId.trim());
    }

    final rows = await query
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> watchAdminTasks({
    String? workerId,
    bool includeArchived = false,
  }) async* {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) {
      yield const <Map<String, dynamic>>[];
      return;
    }

    final workers = await fetchAdminWorkers();
    final workersById = <String, Map<String, dynamic>>{
      for (final w in workers) _s(w['id']): w,
    };

    yield* _supabase
        .from('worker_tasks')
        .stream(primaryKey: ['id'])
        .map((rows) {
      final list = rows
          .map((e) {
        final map = Map<String, dynamic>.from(e);
        map['workers'] = workersById[_s(map['worker_id'])] ?? <String, dynamic>{};
        return map;
      })
          .where((e) => _s(e['admin_auth_id']) == adminId)
          .where((e) => includeArchived || e['is_archived'] == false)
          .where((e) =>
      workerId == null ||
          workerId.trim().isEmpty ||
          _s(e['worker_id']) == workerId.trim())
          .toList();

      list.sort((a, b) {
        final aSort = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bSort = (b['sort_order'] as num?)?.toInt() ?? 0;
        if (aSort != bSort) return aSort.compareTo(bSort);

        final aCreated = DateTime.tryParse(_s(a['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = DateTime.tryParse(_s(b['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bCreated.compareTo(aCreated);
      });

      return list;
    });
  }

  static Future<Map<String, dynamic>> createAdminTask({
    required String workerId,
    required String workerAuthId,
    required String title,
    String? description,
    String priority = 'normal',
    DateTime? dueAt,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) throw Exception('No authenticated admin');

    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw Exception('Task title is required');
    }

    final cleanDescription = _nullableTrim(description);

    final payload = {
      'admin_auth_id': adminId,
      'worker_id': workerId.trim(),
      'worker_auth_id': workerAuthId.trim(),
      'title': cleanTitle,
      'description': cleanDescription,
      'priority': priority,
      'status': 'todo',
      'is_archived': false,
      'sort_order': 0,
      'due_at': dueAt?.toUtc().toIso8601String(),
    };

    debugPrint('CREATE 1');
    debugPrint(
      'adminId=$adminId workerId=${workerId.trim()} workerAuthId=${workerAuthId.trim()} title=$cleanTitle',
    );
    debugPrint('CREATE 2 BEFORE INSERT');

    try {
      final inserted = await _supabase
          .from('worker_tasks')
          .insert(payload)
          .select('id, admin_auth_id, worker_id, worker_auth_id, title, description, priority, status, due_at')
          .single()
          .timeout(const Duration(seconds: 10));

      debugPrint('CREATE 3 AFTER INSERT: $inserted');

      final created = Map<String, dynamic>.from(inserted);

      await _pushTaskToWorker(
        task: created,
        title: 'Task • New assignment',
        body: '$cleanTitle • ${priority.toUpperCase()}',
        eventType: 'task_created',
        extraData: {
          'priority': priority,
          'status': 'todo',
        },
      );

      try {
        await _insertTaskEvent(
          taskId: _s(created['id']),
          actorRole: 'admin',
          eventType: 'task_created',
          meta: {
            'title': cleanTitle,
            'priority': priority,
            'status': 'todo',
            'due_at': dueAt?.toUtc().toIso8601String(),
            'has_description': cleanDescription != null,
          },
        );
      } catch (_) {}

      return created;
    } on TimeoutException {
      debugPrint('CREATE ERROR: INSERT TIMEOUT');
      throw Exception('INSERT TIMEOUT in worker_tasks');
    } catch (e) {
      debugPrint('CREATE ERROR: $e');
      throw Exception('worker_tasks insert failed: $e');
    }
  }

  static Future<void> updateAdminTask({
    required String taskId,
    required String title,
    String? description,
    required String priority,
    DateTime? dueAt,
    String? status,
    int? sortOrder,
    bool? isArchived,
  }) async {
    final cleanTitle = title.trim();
    if (cleanTitle.isEmpty) {
      throw Exception('Task title is required');
    }

    final existing = await _fetchTaskById(taskId);
    if (existing == null) {
      throw Exception('Task not found');
    }

    final cleanDescription = _nullableTrim(description);
    final cleanStatus = (status ?? '').trim();

    final payload = <String, dynamic>{
      'title': cleanTitle,
      'description': cleanDescription,
      'priority': priority,
      'due_at': dueAt?.toUtc().toIso8601String(),
    };


    if (cleanStatus.isNotEmpty) {
      final normalizedStatus = cleanStatus.toLowerCase();
      final isTerminalStatus =
          normalizedStatus == 'done' || normalizedStatus == 'cancelled';

      payload['status'] = cleanStatus;
      payload['completed_at'] =
      normalizedStatus == 'done' ? DateTime.now().toUtc().toIso8601String() : null;

      payload['worker_acknowledged_at'] = isTerminalStatus
          ? existing['worker_acknowledged_at']
          : null;
    }
    if (sortOrder != null) {
      payload['sort_order'] = sortOrder;
    }
    if (isArchived != null) {
      payload['is_archived'] = isArchived;
    }

    await _supabase.from('worker_tasks').update(payload).eq('id', taskId);

    if (_s(existing['title']) != cleanTitle) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'title_changed',
        meta: {'title': cleanTitle},
      );
    }

    final oldDescriptionBody = stripChecklistFromDescription(_s(existing['description']));
    final newDescriptionBody = stripChecklistFromDescription(cleanDescription ?? '');
    if (!_sameNullableText(oldDescriptionBody, newDescriptionBody)) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'description_changed',
        meta: {'has_description': newDescriptionBody.trim().isNotEmpty},
      );
    }

    if (_s(existing['priority']).toLowerCase() != priority.toLowerCase()) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'priority_changed',
        meta: {'priority': priority},
      );
    }

    if (!_sameDueValue(existing['due_at'], dueAt)) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'due_changed',
        meta: {'due_at': dueAt?.toUtc().toIso8601String()},
      );
    }

    if (cleanStatus.isNotEmpty && _s(existing['status']).toLowerCase() != cleanStatus.toLowerCase()) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'status_changed',
        meta: {'status': cleanStatus},
      );
    }

    if (sortOrder != null && ((existing['sort_order'] as num?)?.toInt() ?? 0) != sortOrder) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'sort_changed',
        meta: {'sort_order': sortOrder},
      );
    }

    if (isArchived != null && (existing['is_archived'] == true) != isArchived) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'admin',
        eventType: 'archive_changed',
        meta: {'is_archived': isArchived},
      );
    }

    final changedParts = <String>[];

    if (_s(existing['title']) != cleanTitle) {
      changedParts.add('title');
    }

    if (!_sameNullableText(oldDescriptionBody, newDescriptionBody)) {
      changedParts.add('description');
    }

    if (_s(existing['priority']).toLowerCase() != priority.toLowerCase()) {
      changedParts.add('priority');
    }

    if (!_sameDueValue(existing['due_at'], dueAt)) {
      changedParts.add('due time');
    }

    if (cleanStatus.isNotEmpty &&
        _s(existing['status']).toLowerCase() != cleanStatus.toLowerCase()) {
      changedParts.add('status ${_prettyStatus(cleanStatus)}');
    }

    if (isArchived != null && (existing['is_archived'] == true) != isArchived) {
      changedParts.add(isArchived ? 'archived' : 'unarchived');
    }

    if (changedParts.isNotEmpty) {
      final nextStatus = cleanStatus.isEmpty
          ? _s(existing['status'])
          : cleanStatus;

      final statusWasChanged = cleanStatus.isNotEmpty &&
          _s(existing['status']).toLowerCase() != cleanStatus.toLowerCase();

      await _pushTaskToWorker(
        task: {
          ...existing,
          'id': taskId,
          'title': cleanTitle,
          'priority': priority,
          'status': nextStatus,
        },
        title: statusWasChanged
            ? _taskPushTitleForStatus(status: nextStatus)
            : _taskPushTitleForUpdate(changedParts: changedParts),
        body: statusWasChanged
            ? _taskPushStatusBody(
          taskTitle: cleanTitle,
          status: nextStatus,
        )
            : '$cleanTitle • ${changedParts.join(', ')}',
        eventType: statusWasChanged ? 'status_changed' : 'task_updated',
        extraData: {
          'changes': changedParts.join(','),
          'status': nextStatus,
        },
      );
    }
  }

  static Future<void> archiveAdminTask(String taskId) async {
    await _supabase
        .from('worker_tasks')
        .update({'is_archived': true})
        .eq('id', taskId);

    await _insertTaskEvent(
      taskId: taskId,
      actorRole: 'admin',
      eventType: 'archive_changed',
      meta: {'is_archived': true},
    );
  }

  static Future<void> unarchiveAdminTask(String taskId) async {
    await _supabase
        .from('worker_tasks')
        .update({'is_archived': false})
        .eq('id', taskId);

    await _insertTaskEvent(
      taskId: taskId,
      actorRole: 'admin',
      eventType: 'archive_changed',
      meta: {'is_archived': false},
    );
  }

  static Future<void> deleteAdminTask(String taskId) async {
    await _supabase.from('worker_tasks').delete().eq('id', taskId);
  }

  static Future<void> autoArchiveOldDoneTasks({
    int olderThanDays = 3,
  }) async {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return;

    final rows = await _supabase
        .from('worker_tasks')
        .select('id, status, completed_at, is_archived, admin_auth_id')
        .eq('admin_auth_id', adminId)
        .eq('is_archived', false)
        .eq('status', 'done');

    final now = DateTime.now().toUtc();
    final cutoff = now.subtract(Duration(days: olderThanDays));

    for (final raw in (rows as List)) {
      final task = Map<String, dynamic>.from(raw as Map);

      final completedAt =
      DateTime.tryParse(_s(task['completed_at']))?.toUtc();

      if (completedAt == null) continue;

      if (completedAt.isBefore(cutoff)) {
        await _supabase
            .from('worker_tasks')
            .update({'is_archived': true})
            .eq('id', _s(task['id']));
      }
    }
  }

  // =========================================================
  // TASKS - WORKER
  // =========================================================

  static Future<List<Map<String, dynamic>>> fetchWorkerTasks({
    bool includeArchived = false,
  }) async {
    final workerAuthId = _supabase.auth.currentUser?.id;
    if (workerAuthId == null) return [];

    var query = _supabase
        .from('worker_tasks')
        .select()
        .eq('worker_auth_id', workerAuthId);

    if (!includeArchived) {
      query = query.eq('is_archived', false);
    }

    final rows = await query
        .order('sort_order', ascending: true)
        .order('created_at', ascending: false);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> watchWorkerTasks({
    bool includeArchived = false,
  }) {
    final workerAuthId = _supabase.auth.currentUser?.id;
    if (workerAuthId == null) return Stream.value(const <Map<String, dynamic>>[]);

    return _supabase
        .from('worker_tasks')
        .stream(primaryKey: ['id'])
        .map((rows) {
      final list = rows
          .map((e) => Map<String, dynamic>.from(e))
          .where((e) => _s(e['worker_auth_id']) == workerAuthId)
          .where((e) => includeArchived || e['is_archived'] == false)
          .where((e) {
        final status = _s(e['status']).toLowerCase();
        final isTerminal = status == 'done' || status == 'cancelled';
        final acknowledged = _s(e['worker_acknowledged_at']).isNotEmpty;
        return !(isTerminal && acknowledged);
      })
          .toList();

      list.sort((a, b) {
        final aSort = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bSort = (b['sort_order'] as num?)?.toInt() ?? 0;
        if (aSort != bSort) return aSort.compareTo(bSort);

        final aCreated = DateTime.tryParse(_s(a['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = DateTime.tryParse(_s(b['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bCreated.compareTo(aCreated);
      });

      return list;
    });
  }

  static Future<void> updateWorkerTask({
    required String taskId,
    required String status,
    String? workerNote,
  }) async {
    final existing = await _fetchTaskById(taskId);
    if (existing == null) {
      throw Exception('Task not found');
    }

    final cleanStatus = status.trim();
    final cleanWorkerNote = _nullableTrim(workerNote);

    await _supabase.from('worker_tasks').update({
      'status': cleanStatus,
      'worker_note': cleanWorkerNote,
      'completed_at': cleanStatus == 'done'
          ? DateTime.now().toUtc().toIso8601String()
          : null,
    }).eq('id', taskId);

    if (_s(existing['status']).toLowerCase() != cleanStatus.toLowerCase()) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'worker',
        eventType: 'status_changed',
        meta: {'status': cleanStatus},
      );
    }

    if (!_sameNullableText(_s(existing['worker_note']), cleanWorkerNote)) {
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: 'worker',
        eventType: 'note_changed',
        meta: {'has_note': cleanWorkerNote != null},
      );
    }

    final changedParts = <String>[];

    if (_s(existing['status']).toLowerCase() != cleanStatus.toLowerCase()) {
      changedParts.add('status ${_prettyStatus(cleanStatus)}');
    }

    if (!_sameNullableText(_s(existing['worker_note']), cleanWorkerNote)) {
      changedParts.add('note');
    }

    if (changedParts.isNotEmpty) {
      final workerName = await _workerDisplayName(_s(existing['worker_auth_id']));

      final statusWasChanged =
          _s(existing['status']).toLowerCase() != cleanStatus.toLowerCase();

      await _pushTaskToAdmin(
        task: existing,
        title: statusWasChanged
            ? _taskPushTitleForStatus(
          status: cleanStatus,
          workerName: workerName,
        )
            : _taskPushTitleForUpdate(
          changedParts: changedParts,
          workerName: workerName,
        ),
        body: statusWasChanged
            ? _taskPushStatusBody(
          taskTitle: _s(existing['title']),
          status: cleanStatus,
        )
            : '${_s(existing['title'])} • ${changedParts.join(', ')}',
        eventType: statusWasChanged ? 'status_changed' : 'worker_task_updated',
        extraData: {
          'worker_auth_id': _s(existing['worker_auth_id']),
          'status': cleanStatus,
        },
      );
    }
  }

  static Future<void> acknowledgeWorkerTerminalTask({
    required String taskId,
  }) async {
    final uid = _supabase.auth.currentUser?.id;
    debugPrint('ACK TASK -> taskId=$taskId');
    debugPrint('ACK TASK -> currentUser=$uid');

    final result = await _supabase
        .from('worker_tasks')
        .update({
      'worker_acknowledged_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', taskId)
        .select();

    debugPrint('ACK TASK -> result=$result');
  }

  static Future<void> setTaskSubtaskStatus({
    required String subtaskId,
    required String status,
    String? note,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final existingSubtask = await _fetchSubtaskById(subtaskId);
    if (existingSubtask == null) {
      throw Exception('Checklist item not found');
    }

    final taskId = _s(existingSubtask['task_id']);
    final task = taskId.isEmpty ? null : await _fetchTaskById(taskId);

    final now = DateTime.now().toUtc().toIso8601String();
    final cleanStatus = status.trim().toLowerCase();
    final cleanNote = _nullableTrim(note);

    await _supabase.from('task_subtasks').update({
      'status': cleanStatus,
      'status_note': cleanNote,
      'is_done': cleanStatus == 'done',
      'done_at': cleanStatus == 'done' ? now : null,
      'done_by_auth_id': cleanStatus == 'done' ? userId : null,
      'status_updated_at': now,
      'status_set_by_auth_id': userId,
      'updated_at': now,
    }).eq('id', subtaskId);

    if (task == null) return;

    final actorRole = await _resolveActorRoleForTask(taskId);
    final subtaskTitle = _s(existingSubtask['title']);
    final prettyStatus = _prettyStatus(cleanStatus);

    await _insertTaskEvent(
      taskId: taskId,
      actorRole: actorRole,
      eventType: 'subtask_status_changed',
      meta: {
        'subtask_id': subtaskId,
        'subtask_title': subtaskTitle,
        'status': cleanStatus,
        'has_note': cleanNote != null,
      },
    );

    if (actorRole == 'worker') {
      final workerName = await _workerDisplayName(_s(task['worker_auth_id']));

      await _pushTaskToAdmin(
        task: task,
        title: 'Task • Checklist updated by $workerName',
        body: '$subtaskTitle • $prettyStatus',
        eventType: 'subtask_status_changed',
        extraData: {
          'subtask_id': subtaskId,
          'status': cleanStatus,
          'worker_auth_id': _s(task['worker_auth_id']),
        },
      );
    } else if (actorRole == 'admin') {
      await _pushTaskToWorker(
        task: task,
        title: 'Task • Checklist updated',
        body: '$subtaskTitle • $prettyStatus',
        eventType: 'subtask_status_changed',
        extraData: {
          'subtask_id': subtaskId,
          'status': cleanStatus,
        },
      );
    }
  }

  // =========================================================
  // SUBTASKS
  // =========================================================

  static Future<List<Map<String, dynamic>>> fetchTaskSubtasks(
      String taskId,
      ) async {
    final rows = await _supabase
        .from('task_subtasks')
        .select()
        .eq('task_id', taskId)
        .order('sort_order', ascending: true)
        .order('created_at', ascending: true);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> watchTaskSubtasks(
      String taskId,
      ) {
    return _supabase
        .from('task_subtasks')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => _s(e['task_id']) == taskId)
        .toList()
      ..sort((a, b) {
        final aSort = (a['sort_order'] as num?)?.toInt() ?? 0;
        final bSort = (b['sort_order'] as num?)?.toInt() ?? 0;
        if (aSort != bSort) return aSort.compareTo(bSort);

        final aCreated = DateTime.tryParse(_s(a['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = DateTime.tryParse(_s(b['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return aCreated.compareTo(bCreated);
      }));
  }

  static Future<void> replaceTaskSubtasks({
    required String taskId,
    required List<String> items,
  }) async {
    final existingItems = await fetchTaskSubtasks(taskId);

    await _supabase.from('task_subtasks').delete().eq('task_id', taskId);

    final cleanItems = items
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();

    if (cleanItems.isNotEmpty) {
      await _supabase.from('task_subtasks').insert(
        List.generate(cleanItems.length, (index) {
          return {
            'task_id': taskId,
            'title': cleanItems[index],
            'sort_order': index,
            'is_done': false,
            'status': 'todo',
            'status_note': null,
            'status_updated_at': null,
            'status_set_by_auth_id': null,
          };
        }),
      );
    }

    final previousTitles = existingItems.map((e) => _s(e['title'])).where((e) => e.isNotEmpty).toList();
    if (!_sameChecklist(previousTitles, cleanItems)) {
      final actorRole = await _resolveActorRoleForTask(taskId);
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: actorRole,
        eventType: 'checklist_changed',
        meta: {
          'items_count': cleanItems.length,
          'completed_count': 0,
        },
      );
    }
  }

  static Future<void> toggleTaskSubtask({
    required String subtaskId,
    required bool isDone,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final existing = await _fetchSubtaskById(subtaskId);
    if (existing == null) {
      throw Exception('Checklist item not found');
    }

    final taskId = _s(existing['task_id']);
    final oldDone = existing['is_done'] == true;
    final now = DateTime.now().toUtc().toIso8601String();

    await _supabase.from('task_subtasks').update({
      'is_done': isDone,
      'status': isDone ? 'done' : 'todo',
      'status_note': null,
      'done_at': isDone ? now : null,
      'done_by_auth_id': isDone ? userId : null,
      'status_updated_at': now,
      'status_set_by_auth_id': userId,
      'updated_at': now,
    }).eq('id', subtaskId);

    if (oldDone != isDone) {
      final actorRole = await _resolveActorRoleForTask(taskId);
      await _insertTaskEvent(
        taskId: taskId,
        actorRole: actorRole,
        eventType: 'subtask_toggled',
        meta: {
          'subtask_id': subtaskId,
          'subtask_title': _s(existing['title']),
          'is_done': isDone,
        },
      );
    }
  }

  // =========================================================
  // EVENTS
  // =========================================================

  static Stream<int> watchAdminTaskUnseenCount() {
    final adminId = _supabase.auth.currentUser?.id;
    if (adminId == null) return Stream.value(0);

    return watchAdminTasks(includeArchived: true).asyncExpand((tasks) {
      final taskIds = tasks
          .map((e) => _s(e['id']))
          .where((e) => e.isNotEmpty)
          .toSet();

      if (taskIds.isEmpty) return Stream.value(0);

      return _supabase
          .from('task_events')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) {
        return rows.where((e) {
          final map = Map<String, dynamic>.from(e);
          return taskIds.contains(_s(map['task_id'])) &&
              map['seen_by_admin_at'] == null &&
              _s(map['actor_role']).toLowerCase() != 'admin';
        }).length;
      });
    });
  }

  static Stream<int> watchWorkerTaskUnseenCount() {
    final workerId = _supabase.auth.currentUser?.id;
    if (workerId == null) return Stream.value(0);

    bool isVisibleTask(Map<String, dynamic> task) {
      final status = _s(task['status']).toLowerCase();

      if (status == 'done') {
        final completedAt = DateTime.tryParse(_s(task['completed_at']))?.toLocal();
        if (completedAt != null) {
          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);
          final completedDay = DateTime(
            completedAt.year,
            completedAt.month,
            completedAt.day,
          );

          if (completedDay != today) return false;
        }
      }

      final due = DateTime.tryParse(_s(task['due_at']))?.toLocal();
      if (due != null && due.isBefore(DateTime.now())) {
        return false;
      }

      return true;
    }

    return watchWorkerTasks(includeArchived: true).asyncExpand((tasks) {
      final taskIds = tasks
          .where(isVisibleTask)
          .map((e) => _s(e['id']))
          .where((e) => e.isNotEmpty)
          .toSet();

      if (taskIds.isEmpty) return Stream.value(0);

      return _supabase
          .from('task_events')
          .stream(primaryKey: ['id'])
          .order('created_at', ascending: false)
          .map((rows) {
        return rows.where((e) {
          final map = Map<String, dynamic>.from(e);
          return taskIds.contains(_s(map['task_id'])) &&
              map['seen_by_worker_at'] == null &&
              _s(map['actor_role']).toLowerCase() != 'worker';
        }).length;
      });
    });
  }

  static Future<List<Map<String, dynamic>>> fetchTaskEvents(
    String taskId, {
    int limit = 50,
  }) async {
    final rows = await _supabase
        .from('task_events')
        .select()
        .eq('task_id', taskId)
        .order('created_at', ascending: false)
        .limit(limit);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> watchTaskEvents(String taskId) {
    return _supabase
        .from('task_events')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
                .map((e) => Map<String, dynamic>.from(e))
                .where((e) => _s(e['task_id']) == taskId)
                .toList()
              ..sort((a, b) {
                final aCreated = DateTime.tryParse(_s(a['created_at'])) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                final bCreated = DateTime.tryParse(_s(b['created_at'])) ??
                    DateTime.fromMillisecondsSinceEpoch(0);
                return bCreated.compareTo(aCreated);
              }));
  }

  static Future<void> markAllAdminTaskEventsSeen() async {
    final taskIds = await _fetchAdminTaskIds(includeArchived: true);
    await markAdminTaskEventsSeen(taskIds: taskIds);
  }

  static Future<void> markAllWorkerTaskEventsSeen() async {
    final taskIds = await _fetchWorkerTaskIds(includeArchived: true);
    await markWorkerTaskEventsSeen(taskIds: taskIds);
  }

  static Future<void> markAdminTaskEventsSeen({
    required List<String> taskIds,
  }) async {
    final mergedTaskIds = {
      ...taskIds.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
      ...await _fetchAdminTaskIds(includeArchived: true),
    }.toList();

    if (mergedTaskIds.isEmpty) return;

    await _supabase
        .from('task_events')
        .update({'seen_by_admin_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('task_id', mergedTaskIds)
        .isFilter('seen_by_admin_at', null);
  }

  static Future<void> markWorkerTaskEventsSeen({
    required List<String> taskIds,
  }) async {
    final mergedTaskIds = {
      ...taskIds.where((e) => e.trim().isNotEmpty).map((e) => e.trim()),
      ...await _fetchWorkerTaskIds(includeArchived: true),
    }.toList();

    if (mergedTaskIds.isEmpty) return;

    await _supabase
        .from('task_events')
        .update({'seen_by_worker_at': DateTime.now().toUtc().toIso8601String()})
        .inFilter('task_id', mergedTaskIds)
        .isFilter('seen_by_worker_at', null);
  }

  // =========================================================
  // ATTACHMENTS
  // =========================================================

  static Future<List<Map<String, dynamic>>> fetchTaskAttachments(
      String taskId,
      ) async {
    final rows = await _supabase
        .from('task_attachments')
        .select()
        .eq('task_id', taskId)
        .order('created_at', ascending: true);

    return (rows as List)
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList();
  }

  static Stream<List<Map<String, dynamic>>> watchTaskAttachments(
      String taskId,
      ) {
    return _supabase
        .from('task_attachments')
        .stream(primaryKey: ['id'])
        .map((rows) => rows
        .map((e) => Map<String, dynamic>.from(e))
        .where((e) => _s(e['task_id']) == taskId)
        .toList()
      ..sort((a, b) {
        final aCreated = DateTime.tryParse(_s(a['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bCreated = DateTime.tryParse(_s(b['created_at'])) ??
            DateTime.fromMillisecondsSinceEpoch(0);
        return aCreated.compareTo(bCreated);
      }));
  }

  static Future<void> deleteTaskAttachment(
      Map<String, dynamic> attachment,
      ) async {
    final attachmentId = _s(attachment['id']);
    if (attachmentId.isEmpty) {
      throw Exception('Attachment id is required');
    }

    final mediaPath = _s(attachment['media_path']);

    if (mediaPath.isNotEmpty) {
      try {
        await _supabase.storage.from('task-media').remove([mediaPath]);
      } catch (_) {}
    }

    await _supabase
        .from('task_attachments')
        .delete()
        .eq('id', attachmentId);
  }

  static Future<XFile?> pickTaskImageFromGallery() async {
    return _picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 82,
    );
  }

  static Future<XFile?> pickTaskImageFromCamera() async {
    return _picker.pickImage(
      source: ImageSource.camera,
      imageQuality: 82,
    );
  }

  static Future<PlatformFile?> pickTaskFile() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      type: FileType.any,
    );

    if (result == null || result.files.isEmpty) return null;
    return result.files.first;
  }

  static Future<Map<String, dynamic>> _uploadTaskImage(XFile file) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

    final bytes = await file.readAsBytes();
    final originalName = file.name.trim().isEmpty ? 'image.jpg' : file.name.trim();
    final ext = p.extension(originalName).toLowerCase().replaceFirst('.', '');
    final safeExt = ext.isEmpty ? 'jpg' : ext;
    final fileName =
        '${DateTime.now().millisecondsSinceEpoch}_${userId.substring(0, 8)}.$safeExt';
    final path = 'tasks/$userId/$fileName';

    await _supabase.storage.from('task-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _guessImageMime(safeExt),
      ),
    );

    final publicUrl = _supabase.storage.from('task-media').getPublicUrl(path);

    return {
      'media_url': publicUrl,
      'media_path': path,
      'file_name': originalName,
      'mime_type': _guessImageMime(safeExt),
      'file_size': bytes.length,
      'attachment_type': 'image',
    };
  }

  static Future<Map<String, dynamic>> _uploadTaskFile(PlatformFile file) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated user');

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

    final path = 'tasks/$userId/files/$fileName';

    await _supabase.storage.from('task-media').uploadBinary(
      path,
      bytes,
      fileOptions: FileOptions(
        upsert: false,
        contentType: _guessFileMime(safeExt),
      ),
    );

    final publicUrl = _supabase.storage.from('task-media').getPublicUrl(path);

    return {
      'media_url': publicUrl,
      'media_path': path,
      'file_name': originalName,
      'mime_type': _guessFileMime(safeExt),
      'file_size': bytes.length,
      'attachment_type': 'file',
    };
  }

  static Future<void> addAdminTaskImage({
    required String taskId,
    required XFile file,
    String? proofSubtaskId,
    String? proofKind,
    Map<String, dynamic>? proofMeta,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated admin');

    final upload = await _uploadTaskImage(file);

    await _supabase.from('task_attachments').insert({
      'task_id': taskId,
      'uploaded_by_auth_id': userId,
      'uploaded_by_role': 'admin',
      'attachment_type': 'image',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      if (proofSubtaskId != null && proofSubtaskId.trim().isNotEmpty)
        'proof_subtask_id': proofSubtaskId.trim(),
      if (proofKind != null && proofKind.trim().isNotEmpty)
        'proof_kind': proofKind.trim(),
      if (proofMeta != null && proofMeta.isNotEmpty)
        'proof_meta': proofMeta,
    });

    await _notifyTaskAttachmentUploaded(
      taskId: taskId,
      uploadedByRole: 'admin',
      attachmentType: 'image',
      upload: upload,
      proofSubtaskId: proofSubtaskId,
      proofKind: proofKind,
      proofMeta: proofMeta,
    );
  }

  static Future<void> addWorkerTaskImage({
    required String taskId,
    required XFile file,
    String? proofSubtaskId,
    String? proofKind,
    Map<String, dynamic>? proofMeta,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated worker');

    final upload = await _uploadTaskImage(file);

    await _supabase.from('task_attachments').insert({
      'task_id': taskId,
      'uploaded_by_auth_id': userId,
      'uploaded_by_role': 'worker',
      'attachment_type': 'image',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      if (proofSubtaskId != null && proofSubtaskId.trim().isNotEmpty)
        'proof_subtask_id': proofSubtaskId.trim(),
      if (proofKind != null && proofKind.trim().isNotEmpty)
        'proof_kind': proofKind.trim(),
      if (proofMeta != null && proofMeta.isNotEmpty)
        'proof_meta': proofMeta,
    });

    await _notifyTaskAttachmentUploaded(
      taskId: taskId,
      uploadedByRole: 'worker',
      attachmentType: 'image',
      upload: upload,
      proofSubtaskId: proofSubtaskId,
      proofKind: proofKind,
      proofMeta: proofMeta,
    );
  }

  static Future<void> addAdminTaskFile({
    required String taskId,
    required PlatformFile file,
    String? proofSubtaskId,
    String? proofKind,
    Map<String, dynamic>? proofMeta,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated admin');

    final upload = await _uploadTaskFile(file);

    await _supabase.from('task_attachments').insert({
      'task_id': taskId,
      'uploaded_by_auth_id': userId,
      'uploaded_by_role': 'admin',
      'attachment_type': 'file',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      if (proofSubtaskId != null && proofSubtaskId.trim().isNotEmpty)
        'proof_subtask_id': proofSubtaskId.trim(),
      if (proofKind != null && proofKind.trim().isNotEmpty)
        'proof_kind': proofKind.trim(),
      if (proofMeta != null && proofMeta.isNotEmpty)
        'proof_meta': proofMeta,
    });

    await _notifyTaskAttachmentUploaded(
      taskId: taskId,
      uploadedByRole: 'admin',
      attachmentType: 'file',
      upload: upload,
      proofSubtaskId: proofSubtaskId,
      proofKind: proofKind,
      proofMeta: proofMeta,
    );
  }

  static Future<void> addWorkerTaskFile({
    required String taskId,
    required PlatformFile file,
    String? proofSubtaskId,
    String? proofKind,
    Map<String, dynamic>? proofMeta,
  }) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) throw Exception('No authenticated worker');

    final upload = await _uploadTaskFile(file);

    await _supabase.from('task_attachments').insert({
      'task_id': taskId,
      'uploaded_by_auth_id': userId,
      'uploaded_by_role': 'worker',
      'attachment_type': 'file',
      'media_url': upload['media_url'],
      'media_path': upload['media_path'],
      'file_name': upload['file_name'],
      'mime_type': upload['mime_type'],
      'file_size': upload['file_size'],
      if (proofSubtaskId != null && proofSubtaskId.trim().isNotEmpty)
        'proof_subtask_id': proofSubtaskId.trim(),
      if (proofKind != null && proofKind.trim().isNotEmpty)
        'proof_kind': proofKind.trim(),
      if (proofMeta != null && proofMeta.isNotEmpty)
        'proof_meta': proofMeta,
    });

    await _notifyTaskAttachmentUploaded(
      taskId: taskId,
      uploadedByRole: 'worker',
      attachmentType: 'file',
      upload: upload,
      proofSubtaskId: proofSubtaskId,
      proofKind: proofKind,
      proofMeta: proofMeta,
    );
  }

  // =========================================================
  // HELPERS
  // =========================================================

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