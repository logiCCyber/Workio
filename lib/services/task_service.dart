import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';

class TaskService {
  TaskService();

  static final SupabaseClient _supabase = Supabase.instance.client;
  static final ImagePicker _picker = ImagePicker();

  static String _s(Object? v) => (v ?? '').toString().trim();

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
    return;
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
      payload['status'] = cleanStatus;
      payload['completed_at'] =
          cleanStatus == 'done' ? DateTime.now().toUtc().toIso8601String() : null;
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

    await _supabase.from('task_subtasks').update({
      'is_done': isDone,
      'done_at': isDone ? DateTime.now().toUtc().toIso8601String() : null,
      'done_by_auth_id': isDone ? userId : null,
      'updated_at': DateTime.now().toUtc().toIso8601String(),
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

    return watchWorkerTasks(includeArchived: true).asyncExpand((tasks) {
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