import 'dart:ui';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/cupertino.dart';

import '../services/task_service.dart';

class AdminTasksScreen extends StatefulWidget {
  const AdminTasksScreen({super.key});

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
  String _workerFilterId = '';
  String _workerFilterName = 'All workers';
  String _statusFilter = 'all';

  Timer? _refreshTimer;

  final Map<String, bool> _expandedSubtasks = {};

  bool _showArchived = false;

  IconData _taskStatusIcon(String v) {
    switch (v) {
      case 'done':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.timelapse_rounded;
      case 'needs_review':
        return Icons.rate_review_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  String _s(Object? v) => (v ?? '').toString().trim();

  String _uploadedByLabel(Map<String, dynamic> attachment) {
    final role = _s(attachment['uploaded_by_role']).toLowerCase();

    if (role == 'admin') return 'Uploaded by Admin';
    if (role == 'worker') return 'Uploaded by Worker';

    return 'Uploaded';
  }

  OverlayEntry? _taskToastEntry;

  void _hideTaskToast() {
    _taskToastEntry?.remove();
    _taskToastEntry = null;
  }

  void _showTaskToast(
      String message, {
        IconData? icon,
        Color? accent,
        Duration duration = const Duration(milliseconds: 2200),
      }) {
    if (!mounted) return;

    _hideTaskToast();

    final overlay = Overlay.of(context, rootOverlay: true);
    if (overlay == null) return;

    final media = MediaQuery.of(context);
    final resolvedAccent = accent ?? _TaskPalette.green;
    final resolvedIcon = icon ?? Icons.check_circle_rounded;

    _taskToastEntry = OverlayEntry(
      builder: (_) {
        return Positioned(
          left: 14,
          right: 14,
          bottom: media.padding.bottom + 18,
          child: IgnorePointer(
            ignoring: true,
            child: Material(
              color: Colors.transparent,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 18, end: 0),
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                builder: (context, value, child) {
                  return Transform.translate(
                    offset: Offset(0, value),
                    child: child,
                  );
                },
                child: Container(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF232833).withOpacity(0.98),
                        const Color(0xFF1A1F28).withOpacity(0.99),
                        const Color(0xFF141922).withOpacity(0.99),
                      ],
                    ),
                    border: Border.all(
                      color: resolvedAccent.withOpacity(0.34),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: resolvedAccent.withOpacity(0.20),
                        blurRadius: 20,
                        spreadRadius: -6,
                        offset: const Offset(0, 8),
                      ),
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
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(13),
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              resolvedAccent,
                              resolvedAccent.withOpacity(0.78),
                            ],
                          ),
                        ),
                        child: Icon(
                          resolvedIcon,
                          color: Colors.white,
                          size: 19,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          message,
                          style: const TextStyle(
                            color: _TaskPalette.textMain,
                            fontWeight: FontWeight.w800,
                            fontSize: 13.4,
                            height: 1.25,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );

    overlay.insert(_taskToastEntry!);

    Future.delayed(duration, () {
      _hideTaskToast();
    });
  }


  bool _isRecentlyCompletedTask(Map<String, dynamic> task) {
    final status = _s(task['status']).toLowerCase();
    if (status != 'done') return false;

    final completedAt = DateTime.tryParse(_s(task['completed_at']))?.toLocal();
    if (completedAt == null) return false;

    final now = DateTime.now();
    final cutoff = now.subtract(const Duration(days: 3));

    return completedAt.isAfter(cutoff);
  }

  void _toggleArchivedMode() {
    setState(() {
      _showArchived = !_showArchived;
      _statusFilter = 'all';
    });
  }

  @override
  void initState() {
    super.initState();
    _markAllAdminTaskEventsSeen();
    _runAutoArchive();

    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _hideTaskToast();
    super.dispose();
  }

  Future<void> _markAllAdminTaskEventsSeen() async {
    try {
      final allTasks = await TaskService.fetchAdminTasks(
        includeArchived: true,
      );

      final taskIds = allTasks
          .map((e) => _s(e['id']))
          .where((e) => e.isNotEmpty)
          .toList();

      if (taskIds.isEmpty) return;

      await TaskService.markAdminTaskEventsSeen(
        taskIds: taskIds,
      );
    } catch (_) {}
  }

  String _workerMode(Map<String, dynamic> w) {
    final raw = (w['access_mode'] ?? 'active')
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (raw == 'readonly' ||
        raw == 'read_only' ||
        raw == 'viewonly' ||
        raw == 'view_only') {
      return 'view_only';
    }

    return raw;
  }

  bool _isAssignableWorker(Map<String, dynamic> w) {
    final mode = _workerMode(w);
    final isActive = w['is_active'] == true;

    if (!isActive) return false;
    if (mode == 'suspended') return false;
    if (mode == 'view_only') return false;

    return true;
  }

  bool _isVisibleWorkerForPicker(Map<String, dynamic> w) {
    final mode = _workerMode(w);
    final isActive = w['is_active'] == true;

    if (!isActive) return false;
    if (mode == 'suspended') return false;

    return true;
  }

  Future<void> _runAutoArchive() async {
    try {
      await TaskService.autoArchiveOldDoneTasks(
        olderThanDays: 3,
      );

      if (!mounted) return;
      setState(() {});
    } catch (_) {}
  }

  Future<void> _openWorkerFilterPicker() async {
    try {
      final workers = (await TaskService.fetchAdminWorkers())
          .where(_isVisibleWorkerForPicker)
          .toList();

      if (!mounted) return;

      final selected = await showModalBottomSheet<Map<String, dynamic>?>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _AdminTaskWorkerPickerSheet(
          workers: workers,
          allowAll: true,
        ),
      );

      if (!mounted || selected == null) return;

      setState(() {
        _workerFilterId = _s(selected['id']);
        _workerFilterName = _workerFilterId.isEmpty
            ? 'All workers'
            : (_s(selected['name']).isEmpty ? 'Worker' : _s(selected['name']));
      });
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Filter error: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  DateTime? _dueDay(Object? v) {
    final s = _s(v);
    if (s.isEmpty) return null;

    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return null;

    return DateTime(dt.year, dt.month, dt.day);
  }

  String _groupTitle(String key) {
    if (key == 'no_due') return 'No due date';

    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final tomorrow = today.add(const Duration(days: 1));

    final day = DateTime.parse(key);

    if (day == today) return 'Today';
    if (day == tomorrow) return 'Tomorrow';

    return DateFormat('EEE, MMM d').format(day);
  }

  int _groupRank(String key) {
    if (key == 'no_due') return 4;

    final todayNow = DateTime.now();
    final today = DateTime(todayNow.year, todayNow.month, todayNow.day);
    final tomorrow = today.add(const Duration(days: 1));
    final day = DateTime.parse(key);

    if (day == today) return 0;
    if (day == tomorrow) return 1;
    if (day.isAfter(tomorrow)) return 2;
    return 3; // прошлые даты
  }

  List<_TaskDayGroup> _groupTasksByDay(List<Map<String, dynamic>> tasks) {
    final map = <String, List<Map<String, dynamic>>>{};

    for (final task in tasks) {
      final dueDay = _dueDay(task['due_at']);
      final key = dueDay == null ? 'no_due' : DateFormat('yyyy-MM-dd').format(dueDay);
      (map[key] ??= []).add(task);
    }

    final keys = map.keys.toList()
      ..sort((a, b) {
        final ra = _groupRank(a);
        final rb = _groupRank(b);
        if (ra != rb) return ra.compareTo(rb);

        if (a == 'no_due' && b == 'no_due') return 0;
        if (a == 'no_due') return 1;
        if (b == 'no_due') return -1;

        final ad = DateTime.parse(a);
        final bd = DateTime.parse(b);

        // будущие даты — по возрастанию
        if (_groupRank(a) == 2) return ad.compareTo(bd);

        // прошлые даты — самые свежие выше
        if (_groupRank(a) == 3) return bd.compareTo(ad);

        return ad.compareTo(bd);
      });

    final groups = <_TaskDayGroup>[];

    for (final key in keys) {
      final list = [...map[key]!];

      list.sort((a, b) {
        final ad = DateTime.tryParse(_s(a['due_at']))?.toLocal();
        final bd = DateTime.tryParse(_s(b['due_at']))?.toLocal();

        if (ad != null && bd != null) return ad.compareTo(bd);
        if (ad != null) return -1;
        if (bd != null) return 1;

        final ac = DateTime.tryParse(_s(a['created_at']))?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0);
        final bc = DateTime.tryParse(_s(b['created_at']))?.toLocal() ??
            DateTime.fromMillisecondsSinceEpoch(0);

        return bc.compareTo(ac);
      });

      groups.add(
        _TaskDayGroup(
          key: key,
          title: _groupTitle(key),
          tasks: list,
        ),
      );
    }

    return groups;
  }

  Future<void> _createTask() async {
    try {
      final workers = (await TaskService.fetchAdminWorkers())
          .where(_isAssignableWorker)
          .toList();

      if (!mounted) return;

      if (workers.isEmpty) {
        _showTaskToast(
          'No workers available',
          icon: Icons.group_off_rounded,
          accent: _TaskPalette.orange,
        );
        return;
      }

      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _CreateTaskSheet(
          workers: workers,
          onSubmitTask: (payload) async {
            final tasks = (payload['tasks'] as List<dynamic>? ?? const [])
                .whereType<Map<String, dynamic>>()
                .toList();

            if (tasks.isEmpty) {
              throw Exception('No tasks to create');
            }

            for (final task in tasks) {
              final createdTask = await TaskService.createAdminTask(
                workerId: _s(payload['worker_id']),
                workerAuthId: _s(payload['worker_auth_id']),
                title: _s(task['title']),
                description: _s(task['description']).isEmpty
                    ? null
                    : _s(task['description']),
                priority: _s(task['priority']).isEmpty
                    ? 'normal'
                    : _s(task['priority']),
                dueAt: task['due_at'] as DateTime?,
              );

              final taskId = _s(createdTask['id']);
              if (taskId.isEmpty) {
                throw Exception('Task created without id');
              }

              final subtasks =
              TaskService.extractChecklistItems(_s(task['description']));

              await TaskService.replaceTaskSubtasks(
                taskId: taskId,
                items: subtasks,
              );

              final imageFiles =
              (task['image_files'] as List<dynamic>? ?? const [])
                  .whereType<XFile>()
                  .toList();

              for (final image in imageFiles) {
                await TaskService.addAdminTaskImage(
                  taskId: taskId,
                  file: image,
                );
              }

              final docFile = task['doc_file'];
              if (docFile is PlatformFile) {
                await TaskService.addAdminTaskFile(
                  taskId: taskId,
                  file: docFile,
                );
              }
            }

            if (!mounted) return;
            setState(() {});
            _showTaskToast(
              tasks.length == 1 ? 'Task created' : '${tasks.length} tasks created',
              icon: Icons.check_circle_rounded,
              accent: _TaskPalette.green,
            );
          },
        ),
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Create task failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _openAttachmentUrl(String rawUrl) async {
    final url = Uri.tryParse(rawUrl.trim());

    if (url == null) {
      if (!mounted) return;
      _showTaskToast(
        'Invalid file link',
        icon: Icons.link_off_rounded,
        accent: _TaskPalette.orange,
      );
      return;
    }

    final ok = await launchUrl(
      url,
      mode: LaunchMode.externalApplication,
    );

    if (!ok && mounted) {
      _showTaskToast(
        'Could not open file',
        icon: Icons.open_in_new_off_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _addTaskImageFromGallery(String taskId) async {
    try {
      final picker = ImagePicker();
      final files = await picker.pickMultiImage();

      if (files.isEmpty) return;

      final selected = files.take(5).toList();

      for (final file in selected) {
        await TaskService.addAdminTaskImage(
          taskId: taskId,
          file: file,
        );
      }

      if (!mounted) return;
      _showTaskToast(
        selected.length == 1
            ? 'Image uploaded'
            : '${selected.length} images uploaded',
        icon: Icons.image_rounded,
        accent: _TaskPalette.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Image upload failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _addTaskImageFromCamera(String taskId) async {
    try {
      final file = await TaskService.pickTaskImageFromCamera();
      if (file == null) return;

      await TaskService.addAdminTaskImage(
        taskId: taskId,
        file: file,
      );

      if (!mounted) return;
      _showTaskToast(
        'Photo uploaded',
        icon: Icons.photo_camera_rounded,
        accent: _TaskPalette.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Camera upload failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _addTaskFile(String taskId) async {
    try {
      final file = await TaskService.pickTaskFile();
      if (file == null) return;

      await TaskService.addAdminTaskFile(
        taskId: taskId,
        file: file,
      );

      if (!mounted) return;
      _showTaskToast(
        'File uploaded',
        icon: Icons.attach_file_rounded,
        accent: _TaskPalette.blue,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'File upload failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _openImagePreview(String imageUrl) async {
    if (imageUrl.trim().isEmpty) return;

    await showDialog(
      context: context,
      barrierColor: Colors.black.withOpacity(0.88),
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.all(12),
          child: Stack(
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  color: Colors.black,
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4,
                    child: Image.network(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox(
                        height: 240,
                        child: Center(
                          child: Text(
                            'Failed to load image',
                            style: TextStyle(color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Positioned(
                top: 12,
                right: 12,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _deleteAttachment(Map<String, dynamic> attachment) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232833).withOpacity(0.97),
                      const Color(0xFF1A1F28).withOpacity(0.985),
                      const Color(0xFF141922).withOpacity(0.99),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.34),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF6A2B35),
                                Color(0xFF4A1F27),
                              ],
                            ),
                            border: Border.all(
                              color: _TaskPalette.red.withOpacity(0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Delete attachment',
                            style: TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'This file or image will be deleted from the task.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, false),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF2B313D),
                                      Color(0xFF222833),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.close_rounded,
                                      color: Colors.white.withOpacity(0.85),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: _TaskPalette.textMain,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, true),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF7A2433),
                                      Color(0xFF5A1B26),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: _TaskPalette.red.withOpacity(0.24),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _TaskPalette.red.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: -4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
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
          ),
        );
      },
    );

    if (ok != true) return;

    try {
      await TaskService.deleteTaskAttachment(attachment);

      if (!mounted) return;
      _showTaskToast(
        'Attachment deleted',
        icon: Icons.delete_outline_rounded,
        accent: _TaskPalette.red,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Delete attachment failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _openTaskActions(Map<String, dynamic> task) async {
    final taskId = _s(task['id']);
    if (taskId.isEmpty) return;

    final isArchived = task['is_archived'] == true;

    final Map<String, dynamic> worker =
    task['workers'] is Map
        ? Map<String, dynamic>.from(task['workers'] as Map)
        : <String, dynamic>{};

    final workerName =
    _s(worker['name']).isEmpty ? 'Worker' : _s(worker['name']);

    final workerEmail = _s(worker['email']);
    final workerEmailText = workerEmail.isEmpty ? 'No email' : workerEmail;

    final workerNote = _s(task['worker_note']);
    final rawDescription = _s(task['description']);
    final cleanDescription =
    TaskService.stripChecklistFromDescription(rawDescription);
    final status = _s(task['status']).toLowerCase();
    final priority = _s(task['priority']).toLowerCase();

    final dueRaw = _s(task['due_at']);
    final dueText = dueRaw.isEmpty
        ? ''
        : (() {
      final dt = DateTime.tryParse(dueRaw)?.toLocal();
      if (dt == null) return '';
      return DateFormat('MMM d, HH:mm').format(dt);
    })();

    String? selectedProofSubtaskId;
    Map<String, dynamic>? selectedProofAttachment;

    String proofTitle(Map<String, dynamic>? attachment) {
      if (attachment == null) return '';
      final rawMeta = attachment['proof_meta'];
      if (rawMeta is Map) {
        final meta = Map<String, dynamic>.from(rawMeta);
        final title = _s(meta['subtask_title']).isNotEmpty
            ? _s(meta['subtask_title'])
            : _s(meta['item_title']).isNotEmpty
            ? _s(meta['item_title'])
            : _s(meta['title']);
        if (title.isNotEmpty) return title;
      }
      return '';
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final mq = MediaQuery.of(sheetContext);

        return Padding(
          padding: EdgeInsets.fromLTRB(10, 40, 10, 10 + mq.viewInsets.bottom),
          child: StatefulBuilder(
            builder: (context, setSheetState) {
              return ClipRRect(
                borderRadius: BorderRadius.circular(28),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(0, 16, 0, 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(28),
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          const Color(0xFF2A2E35).withOpacity(0.97),
                          const Color(0xFF23272E).withOpacity(0.985),
                          const Color(0xFF1B1F26).withOpacity(0.99),
                        ],
                      ),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.34),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                    child: SingleChildScrollView(
                      clipBehavior: Clip.none,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: const Icon(
                                        Icons.assignment_rounded,
                                        color: _TaskPalette.green,
                                        size: 20,
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            children: [
                                               Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    const Text(
                                                      'Task details',
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: _TaskPalette.textMain,
                                                        fontWeight: FontWeight.w900,
                                                        fontSize: 18,
                                                        height: 1.1,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 2),
                                                    Text(
                                                      workerName,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors.white.withOpacity(0.48),
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 11.4,
                                                        height: 1.0,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius: BorderRadius.circular(999),
                                                  onTap: () => Navigator.pop(sheetContext),
                                                  child: SizedBox(
                                                    width: 34,
                                                    height: 34,
                                                    child: Center(
                                                      child: Icon(
                                                        Icons.close_rounded,
                                                        color: Colors.white.withOpacity(0.72),
                                                        size: 22,
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
                                  ],
                                ),
                                const SizedBox(height: 14),
                              ],
                            ),
                          ),

                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Container(
                              height: 58,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(999),
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    const Color(0xFF151A21).withOpacity(0.98),
                                    const Color(0xFF0F141B).withOpacity(0.98),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.26),
                                    blurRadius: 18,
                                    spreadRadius: -6,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            _taskStatusIcon(status),
                                            size: 14,
                                            color: _taskStatusColor(status),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              status.replaceAll('_', ' '),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.82),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const _TaskMetaDivider(),
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            priority == 'urgent'
                                                ? Icons.priority_high_rounded
                                                : priority == 'high'
                                                ? Icons.keyboard_double_arrow_up_rounded
                                                : priority == 'low'
                                                ? Icons.south_rounded
                                                : Icons.flag_rounded,
                                            size: 14,
                                            color: _taskPriorityColor(priority),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              priority,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: _taskPriorityColor(priority),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  const _TaskMetaDivider(),
                                  Expanded(
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(
                                            Icons.schedule_rounded,
                                            size: 14,
                                            color: Color(0xFFF59E0B),
                                          ),
                                          const SizedBox(width: 6),
                                          Flexible(
                                            child: Text(
                                              dueText.isEmpty ? 'No date' : dueText,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: Colors.white.withOpacity(0.74),
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12.4,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SheetSectionCard(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Center(
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.sell_rounded,
                                          size: 16,
                                          color: Colors.white.withOpacity(0.88),
                                        ),
                                        const SizedBox(width: 8),
                                        Flexible(
                                          child: Text(
                                            _s(task['title']).isEmpty ? 'Task' : _s(task['title']).toUpperCase(),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            textAlign: TextAlign.center,
                                            style: const TextStyle(
                                              color: _TaskPalette.textMain,
                                              fontWeight: FontWeight.w900,
                                              fontSize: 16.8,
                                              height: 1.0,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),

                                  if (cleanDescription.isNotEmpty) ...[
                                    const SizedBox(height: 14),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        const Padding(
                                          padding: EdgeInsets.only(top: 3),
                                          child: Icon(
                                            Icons.notes_rounded,
                                            size: 15,
                                            color: Color(0xFFFACC15),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            cleanDescription,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(0.68),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 13.2,
                                              height: 1.30,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  if (workerNote.isNotEmpty) ...[
                                    const SizedBox(height: 12),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(
                                          Icons.campaign_rounded,
                                          size: 15,
                                          color: const Color(0xFF8EA0FF).withOpacity(0.92),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            workerNote,
                                            style: TextStyle(
                                              color: const Color(0xFFC9D2FF).withOpacity(0.78),
                                              fontWeight: FontWeight.w700,
                                              fontSize: 12.8,
                                              height: 1.30,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],

                                  StreamBuilder<List<Map<String, dynamic>>>(
                                    stream: TaskService.watchTaskSubtasks(taskId),
                                    builder: (context, snapshot) {
                                      final subtasks = snapshot.data ?? const <Map<String, dynamic>>[];
                                      if (subtasks.isEmpty) return const SizedBox.shrink();

                                      final doneCount = subtasks.where((e) => e['is_done'] == true).length;
                                      final totalCount = subtasks.length;
                                      final isAllDone = doneCount == totalCount;
                                      final countColor =
                                      isAllDone ? _TaskPalette.green : const Color(0xFFFB7185);

                                      final selectedProofTitle = proofTitle(selectedProofAttachment);

                                      return Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          const SizedBox(height: 14),
                                          Container(
                                            height: 1,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              gradient: LinearGradient(
                                                colors: [
                                                  Colors.transparent,
                                                  Colors.white.withOpacity(0.10),
                                                  Colors.white.withOpacity(0.05),
                                                  Colors.transparent,
                                                ],
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 14),

                                          if (selectedProofSubtaskId != null) ...[
                                            Container(
                                              width: double.infinity,
                                              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                                              decoration: BoxDecoration(
                                                borderRadius: BorderRadius.circular(14),
                                                gradient: LinearGradient(
                                                  begin: Alignment.topLeft,
                                                  end: Alignment.bottomRight,
                                                  colors: [
                                                    const Color(0xFF2D3138).withOpacity(0.94),
                                                    const Color(0xFF23272E).withOpacity(0.98),
                                                  ],
                                                ),
                                                border: Border.all(
                                                  color: Colors.white.withOpacity(0.08),
                                                ),
                                              ),
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.start,
                                                children: [
                                                  const Padding(
                                                    padding: EdgeInsets.only(top: 1),
                                                    child: Icon(
                                                      Icons.photo_camera_back_rounded,
                                                      color: _TaskPalette.green,
                                                      size: 15,
                                                    ),
                                                  ),
                                                  const SizedBox(width: 8),
                                                  Expanded(
                                                    child: Text(
                                                      selectedProofTitle.isEmpty
                                                          ? 'This photo is linked to a checklist item.'
                                                          : 'This photo is proof for: $selectedProofTitle',
                                                      style: const TextStyle(
                                                        color: _TaskPalette.textMain,
                                                        fontWeight: FontWeight.w800,
                                                        fontSize: 12.2,
                                                        height: 1.28,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                          ],

                                          ...List.generate(subtasks.length, (index) {
                                            final item = subtasks[index];
                                            final itemId = _s(item['id']);
                                            final title = _s(item['title']);

                                            final itemStatus = _s(item['status']).toLowerCase().isEmpty
                                                ? (item['is_done'] == true ? 'done' : 'todo')
                                                : _s(item['status']).toLowerCase();

                                            final statusNote = _s(item['status_note']);
                                            final isExpanded = _expandedSubtasks[itemId] == true;

                                            final bool showArrow = itemStatus == 'blocked' ||
                                                itemStatus == 'not_needed' ||
                                                itemStatus == 'partial';

                                            final isProofTarget =
                                                selectedProofSubtaskId != null && selectedProofSubtaskId == itemId;

                                            IconData statusIcon;
                                            Color statusColor;

                                            switch (itemStatus) {
                                              case 'done':
                                                statusIcon = Icons.task_alt_rounded;
                                                statusColor = _TaskPalette.green;
                                                break;
                                              case 'blocked':
                                                statusIcon = Icons.block_rounded;
                                                statusColor = _TaskPalette.orange;
                                                break;
                                              case 'not_needed':
                                                statusIcon = Icons.remove_circle_outline_rounded;
                                                statusColor = Colors.white.withOpacity(0.72);
                                                break;
                                              case 'partial':
                                                statusIcon = Icons.timelapse_rounded;
                                                statusColor = _TaskPalette.blue;
                                                break;
                                              default:
                                                statusIcon = Icons.radio_button_unchecked_rounded;
                                                statusColor = _TaskPalette.red;
                                            }

                                            return Padding(
                                              padding: EdgeInsets.only(
                                                bottom: index == subtasks.length - 1 ? 0 : 8,
                                              ),
                                              child: Material(
                                                color: Colors.transparent,
                                                child: InkWell(
                                                  borderRadius: BorderRadius.circular(14),
                                                  onTap: showArrow
                                                      ? () {
                                                    setSheetState(() {
                                                      for (final st in subtasks) {
                                                        final id = _s(st['id']);
                                                        if (id.isNotEmpty && id != itemId) {
                                                          _expandedSubtasks[id] = false;
                                                        }
                                                      }

                                                      _expandedSubtasks[itemId] = !isExpanded;
                                                    });
                                                  }
                                                      : null,
                                                  child: Container(
                                                    width: double.infinity,
                                                    padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                                                    decoration: BoxDecoration(
                                                      borderRadius: BorderRadius.circular(14),
                                                      gradient: LinearGradient(
                                                        begin: Alignment.topLeft,
                                                        end: Alignment.bottomRight,
                                                        colors: [
                                                          const Color(0xFF2D3138).withOpacity(0.94),
                                                          const Color(0xFF23272E).withOpacity(0.98),
                                                        ],
                                                      ),
                                                      border: Border.all(
                                                        color: isProofTarget
                                                            ? _TaskPalette.green.withOpacity(0.26)
                                                            : Colors.white.withOpacity(0.07),
                                                      ),
                                                      boxShadow: [
                                                        BoxShadow(
                                                          color: Colors.black.withOpacity(0.14),
                                                          blurRadius: 8,
                                                          spreadRadius: -6,
                                                          offset: const Offset(0, 5),
                                                        ),
                                                      ],
                                                    ),
                                                    child: Column(
                                                      crossAxisAlignment: CrossAxisAlignment.start,
                                                      children: [
                                                        Row(
                                                          crossAxisAlignment: CrossAxisAlignment.center,
                                                          children: [
                                                            Icon(
                                                              statusIcon,
                                                              size: 18,
                                                              color: statusColor,
                                                            ),
                                                            const SizedBox(width: 9),
                                                            Expanded(
                                                              child: Text(
                                                                title,
                                                                style: TextStyle(
                                                                  color: itemStatus == 'done'
                                                                      ? Colors.white.withOpacity(0.68)
                                                                      : Colors.white.withOpacity(0.90),
                                                                  fontWeight: FontWeight.w700,
                                                                  fontSize: 12.8,
                                                                  height: 1.22,
                                                                  decoration: itemStatus == 'done'
                                                                      ? TextDecoration.lineThrough
                                                                      : null,
                                                                  decorationColor: Colors.white.withOpacity(0.42),
                                                                ),
                                                              ),
                                                            ),
                                                            if (showArrow) ...[
                                                              const SizedBox(width: 6),
                                                              Icon(
                                                                isExpanded
                                                                    ? Icons.keyboard_arrow_up_rounded
                                                                    : Icons.keyboard_arrow_down_rounded,
                                                                color: _TaskPalette.green,
                                                                size: 19,
                                                              ),
                                                            ],
                                                          ],
                                                        ),

                                                        AnimatedSwitcher(
                                                          duration: const Duration(milliseconds: 220),
                                                          switchInCurve: Curves.easeOutCubic,
                                                          switchOutCurve: Curves.easeInCubic,
                                                          transitionBuilder: (child, animation) {
                                                            return SizeTransition(
                                                              sizeFactor: animation,
                                                              axisAlignment: -1,
                                                              child: FadeTransition(
                                                                opacity: animation,
                                                                child: child,
                                                              ),
                                                            );
                                                          },
                                                          child: showArrow && isExpanded
                                                              ? Padding(
                                                            key: ValueKey('admin_reason_open_$itemId'),
                                                            padding: const EdgeInsets.only(top: 9),
                                                            child: Container(
                                                              width: double.infinity,
                                                              padding: const EdgeInsets.fromLTRB(4, 8, 4, 2),
                                                              decoration: BoxDecoration(
                                                                border: Border(
                                                                  top: BorderSide(
                                                                    color: Colors.white.withOpacity(0.06),
                                                                  ),
                                                                ),
                                                              ),
                                                              child: Text(
                                                                statusNote.isEmpty
                                                                    ? 'No reason added yet.'
                                                                    : statusNote,
                                                                style: TextStyle(
                                                                  color: statusNote.isEmpty
                                                                      ? Colors.white.withOpacity(0.34)
                                                                      : Colors.white.withOpacity(0.56),
                                                                  fontWeight: FontWeight.w600,
                                                                  fontSize: 11.4,
                                                                  height: 1.28,
                                                                ),
                                                              ),
                                                            ),
                                                          )
                                                              : SizedBox(
                                                            key: ValueKey('admin_reason_closed_$itemId'),
                                                            height: 0,
                                                            width: double.infinity,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  ),
                                                ),
                                              ),
                                            );
                                          }),

                                          const SizedBox(height: 10),

                                          Row(
                                            children: [
                                              const Spacer(),
                                              Text(
                                                '$doneCount/$totalCount',
                                                style: TextStyle(
                                                  color: countColor,
                                                  fontWeight: FontWeight.w900,
                                                  fontSize: 13.2,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ],
                                      );
                                    },
                                  ),
                                ],
                               ),
                             ),
                          ),
                       ),

                    const SizedBox(height: 14),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: StreamBuilder<List<Map<String, dynamic>>>(
                        stream: TaskService.watchTaskAttachments(taskId),
                            builder: (context, snapshot) {
                              if (snapshot.connectionState == ConnectionState.waiting &&
                                  !snapshot.hasData) {
                                return const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 20),
                                  child: Center(
                                    child: SizedBox(
                                      width: 24,
                                      height: 24,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        color: _TaskPalette.green,
                                      ),
                                    ),
                                  ),
                                );
                              }

                              final attachments =
                                  snapshot.data ?? <Map<String, dynamic>>[];

                              if (attachments.isEmpty) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.fromLTRB(18, 22, 18, 22),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(24),
                                    gradient: const LinearGradient(
                                      begin: Alignment.topLeft,
                                      end: Alignment.bottomRight,
                                      colors: [
                                        Color(0xFF2B2F36),
                                        Color(0xFF23272E),
                                        Color(0xFF1C2026),
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
                                  child: Column(
                                    children: [
                                      Container(
                                        width: 54,
                                        height: 54,
                                        decoration: BoxDecoration(
                                          borderRadius: BorderRadius.circular(18),
                                          gradient: const LinearGradient(
                                            begin: Alignment.topCenter,
                                            end: Alignment.bottomCenter,
                                            colors: [
                                              Color(0xFF3A3E46),
                                              Color(0xFF2D3138),
                                            ],
                                          ),
                                          border: Border.all(
                                            color: Colors.white.withOpacity(0.10),
                                          ),
                                          boxShadow: [
                                            BoxShadow(
                                              color: Colors.black.withOpacity(0.20),
                                              blurRadius: 10,
                                              offset: const Offset(0, 5),
                                            ),
                                          ],
                                        ),
                                        child: Icon(
                                          Icons.attach_file_rounded,
                                          size: 26,
                                          color: Colors.white.withOpacity(0.72),
                                        ),
                                      ),
                                      const SizedBox(height: 14),
                                      const Text(
                                        'No attachments yet',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: _TaskPalette.textMain,
                                          fontWeight: FontWeight.w900,
                                          fontSize: 18,
                                          height: 1.05,
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        'Add photos or files for this task.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.56),
                                          fontWeight: FontWeight.w700,
                                          fontSize: 12.8,
                                          height: 1.35,
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final imageAttachments = attachments.where((a) {
                                return _s(a['attachment_type']).toLowerCase() ==
                                    'image' &&
                                    _s(a['media_url']).isNotEmpty;
                              }).toList();

                              final fileAttachments = attachments.where((a) {
                                return _s(a['attachment_type']).toLowerCase() !=
                                    'image';
                              }).toList();

                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  if (imageAttachments.isNotEmpty) ...[
                                    _TaskImageCarousel(
                                      images: imageAttachments,
                                      onOpen: _openImagePreview,
                                      onDelete: (attachment) =>
                                          _deleteAttachment(attachment),
                                      onVisibleImageChanged: (attachment) {
                                        final nextProofId = _s(attachment['proof_subtask_id']);
                                        setSheetState(() {
                                          selectedProofAttachment = Map<String, dynamic>.from(attachment);
                                          selectedProofSubtaskId =
                                          nextProofId.isEmpty ? null : nextProofId;
                                        });
                                      },
                                    ),
                                    const SizedBox(height: 10),
                                  ],

                                  ...fileAttachments.map((attachment) {
                                    final url = _s(attachment['media_url']);
                                    final fileName =
                                    _s(attachment['file_name']).isEmpty
                                        ? 'File'
                                        : _s(attachment['file_name']);
                                    final uploadedBy = _uploadedByLabel(attachment);

                                    final role =
                                    _s(attachment['uploaded_by_role']).toLowerCase();
                                    final accent = role == 'admin'
                                        ? const Color(0xFF7C9BFF)
                                        : role == 'worker'
                                        ? _TaskPalette.green
                                        : Colors.white.withOpacity(0.10);

                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 10),
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(16),
                                        onTap: url.isEmpty
                                            ? null
                                            : () => _openAttachmentUrl(url),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.all(12),
                                          decoration: BoxDecoration(
                                            color: Colors.white.withOpacity(0.04),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: Colors.white.withOpacity(0.08),
                                            ),
                                          ),
                                          child: Row(
                                            crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                            children: [
                                              const Icon(
                                                Icons.insert_drive_file_outlined,
                                                color: Colors.white70,
                                              ),
                                              const SizedBox(width: 10),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                                  children: [
                                                    Text(
                                                      fileName,
                                                      maxLines: 1,
                                                      overflow:
                                                      TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: _TaskPalette.textMain,
                                                        fontWeight: FontWeight.w800,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 3),
                                                    Container(
                                                      padding:
                                                      const EdgeInsets.symmetric(
                                                        horizontal: 8,
                                                        vertical: 4,
                                                      ),
                                                      decoration: BoxDecoration(
                                                        color:
                                                        accent.withOpacity(0.12),
                                                        borderRadius:
                                                        BorderRadius.circular(999),
                                                        border: Border.all(
                                                          color:
                                                          accent.withOpacity(0.28),
                                                        ),
                                                      ),
                                                      child: Text(
                                                        uploadedBy,
                                                        style: TextStyle(
                                                          color: accent,
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 10.8,
                                                          height: 1,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.open_in_new_rounded,
                                                color: Colors.white.withOpacity(0.55),
                                                size: 18,
                                              ),
                                              IconButton(
                                                onPressed: () =>
                                                    _deleteAttachment(attachment),
                                                tooltip: 'Delete attachment',
                                                icon: const Icon(
                                                  Icons.delete_outline_rounded,
                                                  color: Colors.redAccent,
                                                  size: 20,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  }),
                                ],
                              );
                            },
                          ),
                        ),

                          const SizedBox(height: 12),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _SheetSectionCard(
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                                children: [
                                  _MediaCapsuleAction(
                                    label: 'Gallery',
                                    icon: Icons.photo_library_outlined,
                                    iconColor: Colors.white,
                                    onTap: () => _addTaskImageFromGallery(taskId),
                                  ),
                                  const SizedBox(width: 10),
                                  _MediaCapsuleAction(
                                    label: 'Camera',
                                    icon: Icons.photo_camera_outlined,
                                    iconColor: Colors.white,
                                    onTap: () => _addTaskImageFromCamera(taskId),
                                  ),
                                  const SizedBox(width: 10),
                                  _MediaCapsuleAction(
                                    label: 'Attach',
                                    icon: Icons.attach_file_rounded,
                                    iconColor: Colors.white.withOpacity(0.88),
                                    onTap: () => _addTaskFile(taskId),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                          const SizedBox(height: 14),

                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          if (!isArchived) ...[
                                Expanded(
                                  child: _TaskActionCapsule(
                                    label: 'Edit',
                                    icon: Icons.edit_outlined,
                                    onTap: () async {
                                      Navigator.pop(sheetContext);
                                      await _editTask(task);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _TaskActionCapsule(
                                    label: 'Archive',
                                    icon: Icons.archive_outlined,
                                    accentColor: _TaskPalette.green,
                                    onTap: () async {
                                      Navigator.pop(sheetContext);
                                      await _archiveTask(task);
                                    },
                                  ),
                                ),
                              ] else ...[
                                Expanded(
                                  child: _TaskActionCapsule(
                                    label: 'Unarchive',
                                    icon: Icons.unarchive_outlined,
                                    accentColor: const Color(0xFF9AA4B5),
                                    onTap: () async {
                                      Navigator.pop(sheetContext);
                                      await _unarchiveTask(task);
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: _TaskActionCapsule(
                                    label: 'Delete',
                                    icon: Icons.delete_outline_rounded,
                                    accentColor: _TaskPalette.red,
                                    onTap: () async {
                                      Navigator.pop(sheetContext);
                                      await _deleteTask(task);
                                    },
                                  ),
                                ),
                              ],
                            ],
                          ),
                         ),
                      ],
                    ),
                  ),
                ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Color _taskStatusColor(String v) {
    switch (v) {
      case 'done':
        return _TaskPalette.green;
      case 'in_progress':
        return _TaskPalette.blue;
      case 'needs_review':
        return _TaskPalette.orange;
      case 'cancelled':
        return _TaskPalette.red;
      default:
        return Colors.white.withOpacity(0.7);
    }
  }

  Color _taskPriorityColor(String v) {
    switch (v) {
      case 'urgent':
        return _TaskPalette.red;
      case 'high':
        return _TaskPalette.orange;
      case 'low':
        return Colors.white.withOpacity(0.62);
      default:
        return _TaskPalette.blue;
    }
  }

  Future<void> _editTask(Map<String, dynamic> task) async {
    final Map<String, dynamic> worker =
    task['workers'] is Map
        ? Map<String, dynamic>.from(task['workers'] as Map)
        : <String, dynamic>{};

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _EditTaskSheet(
        task: task,
        worker: worker,
        onSubmitTask: (payload) async {
          final oldDescription = _s(task['description']);
          final newDescription = _s(payload['description']);

          final oldChecklist =
          TaskService.extractChecklistItems(oldDescription);
          final newChecklist =
          TaskService.extractChecklistItems(newDescription);

          await TaskService.updateAdminTask(
            taskId: _s(task['id']),
            title: _s(payload['title']),
            description: newDescription.isEmpty ? null : newDescription,
            priority: _s(payload['priority']).isEmpty
                ? 'normal'
                : _s(payload['priority']),
            dueAt: payload['due_at'] as DateTime?,
            status: _s(payload['status']).isEmpty ? null : _s(payload['status']),
          );

          final sameChecklist =
              oldChecklist.length == newChecklist.length &&
                  List.generate(oldChecklist.length, (i) {
                    return oldChecklist[i].trim() == newChecklist[i].trim();
                  }).every((e) => e);

          if (!sameChecklist) {
            await TaskService.replaceTaskSubtasks(
              taskId: _s(task['id']),
              items: newChecklist,
            );
          }

          if (!mounted) return;
          setState(() {});
          _showTaskToast(
            'Task updated',
            icon: Icons.check_circle_rounded,
            accent: _TaskPalette.green,
          );
        },
      ),
    );
  }

  Future<void> _archiveTask(Map<String, dynamic> task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232833).withOpacity(0.97),
                      const Color(0xFF1A1F28).withOpacity(0.985),
                      const Color(0xFF141922).withOpacity(0.99),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.34),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF356657),
                                Color(0xFF274C41),
                              ],
                            ),
                            border: Border.all(
                              color: _TaskPalette.green.withOpacity(0.20),
                            ),
                          ),
                          child: const Icon(
                            Icons.archive_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Archive task',
                            style: TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 1,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.10),
                            Colors.white.withOpacity(0.05),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'The task will be hidden from the active list.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, false),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF2B313D),
                                      Color(0xFF222833),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.close_rounded,
                                      color: Colors.white.withOpacity(0.85),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: _TaskPalette.textMain,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, true),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF356657),
                                      Color(0xFF274C41),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: _TaskPalette.green.withOpacity(0.20),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _TaskPalette.green.withOpacity(0.14),
                                      blurRadius: 12,
                                      spreadRadius: -4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.archive_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Archive',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
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
          ),
        );
      },
    );

    if (ok != true) return;

    try {
      await TaskService.archiveAdminTask(_s(task['id']));
      if (!mounted) return;
      setState(() {});
      _showTaskToast(
        'Task archived',
        icon: Icons.archive_rounded,
        accent: _TaskPalette.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Archive failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _unarchiveTask(Map<String, dynamic> task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232833).withOpacity(0.97),
                      const Color(0xFF1A1F28).withOpacity(0.985),
                      const Color(0xFF141922).withOpacity(0.99),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.34),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF555E6D),
                                Color(0xFF3E4653),
                              ],
                            ),
                            border: Border.all(
                              color: Colors.white24,
                            ),
                          ),
                          child: const Icon(
                            Icons.unarchive_outlined,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Unarchive task',
                            style: TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Container(
                      height: 1,
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            Colors.transparent,
                            Colors.white.withOpacity(0.10),
                            Colors.white.withOpacity(0.05),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'The task will return to the active list.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, false),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF2B313D),
                                      Color(0xFF222833),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.close_rounded,
                                      color: Colors.white.withOpacity(0.85),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: _TaskPalette.textMain,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, true),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF9AA4B5),
                                      Color(0xFF7E889A),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.16),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.08),
                                      blurRadius: 12,
                                      spreadRadius: -4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.unarchive_outlined,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Unarchive',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
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
          ),
        );
      },
    );

    if (ok != true) return;

    try {
      await TaskService.unarchiveAdminTask(_s(task['id']));
      if (!mounted) return;
      setState(() {});
      _showTaskToast(
        'Task moved to active list',
        icon: Icons.unarchive_rounded,
        accent: _TaskPalette.green,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Unarchive failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  Future<void> _deleteTask(Map<String, dynamic> task) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(30),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232833).withOpacity(0.97),
                      const Color(0xFF1A1F28).withOpacity(0.985),
                      const Color(0xFF141922).withOpacity(0.99),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withOpacity(0.08)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.34),
                      blurRadius: 28,
                      offset: const Offset(0, 16),
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 42,
                          height: 42,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFF6A2B35),
                                Color(0xFF4A1F27),
                              ],
                            ),
                            border: Border.all(
                              color: _TaskPalette.red.withOpacity(0.22),
                            ),
                          ),
                          child: const Icon(
                            Icons.delete_outline_rounded,
                            color: Colors.white,
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Delete task',
                            style: TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w900,
                              fontSize: 20,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'This action cannot be undone.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.70),
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        height: 1.35,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, false),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF2B313D),
                                      Color(0xFF222833),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.close_rounded,
                                      color: Colors.white.withOpacity(0.85),
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    const Text(
                                      'Cancel',
                                      style: TextStyle(
                                        color: _TaskPalette.textMain,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Material(
                            color: Colors.transparent,
                            child: InkWell(
                              borderRadius: BorderRadius.circular(20),
                              onTap: () => Navigator.pop(context, true),
                              child: Container(
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(20),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF7A2433),
                                      Color(0xFF5A1B26),
                                    ],
                                  ),
                                  border: Border.all(
                                    color: _TaskPalette.red.withOpacity(0.24),
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: _TaskPalette.red.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: -4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.delete_outline_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Delete',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ],
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
          ),
        );
      },
    );

    if (ok != true) return;

    try {
      await TaskService.deleteAdminTask(_s(task['id']));
      if (!mounted) return;
      setState(() {});
      _showTaskToast(
        'Task deleted',
        icon: Icons.delete_outline_rounded,
        accent: _TaskPalette.red,
      );
    } catch (e) {
      if (!mounted) return;
      _showTaskToast(
        'Delete failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TaskPalette.bg,
      body: Stack(
        children: [
          const _TasksBackground(),
          SafeArea(
            child: StreamBuilder<List<Map<String, dynamic>>>(
              stream: TaskService.watchAdminTasks(
                workerId: _workerFilterId.isEmpty ? null : _workerFilterId,
                includeArchived: true,
              ),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting &&
                    !snapshot.hasData) {
                  return const Center(
                    child: SizedBox(
                      width: 28,
                      height: 28,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: _TaskPalette.green,
                      ),
                    ),
                  );
                }

                final allTasks =
                List<Map<String, dynamic>>.from(snapshot.data ?? const []);

                final activeCount = allTasks.where((t) {
                  final isArchived = t['is_archived'] == true;
                  final status = _s(t['status']).toLowerCase();
                  return !isArchived && status != 'done';
                }).length;

                final doneCount = allTasks.where((t) {
                  final isArchived = t['is_archived'] == true;
                  final status = _s(t['status']).toLowerCase();
                  return !isArchived && status == 'done';
                }).length;

                final archivedCount = allTasks.where((t) {
                  return t['is_archived'] == true;
                }).length;

                if (allTasks.isNotEmpty) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    TaskService.markAdminTaskEventsSeen(
                      taskIds: allTasks
                          .map((e) => _s(e['id']))
                          .where((e) => e.isNotEmpty)
                          .toList(),
                    );
                  });
                }

                var tasks = List<Map<String, dynamic>>.from(allTasks);

                if (_showArchived) {
                  tasks = tasks.where((t) => t['is_archived'] == true).toList();
                } else {
                  tasks = tasks.where((t) => t['is_archived'] != true).toList();
                }

                if (_statusFilter != 'all') {
                  tasks = tasks
                      .where(
                        (t) => _s(t['status']).toLowerCase() == _statusFilter,
                  )
                      .toList();
                }

                List<Map<String, dynamic>> recentDone = [];

                if (!_showArchived) {
                  recentDone = tasks.where(_isRecentlyCompletedTask).toList();
                  tasks =
                      tasks.where((t) => !_isRecentlyCompletedTask(t)).toList();
                }

                final groups = _groupTasksByDay(tasks);
                final hasContent = tasks.isNotEmpty || recentDone.isNotEmpty;

                return ListView(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 18),
                  children: [
                    _AdminTasksTopPanel(
                      title: _showArchived ? 'Archived tasks' : 'Tasks',
                      subtitle:
                      _showArchived ? 'Admin archive' : 'Admin task board',
                      workerFilterName: _workerFilterName,
                      statusFilter: _statusFilter,
                      showArchived: _showArchived,
                      activeCount: activeCount,
                      doneCount: doneCount,
                      archivedCount: archivedCount,
                      onBack: () => Navigator.pop(context),
                      onCreate: _createTask,
                      onWorkerTap: _openWorkerFilterPicker,
                      onStatusChanged: (v) => setState(() => _statusFilter = v),
                      onArchiveChanged: (v) {
                        if (v != _showArchived) {
                          _toggleArchivedMode();
                        }
                      },
                    ),
                    const SizedBox(height: 12),

                    if (!hasContent)
                      Container(
                        padding: const EdgeInsets.fromLTRB(18, 24, 18, 24),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          gradient: const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Color(0xFF2C3038),
                              Color(0xFF232730),
                              Color(0xFF1C2027),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.07),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.24),
                              blurRadius: 16,
                              offset: const Offset(0, 10),
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            SizedBox(
                              width: 54,
                              height: 54,
                              child: Icon(
                                _showArchived
                                    ? Icons.archive_outlined
                                    : Icons.task_alt_rounded,
                                size: 30,
                                color: Colors.white.withOpacity(0.72),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Text(
                              _showArchived
                                  ? 'No archived tasks'
                                  : 'No tasks yet',
                              textAlign: TextAlign.center,
                              style: const TextStyle(
                                color: _TaskPalette.textMain,
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                height: 1.05,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _showArchived
                                  ? 'Archived tasks will appear here.'
                                  : 'Create the first task for any worker.',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.56),
                                fontWeight: FontWeight.w700,
                                fontSize: 12.8,
                                height: 1.35,
                              ),
                            ),
                          ],
                        ),
                      )
                    else ...[
                      if (recentDone.isNotEmpty)
                        Padding(
                          padding: EdgeInsets.only(
                            bottom: groups.isNotEmpty ? 14 : 0,
                          ),
                          child: _TaskDaySection(
                            title: 'Recently completed',
                            count: recentDone.length,
                            children: List.generate(recentDone.length, (index) {
                              final task = recentDone[index];
                              final Map<String, dynamic> worker =
                              task['workers'] is Map
                                  ? Map<String, dynamic>.from(
                                task['workers'] as Map,
                              )
                                  : <String, dynamic>{};

                              return _TaskCard(
                                task: task,
                                worker: worker,
                                onTap: () => _openTaskActions(task),
                                alternate: index.isOdd,
                                indexLabel: '${index + 1}'.padLeft(2, '0'),
                              );
                            }),
                          ),
                        ),
                      ...List.generate(groups.length, (groupIndex) {
                        final group = groups[groupIndex];

                        return Padding(
                          padding: EdgeInsets.only(
                            bottom: groupIndex == groups.length - 1 ? 0 : 14,
                          ),
                          child: _TaskDaySection(
                            title: group.title,
                            count: group.tasks.length,
                            children: List.generate(group.tasks.length, (taskIndex) {
                              final task = group.tasks[taskIndex];
                              final Map<String, dynamic> worker =
                              task['workers'] is Map
                                  ? Map<String, dynamic>.from(task['workers'] as Map)
                                  : <String, dynamic>{};

                              return Padding(
                                padding: EdgeInsets.only(
                                  bottom: taskIndex == group.tasks.length - 1 ? 0 : 12,
                                ),
                                child: _TaskCard(
                                  task: task,
                                  worker: worker,
                                  onTap: () => _openTaskActions(task),
                                  alternate: false,
                                  indexLabel: '${taskIndex + 1}'.padLeft(2, '0'),
                                ),
                              );
                            }),
                          ),
                        );
                      }),
                    ],
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskPalette {
  static const bg = Color(0xFF0B0D12);
  static const cardTop = Color(0xFF2F3036);
  static const cardBottom = Color(0xFF24252B);
  static const pill = Color(0xFF1F2025);
  static const pillBorder = Color(0xFF34353C);
  static const textMain = Color(0xFFEDEFF6);
  static const textSoft = Color(0xFFB7BCCB);
  static const green = Color(0xFF34D399);
  static const orange = Color(0xFFF59E0B);
  static const blue = Color(0xFF38BDF8);
  static const red = Color(0xFFFB7185);
}

class _TasksBackground extends StatelessWidget {
  const _TasksBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _TaskPalette.bg,
    );
  }
}

class _TasksHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;
  final VoidCallback onCreate;

  const _TasksHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
    required this.onCreate,
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
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _TaskPalette.cardTop.withOpacity(0.97),
                _TaskPalette.cardBottom.withOpacity(0.96),
                const Color(0xFF171A22).withOpacity(0.97),
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
          child: Row(
            children: [
              _HeaderBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _TaskPalette.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 20,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.56),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _HeaderBtn(
                icon: Icons.add_rounded,
                onTap: onCreate,
                accent: true,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminTasksTopPanel extends StatelessWidget {
  final String title;
  final String subtitle;
  final String workerFilterName;
  final String statusFilter;
  final bool showArchived;

  final int activeCount;
  final int doneCount;
  final int archivedCount;

  final VoidCallback onBack;
  final VoidCallback onCreate;
  final VoidCallback onWorkerTap;
  final ValueChanged<String> onStatusChanged;
  final ValueChanged<bool> onArchiveChanged;

  const _AdminTasksTopPanel({
    required this.title,
    required this.subtitle,
    required this.workerFilterName,
    required this.statusFilter,
    required this.showArchived,
    required this.onBack,
    required this.onCreate,
    required this.onWorkerTap,
    required this.onStatusChanged,
    required this.onArchiveChanged,
    required this.activeCount,
    required this.doneCount,
    required this.archivedCount,
  });

  String _statusLabel(String v) {
    switch (v) {
      case 'todo':
        return 'Todo';
      case 'in_progress':
        return 'Progress';
      case 'done':
        return 'Done';
      case 'needs_review':
        return 'Review';
      default:
        return 'All';
    }
  }

  IconData _statusIcon(String v) {
    switch (v) {
      case 'todo':
        return Icons.radio_button_unchecked_rounded;
      case 'in_progress':
        return Icons.timelapse_rounded;
      case 'done':
        return Icons.check_circle_rounded;
      case 'needs_review':
        return Icons.rate_review_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  Color _statusColor(String v) {
    switch (v) {
      case 'todo':
        return const Color(0xFFA47551);
      case 'in_progress':
        return _TaskPalette.blue;
      case 'done':
        return _TaskPalette.green;
      case 'needs_review':
        return _TaskPalette.orange;
      default:
        return Colors.white.withOpacity(0.78);
    }
  }

  BoxDecoration _panelDecoration({
    bool active = false,
  }) {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(20),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: active
            ? [
          const Color(0xFF3E8E70),
          const Color(0xFF2F705A),
        ]
            : [
          const Color(0xFF303542),
          const Color(0xFF262B36),
        ],
      ),
      border: Border.all(
        color: active
            ? _TaskPalette.green.withOpacity(0.30)
            : Colors.white.withOpacity(0.10),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.22),
          blurRadius: 10,
          offset: const Offset(0, 5),
        ),
        BoxShadow(
          color: Colors.white.withOpacity(0.04),
          blurRadius: 12,
          spreadRadius: -6,
          offset: const Offset(0, -2),
        ),
      ],
    );
  }

  BoxDecoration _groupPanelDecoration() {
    return BoxDecoration(
      borderRadius: BorderRadius.circular(24),
      gradient: LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          const Color(0xFF2B313D),
          const Color(0xFF242A35),
        ],
      ),
      border: Border.all(
        color: Colors.white.withOpacity(0.08),
      ),
      boxShadow: [
        BoxShadow(
          color: Colors.black.withOpacity(0.20),
          blurRadius: 14,
          offset: const Offset(0, 8),
        ),
      ],
    );
  }

  Widget _miniStat({
    required IconData icon,
    required Color color,
    required int count,
  }) {
    return Container(
      height: 56,
      decoration: _panelDecoration(),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: const TextStyle(
              color: _TaskPalette.textMain,
              fontWeight: FontWeight.w900,
              fontSize: 15.5,
            ),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: double.infinity,
            alignment: Alignment.center,
            decoration: _panelDecoration(active: selected),
            child: Text(
              label,
              style: TextStyle(
                color: selected
                    ? Colors.white
                    : Colors.white.withOpacity(0.72),
                fontWeight: FontWeight.w800,
                fontSize: 13.2,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    PopupMenuEntry<String> item({
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 46,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    PopupMenuEntry<String> divider() {
      return PopupMenuItem<String>(
        enabled: false,
        height: 8,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.16),
                Colors.white.withOpacity(0.08),
                Colors.transparent,
              ],
            ),
          ),
        ),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2E3139),
                Color(0xFF252830),
                Color(0xFF1F2229),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.07),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.26),
                blurRadius: 22,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            children: [
              Row(
                children: [
                  _HeaderBtn(
                    icon: Icons.arrow_back_ios_new_rounded,
                    onTap: onBack,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _TaskPalette.textMain,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.56),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Icon(
                    Icons.assignment_rounded,
                    color: _TaskPalette.green,
                    size: 24,
                  ),
                ],
              ),

              const SizedBox(height: 14),

              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF343842),
                      Color(0xFF2B2F38),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.07),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 14,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _FilterPill(
                            icon: Icons.person_outline_rounded,
                            label: workerFilterName,
                            onTap: onWorkerTap,
                          ),
                        ),
                        const SizedBox(width: 10),
                        _AddTaskIconButton(
                          onTap: onCreate,
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: _StatusFilterChip(
                            value: statusFilter,
                            onChanged: onStatusChanged,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _ArchiveModeSwitch(
                            showArchived: showArchived,
                            onChanged: onArchiveChanged,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeaderBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onTap;
  final bool accent;

  const _HeaderBtn({
    required this.icon,
    required this.onTap,
    this.accent = false,
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
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: accent
                  ? const [
                Color(0xFF2E6B58),
                Color(0xFF1E4D40),
              ]
                  : const [
                Color(0xFF31363E),
                Color(0xFF232830),
              ],
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: accent
                  ? _TaskPalette.green.withOpacity(0.18)
                  : Colors.white.withOpacity(0.06),
            ),
          ),
          child: Icon(
            icon,
            color: Colors.white.withOpacity(0.84),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FilterPill({
    required this.icon,
    required this.label,
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
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                const Color(0xFF343A47),
                const Color(0xFF2A303B),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.04),
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white.withOpacity(0.76), size: 18),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TaskPalette.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.2,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withOpacity(0.62),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddTaskIconButton extends StatelessWidget {
  final VoidCallback onTap;

  const _AddTaskIconButton({
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
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF356657),
                Color(0xFF274C41),
              ],
            ),
            border: Border.all(
              color: _TaskPalette.green.withOpacity(0.20),
            ),
            boxShadow: [
              BoxShadow(
                color: _TaskPalette.green.withOpacity(0.12),
                blurRadius: 12,
                spreadRadius: -5,
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Icon(
            Icons.add_rounded,
            color: Colors.white.withOpacity(0.95),
            size: 22,
          ),
        ),
      ),
    );
  }
}

class _StatusFilterChip extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusFilterChip({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    PopupMenuEntry<String> item({
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 46,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      );
    }

    PopupMenuEntry<String> divider() {
      return PopupMenuItem<String>(
        enabled: false,
        height: 8,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.16),
                Colors.white.withOpacity(0.08),
                Colors.transparent,
              ],
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      color: const Color(0xFF20242D),
      elevation: 14,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      onSelected: onChanged,
      itemBuilder: (_) => [
        item(
          value: 'all',
          label: 'All',
          icon: Icons.apps_rounded,
          color: Colors.white.withOpacity(0.82),
        ),
        divider(),
        item(
          value: 'todo',
          label: 'Todo',
          icon: Icons.radio_button_unchecked_rounded,
          color: const Color(0xFFA47551),
        ),
        divider(),
        item(
          value: 'in_progress',
          label: 'In progress',
          icon: Icons.timelapse_rounded,
          color: _TaskPalette.blue,
        ),
        divider(),
        item(
          value: 'done',
          label: 'Done',
          icon: Icons.check_circle_rounded,
          color: _TaskPalette.green,
        ),
        divider(),
        item(
          value: 'needs_review',
          label: 'Needs review',
          icon: Icons.rate_review_rounded,
          color: _TaskPalette.orange,
        ),
      ],
      child: Container(
        width: double.infinity,
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF303542),
              Color(0xFF262B36),
            ],
          ),
          border: Border.all(
            color: Colors.white.withOpacity(0.10),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.22),
              blurRadius: 10,
              offset: const Offset(0, 5),
            ),
            BoxShadow(
              color: Colors.white.withOpacity(0.04),
              blurRadius: 12,
              spreadRadius: -6,
              offset: const Offset(0, -2),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              _icon(value),
              color: _iconColor(value),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _label(value),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.8,
                ),
              ),
            ),
            Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Colors.white.withOpacity(0.62),
            ),
          ],
        ),
      ),
    );
  }

  String _label(String v) {
    switch (v) {
      case 'todo':
        return 'Todo';
      case 'in_progress':
        return 'Progress';
      case 'done':
        return 'Done';
      case 'needs_review':
        return 'Review';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'All';
    }
  }

  IconData _icon(String v) {
    switch (v) {
      case 'todo':
        return Icons.radio_button_unchecked_rounded;
      case 'in_progress':
        return Icons.timelapse_rounded;
      case 'done':
        return Icons.check_circle_rounded;
      case 'needs_review':
        return Icons.rate_review_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.apps_rounded;
    }
  }

  Color _iconColor(String v) {
    switch (v) {
      case 'in_progress':
        return _TaskPalette.blue;
      case 'done':
        return _TaskPalette.green;
      case 'needs_review':
        return _TaskPalette.orange;
      case 'cancelled':
        return _TaskPalette.red;
      default:
        return Colors.white.withOpacity(0.80);
    }
  }
}

class _TaskCard extends StatelessWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic> worker;
  final VoidCallback onTap;
  final bool alternate;
  final String indexLabel;

  const _TaskCard({
    required this.task,
    required this.worker,
    required this.onTap,
    this.alternate = false,
    this.indexLabel = '01',
  });

  String _s(Object? v) => (v ?? '').toString().trim();

  String _previewLine(String text, {int limit = 60}) {
    final clean = text
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (clean.isEmpty) return '';
    if (clean.length <= limit) return '$clean ...more';

    return '${clean.substring(0, limit).trimRight()} ...more';
  }

  Color _taskTitleColor() => _TaskPalette.textMain;

  String _fmtDue(Object? v) {
    final s = _s(v);
    if (s.isEmpty) return '';
    final dt = DateTime.tryParse(s)?.toLocal();
    if (dt == null) return '';
    return DateFormat('MMM d, HH:mm').format(dt);
  }

  String _statusLabel(String v) {
    switch (v) {
      case 'in_progress':
        return 'in progress';
      case 'needs_review':
        return 'review';
      default:
        return v;
    }
  }

  IconData _taskStatusIcon(String v) {
    switch (v) {
      case 'done':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.timelapse_rounded;
      case 'needs_review':
        return Icons.rate_review_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  Color _taskStatusColor(String v) {
    switch (v) {
      case 'done':
        return _TaskPalette.green;
      case 'in_progress':
        return _TaskPalette.blue;
      case 'needs_review':
        return _TaskPalette.orange;
      case 'cancelled':
        return _TaskPalette.red;
      default:
        return Colors.white.withOpacity(0.7);
    }
  }

  Color _taskPriorityColor(String v) {
    switch (v) {
      case 'urgent':
        return _TaskPalette.red;
      case 'high':
        return _TaskPalette.orange;
      case 'low':
        return Colors.white.withOpacity(0.62);
      default:
        return _TaskPalette.blue;
    }
  }

  Color _statusColor(String v) {
    switch (v) {
      case 'todo':
        return const Color(0xFFA47551);
      case 'done':
        return _TaskPalette.green;
      case 'in_progress':
        return _TaskPalette.blue;
      case 'needs_review':
        return _TaskPalette.orange;
      case 'cancelled':
        return _TaskPalette.red;
      default:
        return Colors.white.withOpacity(0.78);
    }
  }

  Color _priorityColor(String v) {
    switch (v) {
      case 'urgent':
        return _TaskPalette.red;
      case 'high':
        return _TaskPalette.orange;
      case 'low':
        return Colors.white.withOpacity(0.62);
      default:
        return _TaskPalette.blue;
    }
  }

  IconData _statusIcon(String v) {
    switch (v) {
      case 'done':
        return Icons.check_circle_rounded;
      case 'in_progress':
        return Icons.timelapse_rounded;
      case 'needs_review':
        return Icons.rate_review_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  String _priorityLabel(String v) {
    switch (v) {
      case 'urgent':
        return 'urgent';
      case 'high':
        return 'high';
      case 'low':
        return 'low';
      default:
        return 'normal';
    }
  }

  IconData _priorityIcon(String v) {
    switch (v) {
      case 'urgent':
        return Icons.priority_high_rounded;
      case 'high':
        return Icons.keyboard_double_arrow_up_rounded;
      case 'low':
        return Icons.south_rounded;
      default:
        return Icons.flag_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _s(task['title']).isEmpty ? 'Task' : _s(task['title']).toUpperCase();
    final rawDescription = _s(task['description']);
    final cleanDescription =
    TaskService.stripChecklistFromDescription(rawDescription);

    final workerEmail = _s(worker['email']);
    final workerEmailText = workerEmail.isEmpty ? 'No email' : workerEmail;

    final status = _s(task['status']).toLowerCase();
    final priority = _s(task['priority']).toLowerCase();
    final avatarUrl = _s(worker['avatar_url']);
    final workerNote = _s(task['worker_note']);
    final dueText = _fmtDue(task['due_at']);
    final workerName =
    _s(worker['name']).isEmpty ? 'Worker' : _s(worker['name']);

    final List<Color> cardGradient = alternate
        ? const [
      Color(0xFF3A3E45),
      Color(0xFF2E3239),
    ]
        : const [
      Color(0xFF30343B),
      Color(0xFF24282F),
    ];

    final List<Color> sideBtnGradient = alternate
        ? const [
      Color(0xFF3A404C),
      Color(0xFF2C313B),
    ]
        : const [
      Color(0xFF2C313A),
      Color(0xFF20252D),
    ];

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(0, 14, 0, 14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cardGradient.first.withOpacity(1.0),
                cardGradient.last.withOpacity(1.0),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.11),
              width: 1.1,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.34),
                blurRadius: 20,
                spreadRadius: 1,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: Colors.black.withOpacity(0.16),
                blurRadius: 8,
                spreadRadius: -2,
                offset: const Offset(0, 3),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.045),
                blurRadius: 12,
                spreadRadius: -7,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    _DeadlineIndexBadge(
                      indexLabel: indexLabel,
                      createdAtRaw: _s(task['created_at']),
                      dueAtRaw: _s(task['due_at']),
                      statusRaw: _s(task['status']),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Text(
                            workerName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.88),
                              fontWeight: FontWeight.w800,
                              fontSize: 15.0,
                              height: 1.0,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Container(
                      width: 46,
                      height: 46,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: sideBtnGradient,
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: avatarUrl.isEmpty
                            ? Icon(
                          Icons.person_rounded,
                          color: Colors.white.withOpacity(0.48),
                          size: 21,
                        )
                            : Image.network(
                          avatarUrl,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Icon(
                            Icons.person_rounded,
                            color: Colors.white.withOpacity(0.48),
                            size: 21,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Container(
                  width: double.infinity,
                  height: 48,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        const Color(0xFF20252D).withOpacity(0.98),
                        const Color(0xFF171B22).withOpacity(0.96),
                        const Color(0xFF11151B).withOpacity(0.98),
                      ],
                    ),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.06),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.28),
                        blurRadius: 14,
                        offset: const Offset(0, 7),
                      ),
                      BoxShadow(
                        color: Colors.white.withOpacity(0.035),
                        blurRadius: 10,
                        spreadRadius: -6,
                        offset: const Offset(0, -2),
                      ),
                    ],
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _statusIcon(status),
                                size: 14,
                                color: _statusColor(status),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _statusLabel(status),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.78),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: Colors.white.withOpacity(0.06),
                      ),
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _priorityIcon(priority),
                                size: 14,
                                color: _priorityColor(priority),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  _priorityLabel(priority),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _priorityColor(priority),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 16,
                        color: Colors.white.withOpacity(0.06),
                      ),
                      Expanded(
                        child: Center(
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.schedule_rounded,
                                size: 14,
                                color: Color(0xFFF59E0B),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  dueText.isEmpty ? 'No date' : dueText,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: Colors.white.withOpacity(0.70),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.2,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 10),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            const Color(0xFF252A32).withOpacity(0.92),
                            const Color(0xFF1D2128).withOpacity(0.96),
                            const Color(0xFF171B21).withOpacity(0.98),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.28),
                            blurRadius: 18,
                            spreadRadius: -8,
                            offset: const Offset(0, 10),
                          ),
                          BoxShadow(
                            color: const Color(0xFF6E92D8).withOpacity(0.08),
                            blurRadius: 18,
                            spreadRadius: -10,
                          ),
                        ],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.sell_rounded,
                                  size: 16,
                                  color: Colors.white.withOpacity(0.88),
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: _TaskPalette.textMain,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 16.8,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (cleanDescription.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.notes_rounded,
                                    size: 15,
                                    color: Color(0xFFFACC15),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _previewLine(cleanDescription, limit: 56),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.66),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.0,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          if (workerNote.isNotEmpty) ...[
                            const SizedBox(height: 12),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Padding(
                                  padding: EdgeInsets.only(top: 1),
                                  child: Icon(
                                    Icons.campaign_rounded,
                                    size: 15,
                                    color: Color(0xFF8EA0FF),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    _previewLine(workerNote, limit: 56),
                                    maxLines: 1,
                                    overflow: TextOverflow.clip,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.60),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12.8,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],

                          const SizedBox(height: 14),

                          Container(
                            height: 1,
                            width: double.infinity,
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.transparent,
                                  Colors.white.withOpacity(0.10),
                                  Colors.white.withOpacity(0.05),
                                  Colors.transparent,
                                ],
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),

                          _TaskChecklistPreview(
                            taskId: _s(task['id']),
                            embedded: true,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DeadlineIndexBadge extends StatelessWidget {
  final String indexLabel;
  final String createdAtRaw;
  final String dueAtRaw;
  final String statusRaw;

  const _DeadlineIndexBadge({
    required this.indexLabel,
    required this.createdAtRaw,
    required this.dueAtRaw,
    required this.statusRaw,
  });

  DateTime? _parse(String raw) {
    if (raw.trim().isEmpty) return null;
    return DateTime.tryParse(raw)?.toLocal();
  }

  @override
  Widget build(BuildContext context) {
    final createdAt = _parse(createdAtRaw);
    final dueAt = _parse(dueAtRaw);
    final now = DateTime.now();

    final status = statusRaw.toLowerCase();

    double progress = 0.0;
    Color ringColor = _TaskPalette.green;

    if (status == 'done' || status == 'cancelled') {
      progress = 1.0;
      ringColor = _TaskPalette.red;
    } else if (createdAt != null &&
        dueAt != null &&
        dueAt.isAfter(createdAt)) {
      final totalMs =
          dueAt.millisecondsSinceEpoch - createdAt.millisecondsSinceEpoch;
      final elapsedMs =
          now.millisecondsSinceEpoch - createdAt.millisecondsSinceEpoch;

      progress = (elapsedMs / totalMs).clamp(0.0, 1.0);

      final remaining = 1.0 - progress;

      if (remaining > 0.5) {
        ringColor = _TaskPalette.green;
      } else if (remaining > 0.2) {
        ringColor = _TaskPalette.orange;
      } else {
        ringColor = _TaskPalette.red;
      }
    } else {
      progress = 0.0;
      ringColor = Colors.white.withOpacity(0.18);
    }

    return SizedBox(
      width: 34,
      height: 34,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            width: 34,
            height: 34,
            child: CircularProgressIndicator(
              value: 1.0,
              strokeWidth: 3.2,
              valueColor: AlwaysStoppedAnimation<Color>(
                Colors.white.withOpacity(0.06),
              ),
              backgroundColor: Colors.transparent,
            ),
          ),
          SizedBox(
            width: 34,
            height: 34,
            child: TweenAnimationBuilder<double>(
              tween: Tween<double>(begin: 0, end: progress),
              duration: const Duration(milliseconds: 900),
              curve: Curves.linear,
              builder: (context, value, _) {
                return CircularProgressIndicator(
                  value: value,
                  strokeWidth: 3.6,
                  strokeCap: StrokeCap.round,
                  valueColor: AlwaysStoppedAnimation<Color>(ringColor),
                  backgroundColor: Colors.transparent,
                );
              },
            ),
          ),
          Container(
            width: 29,
            height: 29,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(999),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF31363E),
                  Color(0xFF232830),
                ],
              ),
            ),
            child: Text(
              indexLabel,
              style: TextStyle(
                color: ringColor,
                fontWeight: FontWeight.w900,
                fontSize: 12.8,
                letterSpacing: 0.3,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniTag extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _MiniTag({
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withOpacity(0.24)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color.withOpacity(0.95)),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: TextStyle(
              color: color.withOpacity(0.95),
              fontWeight: FontWeight.w900,
              fontSize: 10.8,
              letterSpacing: 0.1,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskMetaFlat extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color? textColor;

  const _TaskMetaFlat({
    required this.label,
    required this.icon,
    required this.iconColor,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedTextColor = textColor ?? Colors.white.withOpacity(0.62);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: iconColor),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            color: resolvedTextColor,
            fontWeight: FontWeight.w800,
            fontSize: 12.2,
          ),
        ),
      ],
    );
  }
}

class _TaskMetaDivider extends StatelessWidget {

  const _TaskMetaDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 14,
      margin: const EdgeInsets.symmetric(horizontal: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.28),
            Colors.white.withOpacity(0.12),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _TaskChecklistPreview extends StatelessWidget {
  final String taskId;
  final bool embedded;

  const _TaskChecklistPreview({
    required this.taskId,
    this.embedded = false,
  });

  static String _txt(Object? v) => (v ?? '').toString().trim();

  static String _itemStatus(Map<String, dynamic> item) {
    final status = _txt(item['status']).toLowerCase();

    if (status.isNotEmpty) return status;
    if (item['is_done'] == true) return 'done';

    return 'todo';
  }

  static IconData _statusIcon(String status) {
    switch (status) {
      case 'done':
        return Icons.task_alt_rounded;
      case 'blocked':
        return Icons.block_rounded;
      case 'not_needed':
        return Icons.remove_circle_outline_rounded;
      case 'partial':
        return Icons.timelapse_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'done':
        return _TaskPalette.green;
      case 'blocked':
        return _TaskPalette.orange;
      case 'not_needed':
        return Colors.white70;
      case 'partial':
        return _TaskPalette.blue;
      default:
        return _TaskPalette.red;
    }
  }

  static String _statusLabel(String status) {
    switch (status) {
      case 'done':
        return 'done';
      case 'blocked':
        return 'blocked';
      case 'not_needed':
        return 'not needed';
      case 'partial':
        return 'partial';
      default:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: TaskService.watchTaskSubtasks(taskId),
      builder: (context, snapshot) {
        final subtasks = snapshot.data ?? const <Map<String, dynamic>>[];
        if (subtasks.isEmpty) return const SizedBox.shrink();

        final visible = subtasks.take(2).toList();

        final doneCount = subtasks.where((e) {
          final status = _itemStatus(e);
          return status == 'done';
        }).length;

        final totalCount = subtasks.length;
        final hasMore = totalCount > visible.length;
        final isAllDone = doneCount == totalCount;

        final countColor = isAllDone
            ? _TaskPalette.green
            : const Color(0xFFFB7185);

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...List.generate(visible.length, (index) {
              final item = visible[index];
              final title = _txt(item['title']);
              final status = _itemStatus(item);
              final isDone = status == 'done';
              final label = _statusLabel(status);
              final color = _statusColor(status);

              return Padding(
                padding: EdgeInsets.only(
                  bottom: index == visible.length - 1 ? 0 : 8,
                ),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        const Color(0xFF232833).withOpacity(0.94),
                        const Color(0xFF1A1F28).withOpacity(0.98),
                      ],
                    ),
                    border: Border.all(
                      color: status == 'blocked'
                          ? _TaskPalette.orange.withOpacity(0.22)
                          : status == 'partial'
                          ? _TaskPalette.blue.withOpacity(0.22)
                          : status == 'not_needed'
                          ? Colors.white.withOpacity(0.12)
                          : Colors.white.withOpacity(0.07),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.14),
                        blurRadius: 8,
                        spreadRadius: -6,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Icon(
                        _statusIcon(status),
                        size: 18,
                        color: color,
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isDone
                                ? Colors.white.withOpacity(0.68)
                                : Colors.white.withOpacity(0.90),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.8,
                            height: 1.22,
                            decoration:
                            isDone ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.white.withOpacity(0.42),
                          ),
                        ),
                      ),
                      if (label.isNotEmpty && status != 'todo') ...[
                        const SizedBox(width: 8),
                        Text(
                          label,
                          style: TextStyle(
                            color: color.withOpacity(0.92),
                            fontWeight: FontWeight.w900,
                            fontSize: 10.8,
                            height: 1,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }),
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  hasMore ? '...more' : '',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.38),
                    fontWeight: FontWeight.w800,
                    fontSize: 11.4,
                  ),
                ),
                const Spacer(),
                Text(
                  '$doneCount/$totalCount',
                  style: TextStyle(
                    color: countColor,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.2,
                  ),
                ),
              ],
            ),
          ],
        );

        if (embedded) return content;

        return Padding(
          padding: const EdgeInsets.only(top: 12),
          child: content,
        );
      },
    );
  }
}

class _TasksEmptyState extends StatelessWidget {
  final bool showArchived;

  const _TasksEmptyState({
    this.showArchived = false,
  });

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
                _TaskPalette.cardTop.withOpacity(0.97),
                _TaskPalette.cardBottom.withOpacity(0.96),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              Icon(
                showArchived
                    ? Icons.archive_outlined
                    : Icons.task_alt_rounded,
                size: 28,
                color: Colors.white.withOpacity(0.56),
              ),
              const SizedBox(height: 10),
              Text(
                showArchived ? 'No archived tasks' : 'No tasks yet',
                style: const TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                showArchived
                    ? 'Archived tasks will appear here.'
                    : 'Create the first task for any worker.',
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

class _AdminTaskWorkerPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> workers;
  final bool allowAll;

  const _AdminTaskWorkerPickerSheet({
    required this.workers,
    this.allowAll = false,
  });

  @override
  State<_AdminTaskWorkerPickerSheet> createState() =>
      _AdminTaskWorkerPickerSheetState();
}

class _AdminTaskWorkerPickerSheetState extends State<_AdminTaskWorkerPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _q = '';

  String _s(Object? v) => (v ?? '').toString().trim();

  String _mode(Map<String, dynamic> w) {
    final raw = (w['access_mode'] ?? 'active')
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (raw == 'readonly' ||
        raw == 'read_only' ||
        raw == 'viewonly' ||
        raw == 'view_only') {
      return 'view_only';
    }

    return raw;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    final filtered = widget.workers.where((w) {
      final mode = _mode(w);
      if (mode == 'suspended') return false;

      final name = _s(w['name']).toLowerCase();
      final email = _s(w['email']).toLowerCase();
      final q = _q.trim().toLowerCase();

      if (q.isEmpty) return true;
      return name.contains(q) || email.contains(q);
    }).toList();

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 40, 10, 10 + mq.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  const Color(0xFF2C3037).withOpacity(0.97),
                  const Color(0xFF24282F).withOpacity(0.985),
                  const Color(0xFF1D2128).withOpacity(0.99),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.34),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 10),
                  Container(
                    width: 42,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(999),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Select worker',
                            style: TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w900,
                              fontSize: 18,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.groups_2_rounded,
                          color: _TaskPalette.green,
                          size: 22,
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _SheetSearchBar(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 2, 16, 18),
                      children: [
                        if (widget.allowAll)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _WorkerOptionTile(
                              worker: const {
                                'id': '',
                                'name': 'All workers',
                                'email': '',
                                'avatar_url': '',
                                'auth_user_id': '',
                              },
                              onTap: () => Navigator.pop(
                                context,
                                {
                                  'id': '',
                                  'name': 'All workers',
                                  'email': '',
                                  'avatar_url': '',
                                  'auth_user_id': '',
                                },
                              ),
                            ),
                          ),
                        ...filtered.map(
                              (worker) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _WorkerOptionTile(
                              worker: worker,
                              onTap: () => Navigator.pop(context, worker),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerOptionTile extends StatelessWidget {
  final Map<String, dynamic> worker;
  final VoidCallback onTap;

  const _WorkerOptionTile({
    required this.worker,
    required this.onTap,
  });

  String _s(Object? v) => (v ?? '').toString().trim();

  String _mode(Map<String, dynamic> w) {
    final raw = (w['access_mode'] ?? 'active')
        .toString()
        .toLowerCase()
        .trim()
        .replaceAll('-', '_')
        .replaceAll(' ', '_');

    if (raw == 'readonly' ||
        raw == 'read_only' ||
        raw == 'viewonly' ||
        raw == 'view_only') {
      return 'view_only';
    }

    return raw;
  }

  @override
  Widget build(BuildContext context) {
    final name = _s(worker['name']).isEmpty ? 'Worker' : _s(worker['name']);
    final email = _s(worker['email']);
    final avatarUrl = _s(worker['avatar_url']);
    final mode = _mode(worker);

    final isAllWorkers = _s(worker['id']).isEmpty;
    final isViewOnly = mode == 'view_only';

    final gradientColors = isViewOnly
        ? const [
      Color(0xFF4A4430),
      Color(0xFF3E3928),
      Color(0xFF322E22),
    ]
        : const [
      Color(0xFF323842),
      Color(0xFF2A3038),
      Color(0xFF242B31),
    ];

    final borderColor = isViewOnly
        ? const Color(0xFFFACC15).withOpacity(0.22)
        : Colors.white.withOpacity(0.06);

    final glowColor = isViewOnly
        ? const Color(0xFFFACC15).withOpacity(0.08)
        : _TaskPalette.green.withOpacity(0.025);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: gradientColors,
            ),
            border: Border.all(
              color: borderColor,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 16,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: glowColor,
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
            child: Row(
              children: [
                _WorkerAvatar(avatarUrl: avatarUrl),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            isAllWorkers
                                ? Icons.badge_outlined
                                : Icons.badge_outlined,
                            size: 15,
                            color: isViewOnly
                                ? const Color(0xFFFACC15).withOpacity(0.82)
                                : Colors.white.withOpacity(0.42),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: _TaskPalette.textMain,
                                fontWeight: FontWeight.w900,
                                fontSize: 15.2,
                              ),
                            ),
                          ),
                          if (isViewOnly) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 5,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFFACC15).withOpacity(0.12),
                                borderRadius: BorderRadius.circular(999),
                                border: Border.all(
                                  color: const Color(0xFFFACC15).withOpacity(0.24),
                                ),
                              ),
                              child: const Text(
                                'View only',
                                style: TextStyle(
                                  color: Color(0xFFFACC15),
                                  fontWeight: FontWeight.w900,
                                  fontSize: 10.2,
                                  height: 1,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                      if (email.isNotEmpty) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              Icons.email_outlined,
                              size: 14,
                              color: isViewOnly
                                  ? const Color(0xFFFDE68A).withOpacity(0.62)
                                  : Colors.white.withOpacity(0.38),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                email,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isViewOnly
                                      ? const Color(0xFFFDE68A).withOpacity(0.76)
                                      : Colors.white.withOpacity(0.62),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12.8,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Icon(
                  Icons.chevron_right_rounded,
                  color: isViewOnly
                      ? const Color(0xFFFACC15).withOpacity(0.62)
                      : Colors.white.withOpacity(0.28),
                  size: 22,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WorkerAvatar extends StatelessWidget {
  final String avatarUrl;

  const _WorkerAvatar({required this.avatarUrl});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 46,
      height: 46,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        color: Colors.white.withOpacity(0.06),
        border: Border.all(color: Colors.white.withOpacity(0.12)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: avatarUrl.isEmpty
            ? Icon(
          Icons.person_rounded,
          color: Colors.white.withOpacity(0.52),
          size: 20,
        )
            : Image.network(
          avatarUrl,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Icon(
            Icons.person_rounded,
            color: Colors.white.withOpacity(0.52),
            size: 20,
          ),
        ),
      ),
    );
  }
}

class _SheetSearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SheetSearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(22),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF252930).withOpacity(0.94),
                const Color(0xFF1D2128).withOpacity(0.97),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: TextField(
            controller: controller,
            onChanged: onChanged,
            style: const TextStyle(
              color: _TaskPalette.textMain,
              fontWeight: FontWeight.w700,
            ),
            decoration: InputDecoration(
              border: InputBorder.none,
              icon: Icon(
                Icons.search_rounded,
                color: Colors.white.withOpacity(0.50),
              ),
              hintText: 'Search worker',
              hintStyle: TextStyle(
                color: Colors.white.withOpacity(0.30),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

Future<bool> showPastDueTaskWarningDialog(
    BuildContext context, {
      required bool isEdit,
    }) async {
  final result = await showDialog<bool>(
    context: context,
    barrierColor: Colors.black.withOpacity(0.62),
    builder: (context) {
      return Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 18),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(30),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(30),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    const Color(0xFF2A2024).withOpacity(0.98),
                    const Color(0xFF211C22).withOpacity(0.99),
                    const Color(0xFF171A21).withOpacity(0.99),
                  ],
                ),
                border: Border.all(
                  color: _TaskPalette.red.withOpacity(0.24),
                ),
                boxShadow: [
                  BoxShadow(
                    color: _TaskPalette.red.withOpacity(0.16),
                    blurRadius: 26,
                    spreadRadius: -8,
                    offset: const Offset(0, 12),
                  ),
                  BoxShadow(
                    color: Colors.black.withOpacity(0.36),
                    blurRadius: 28,
                    offset: const Offset(0, 16),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(15),
                          gradient: const LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Color(0xFF7A2433),
                              Color(0xFF4A1F27),
                            ],
                          ),
                          border: Border.all(
                            color: _TaskPalette.red.withOpacity(0.30),
                          ),
                        ),
                        child: const Icon(
                          Icons.schedule_rounded,
                          color: Colors.white,
                          size: 21,
                        ),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Text(
                          'Past due time',
                          style: TextStyle(
                            color: _TaskPalette.textMain,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            height: 1.05,
                          ),
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 14),

                  Container(
                    height: 1,
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.transparent,
                          _TaskPalette.red.withOpacity(0.24),
                          Colors.white.withOpacity(0.06),
                          Colors.transparent,
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(height: 14),

                  Text(
                    isEdit
                        ? 'This due time is already in the past. The task will be shown as overdue.'
                        : 'This due time is already in the past. The worker will still see this task, but it will be marked as overdue.',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.72),
                      fontWeight: FontWeight.w700,
                      fontSize: 13.8,
                      height: 1.36,
                    ),
                  ),

                  const SizedBox(height: 18),

                  Row(
                    children: [
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.pop(context, false),
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF2B313D),
                                    Color(0xFF222833),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.08),
                                ),
                              ),
                              child: const Center(
                                child: Text(
                                  'Edit time',
                                  style: TextStyle(
                                    color: _TaskPalette.textMain,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(20),
                            onTap: () => Navigator.pop(context, true),
                            child: Container(
                              height: 54,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF7A2433),
                                    Color(0xFF5A1B26),
                                  ],
                                ),
                                border: Border.all(
                                  color: _TaskPalette.red.withOpacity(0.28),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: _TaskPalette.red.withOpacity(0.18),
                                    blurRadius: 12,
                                    spreadRadius: -4,
                                  ),
                                ],
                              ),
                              child: Center(
                                child: Text(
                                  isEdit ? 'Save anyway' : 'Create anyway',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 14,
                                  ),
                                ),
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
        ),
      );
    },
  );

  return result == true;
}

class _CreateTaskSheet extends StatefulWidget {
  final List<Map<String, dynamic>> workers;
  final Future<void> Function(Map<String, dynamic> payload) onSubmitTask;

  const _CreateTaskSheet({
    required this.workers,
    required this.onSubmitTask,
  });

  @override
  State<_CreateTaskSheet> createState() => _CreateTaskSheetState();
}

class _CreateTaskSheetState extends State<_CreateTaskSheet> {
  final TextEditingController _titleCtrl = TextEditingController();
  final TextEditingController _descCtrl = TextEditingController();
  bool _isSubmitting = false;

  String? _workerError;
  String? _titleError;

  final List<XFile> _imageFiles = [];
  PlatformFile? _docFile;

  final List<Map<String, dynamic>> _queuedTasks = [];

  Map<String, dynamic>? _selectedWorker;
  String _priority = 'normal';
  DateTime? _dueAt;

  String _s(Object? v) => (v ?? '').toString().trim();

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickWorker() async {
    final selected = await showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AdminTaskWorkerPickerSheet(
        workers: widget.workers,
      ),
    );

    if (selected == null) return;
    setState(() {
      _selectedWorker = selected;
      _workerError = null;
    });
  }

  Future<void> _pickImageFromGallery() async {
    final remaining = 5 - _imageFiles.length;
    if (remaining <= 0) return;

    final picker = ImagePicker();
    final files = await picker.pickMultiImage();

    if (files.isEmpty) return;

    setState(() {
      _imageFiles.addAll(files.take(remaining));
    });
  }

  Future<void> _pickImageFromCamera() async {
    if (_imageFiles.length >= 5) return;
    final file = await TaskService.pickTaskImageFromCamera();
    if (file == null) return;
    setState(() {
      if (_imageFiles.length < 5) {
        _imageFiles.add(file);
      }
    });
  }

  Future<void> _pickDocFile() async {
    final file = await TaskService.pickTaskFile();
    if (file == null) return;
    setState(() => _docFile = file);
  }

  Future<void> _pickDueDate() async {
    final picked = await showModernDueDatePicker(
      context,
      initial: _dueAt ?? DateTime.now(),
    );

    if (picked == null) return;

    setState(() {
      _dueAt = picked;
    });
  }

  Map<String, dynamic> _currentTaskDraft() {
    return {
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'priority': _priority,
      'due_at': _dueAt,
      'image_files': List<XFile>.from(_imageFiles),
      'doc_file': _docFile,
    };
  }

  void _addAnotherTask() {
    final title = _titleCtrl.text.trim();

    setState(() {
      _titleError = title.isEmpty ? 'Enter task title' : null;
    });

    if (title.isEmpty) {
      final parentState = context.findAncestorStateOfType<_AdminTasksScreenState>();
      parentState?._showTaskToast(
        'Enter task title before adding another',
        icon: Icons.info_outline_rounded,
        accent: _TaskPalette.orange,
      );
      return;
    }

    setState(() {
      _queuedTasks.add(_currentTaskDraft());

      _titleCtrl.clear();
      _descCtrl.clear();
      _priority = 'normal';
      _dueAt = null;

      _imageFiles.clear();   // <-- очистили фото для следующей задачи
      _docFile = null;       // <-- очистили файл для следующей задачи

      _titleError = null;
    });
  }

  Future<void> _submit() async {
    debugPrint('SUBMIT CLICKED');
    if (_isSubmitting) return;

    final hasWorker = _selectedWorker != null;

    final tasks = <Map<String, dynamic>>[
      ..._queuedTasks,
    ];

    if (_titleCtrl.text.trim().isNotEmpty) {
      tasks.add(_currentTaskDraft());
    }

    setState(() {
      _workerError = hasWorker ? null : 'Select worker';
      _titleError = tasks.isEmpty ? 'Enter task title' : null;
    });

    if (!hasWorker || tasks.isEmpty) {
      final parentState = context.findAncestorStateOfType<_AdminTasksScreenState>();
      parentState?._showTaskToast(
        !hasWorker ? 'Select worker first' : 'Enter task title',
        icon: Icons.info_outline_rounded,
        accent: _TaskPalette.orange,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {

      final hasPastDue = tasks.any((task) {
        final dueAt = task['due_at'];
        return dueAt is DateTime && dueAt.isBefore(DateTime.now());
      });

      await widget.onSubmitTask({
        'worker_id': _s(_selectedWorker!['id']),
        'worker_auth_id': _s(_selectedWorker!['auth_user_id']),
        'tasks': tasks,
      });

      if (!mounted) return;
      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;
      final parentState = context.findAncestorStateOfType<_AdminTasksScreenState>();
      parentState?._showTaskToast(
        'Create failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final workerName = _selectedWorker == null
        ? 'Select worker'
        : (_s(_selectedWorker!['name']).isEmpty
        ? 'Worker'
        : _s(_selectedWorker!['name']));

    return Padding(
        padding: EdgeInsets.fromLTRB(10, 40, 10, 10 + mq.viewInsets.bottom),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: _TaskFormShell(
            title: 'New task',
            panelColors: const [
              Color(0xFF2C3037),
              Color(0xFF24282F),
              Color(0xFF1D2128),
            ],
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _SheetSectionCard(
                  child: Column(
                    children: [
                      _GroupedTapField(
                        label: 'Worker',
                        value: workerName,
                        icon: Icons.person_outline_rounded,
                        iconColor: _TaskPalette.green,
                        onTap: _pickWorker,
                      ),
                      const _SectionDivider(),
                      _GroupedTextField(
                        controller: _titleCtrl,
                        label: 'Task title',
                        hint: 'Enter short clear title',
                        maxLines: 2,
                        icon: Icons.title_rounded,
                        iconColor: Colors.white,
                      ),
                      const _SectionDivider(),
                      _GroupedTextField(
                        controller: _descCtrl,
                        label: 'Description',
                        hint: 'Add details for the worker',
                        maxLines: 4,
                        icon: Icons.notes_rounded,
                        iconColor: _TaskPalette.orange,
                      ),
                      const _SectionDivider(),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: _PriorityPicker(
                                value: _priority,
                                onChanged: (v) => setState(() => _priority = v),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: _MiniSelectCard(
                                label: 'Due date',
                                value: _dueAt == null
                                    ? 'Set date'
                                    : DateFormat('MMM d • hh:mm a').format(_dueAt!),
                                icon: Icons.calendar_month_rounded,
                                iconColor: _TaskPalette.blue,
                                onTap: _pickDueDate,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_workerError != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _workerError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],

                if (_titleError != null) ...[
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      _titleError!,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],

                const SizedBox(height: 12),

                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(20),
                    onTap: _addAnotherTask,
                    child: Container(
                      width: double.infinity,
                      height: 56,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Color(0xFF2A2E35),
                            Color(0xFF20242B),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.18),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.playlist_add_rounded,
                            color: Colors.white.withOpacity(0.88),
                          ),
                          const SizedBox(width: 10),
                          const Text(
                            'Add another',
                            style: TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w800,
                              fontSize: 14.2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

                if (_queuedTasks.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Column(
                    children: List.generate(_queuedTasks.length, (index) {
                      final item = _queuedTasks[index];

                      return Padding(
                        padding: EdgeInsets.only(bottom: index == _queuedTasks.length - 1 ? 0 : 8),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFACC15).withOpacity(0.06),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: const Color(0xFFFACC15).withOpacity(0.14),
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFFACC15).withOpacity(0.04),
                                blurRadius: 10,
                                spreadRadius: -6,
                              ),
                            ],
                          ),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _s(item['title']),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        color: _TaskPalette.textMain,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13.8,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      _s(item['priority']).isEmpty ? 'normal' : _s(item['priority']),
                                      style: TextStyle(
                                        color: Colors.white.withOpacity(0.52),
                                        fontWeight: FontWeight.w700,
                                        fontSize: 11.8,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              IconButton(
                                onPressed: () {
                                  setState(() {
                                    _queuedTasks.removeAt(index);
                                  });
                                },
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white70,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ),
                ],

                const SizedBox(height: 12),

                _SheetSectionCard(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Row(
                      children: [
                        _MediaCapsuleAction(
                          label: 'Gallery',
                          icon: Icons.photo_library_outlined,
                          iconColor: Colors.white,
                          onTap: _pickImageFromGallery,
                        ),
                        const SizedBox(width: 10),
                        _MediaCapsuleAction(
                          label: 'Camera',
                          icon: Icons.photo_camera_outlined,
                          iconColor: Colors.white,
                          onTap: _pickImageFromCamera,
                        ),
                        const SizedBox(width: 10),
                        _MediaCapsuleAction(
                          label: 'Attach',
                          icon: Icons.attach_file_rounded,
                          iconColor: Colors.white.withOpacity(0.88),
                          onTap: _pickDocFile,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_imageFiles.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  SizedBox(
                    height: 86,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _imageFiles.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 10),
                      itemBuilder: (context, index) {
                        final image = _imageFiles[index];

                        return Stack(
                          children: [
                            ClipRRect(
                              borderRadius: BorderRadius.circular(18),
                              child: Image.file(
                                File(image.path),
                                width: 86,
                                height: 86,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(
                                  width: 86,
                                  height: 86,
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: Colors.white.withOpacity(0.04),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: Colors.white.withOpacity(0.08)),
                                  ),
                                  child: const Icon(
                                    Icons.broken_image_outlined,
                                    color: Colors.white70,
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 6,
                              right: 6,
                              child: Material(
                                color: Colors.black.withOpacity(0.55),
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                                    setState(() {
                                      _imageFiles.removeAt(index);
                                    });
                                  },
                                  child: const Padding(
                                    padding: EdgeInsets.all(4),
                                    child: Icon(
                                      Icons.close_rounded,
                                      size: 14,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],

                if (_docFile != null) ...[
                  const SizedBox(height: 10),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: Colors.white.withOpacity(0.08)),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.insert_drive_file_outlined,
                          color: Colors.white.withOpacity(0.72),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _docFile!.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],

                const SizedBox(height: 14),
                _FormButtons(
                  onCancel: () {
                    if (_isSubmitting) return;
                    Navigator.pop(context);
                  },
                  onSubmit: () async {
                    if (_isSubmitting) return;
                    await _submit();
                  },
                  submitText: _isSubmitting ? 'Creating...' : 'Create',
                ),
              ],
            ),
       ),
      ),
    );
  }
}

class _EditTaskSheet extends StatefulWidget {
  final Map<String, dynamic> task;
  final Map<String, dynamic> worker;
  final Future<void> Function(Map<String, dynamic> payload) onSubmitTask;

  const _EditTaskSheet({
    required this.task,
    required this.worker,
    required this.onSubmitTask,
  });

  @override
  State<_EditTaskSheet> createState() => _EditTaskSheetState();
}

class _EditTaskSheetState extends State<_EditTaskSheet> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _descCtrl;

  String? _titleError;

  late String _priority;
  late String _status;
  DateTime? _dueAt;

  String _s(Object? v) => (v ?? '').toString().trim();

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: _s(widget.task['title']));
    _descCtrl = TextEditingController(text: _s(widget.task['description']));
    _priority = _s(widget.task['priority']).isEmpty ? 'normal' : _s(widget.task['priority']);
    _status = _s(widget.task['status']).isEmpty ? 'todo' : _s(widget.task['status']);
    _dueAt = DateTime.tryParse(_s(widget.task['due_at']))?.toLocal();
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickDueDate() async {
    final picked = await showModernDueDatePicker(
      context,
      initial: _dueAt ?? DateTime.now(),
    );

    if (picked == null) return;

    setState(() {
      _dueAt = picked;
    });
  }

  Future<void> _submit() async {
    final hasTitle = _titleCtrl.text.trim().isNotEmpty;

    setState(() {
      _titleError = hasTitle ? null : 'Enter task title';
    });

    if (!hasTitle) {
      final parentState = context.findAncestorStateOfType<_AdminTasksScreenState>();
      parentState?._showTaskToast(
        'Enter task title',
        icon: Icons.info_outline_rounded,
        accent: _TaskPalette.orange,
      );
      return;
    }

    if (_dueAt != null && _dueAt!.isBefore(DateTime.now())) {
      final continueAnyway = await showPastDueTaskWarningDialog(
        context,
        isEdit: true,
      );

      if (!continueAnyway) return;
    }

    await widget.onSubmitTask({
      'title': _titleCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      'priority': _priority,
      'status': _status,
      'due_at': _dueAt,
    });

    if (!mounted) return;
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final workerName =
    _s(widget.worker['name']).isEmpty ? 'Worker' : _s(widget.worker['name']);

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 40, 10, 10 + mq.viewInsets.bottom),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: _TaskFormShell(
          title: 'Edit task',
          panelColors: const [
            Color(0xFF2C3037),
            Color(0xFF24282F),
            Color(0xFF1D2128),
          ],
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SheetSectionCard(
                child: Column(
                  children: [
                    IgnorePointer(
                      ignoring: true,
                      child: _GroupedTapField(
                        label: 'Worker',
                        value: workerName,
                        icon: Icons.person_outline_rounded,
                        iconColor: _TaskPalette.green,
                        onTap: () {},
                      ),
                    ),
                    const _SectionDivider(),
                    _GroupedTextField(
                      controller: _titleCtrl,
                      label: 'Task title',
                      hint: 'Enter short clear title',
                      maxLines: 2,
                      icon: Icons.title_rounded,
                      iconColor: Colors.white,
                    ),
                    const _SectionDivider(),
                    _GroupedTextField(
                      controller: _descCtrl,
                      label: 'Description',
                      hint: 'Add details for the worker',
                      maxLines: 5,
                      icon: Icons.notes_rounded,
                      iconColor: _TaskPalette.orange,
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              _SheetSectionCard(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: _PriorityPicker(
                              value: _priority,
                              onChanged: (v) => setState(() => _priority = v),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _StatusPicker(
                              value: _status,
                              onChanged: (v) => setState(() => _status = v),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _MiniSelectCard(
                        label: 'Due date',
                        value: _dueAt == null
                            ? 'Set date'
                            : DateFormat('MMM d • hh:mm a').format(_dueAt!),
                        icon: Icons.calendar_month_rounded,
                        iconColor: _TaskPalette.blue,
                        onTap: _pickDueDate,
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 14),

              _FormButtons(
                onCancel: () => Navigator.pop(context),
                onSubmit: _submit,
                submitText: 'Save',
                submitIcon: Icons.check_rounded,
              ),
            ],
        ),
       ),
      ),
    );
  }
}

class _TaskFormShell extends StatelessWidget {
  final String title;
  final Widget child;
  final List<Color>? panelColors;

  const _TaskFormShell({
    required this.title,
    required this.child,
    this.panelColors,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedPanelColors = panelColors ??
        const [
          Color(0xFF232833),
          Color(0xFF1A1F28),
          Color(0xFF141922),
        ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(30),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
        child: Container(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(30),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: resolvedPanelColors,
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.34),
                blurRadius: 28,
                offset: const Offset(0, 16),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _TaskPalette.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                        letterSpacing: 0.1,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.assignment_turned_in_rounded,
                    color: _TaskPalette.green,
                    size: 22,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                height: 1,
                width: double.infinity,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      Colors.transparent,
                      Colors.white.withOpacity(0.10),
                      Colors.white.withOpacity(0.05),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

class _SheetSectionCard extends StatelessWidget {
  final Widget child;

  const _SheetSectionCard({
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(24),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF2A2E35).withOpacity(0.92),
            const Color(0xFF23272E).withOpacity(0.96),
            const Color(0xFF1B1F26).withOpacity(0.98),
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
      child: child,
    );
  }
}

class _SectionDivider extends StatelessWidget {
  const _SectionDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 1,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.05),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _GroupedTapField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback onTap;
  final bool showChevron;

  const _GroupedTapField({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    required this.onTap,
    this.showChevron = true,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label.toUpperCase(),
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.34),
                        fontWeight: FontWeight.w700,
                        fontSize: 10.5,
                        letterSpacing: 0.7,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _TaskPalette.textMain,
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                      ),
                    ),
                  ],
                ),
              ),
              if (showChevron)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withOpacity(0.46),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GroupedTextField extends StatelessWidget {
  final String label;
  final String hint;
  final TextEditingController controller;
  final IconData icon;
  final Color iconColor;
  final int maxLines;

  const _GroupedTextField({
    required this.label,
    required this.hint,
    required this.controller,
    required this.icon,
    required this.iconColor,
    required this.maxLines,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Row(
        crossAxisAlignment:
        maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Padding(
            padding: EdgeInsets.only(top: maxLines > 1 ? 18 : 18),
            child: Icon(
              icon,
              size: 18,
              color: iconColor,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label.toUpperCase(),
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.34),
                    fontWeight: FontWeight.w700,
                    fontSize: 10.5,
                    letterSpacing: 0.7,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: maxLines,
                  style: const TextStyle(
                    color: _TaskPalette.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.5,
                    height: 1.3,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.28),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
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

class _MiniSelectCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _MiniSelectCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.iconColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      height: 84,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        color: Colors.white.withOpacity(0.035),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.34),
              fontWeight: FontWeight.w700,
              fontSize: 10.5,
              letterSpacing: 0.7,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(icon, size: 18, color: iconColor),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _TaskPalette.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.2,
                  ),
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white.withOpacity(0.44),
              ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

class _MediaCapsuleAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color iconColor;

  const _MediaCapsuleAction({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 92,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2A2E35),
                  Color(0xFF20242B),
                ],
              ),
              border: Border.all(
                color: Colors.white.withOpacity(0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 22,
                  color: Colors.white,
                ),
                const SizedBox(height: 10),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.8,
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

class _TaskActionCapsule extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final Color accentColor;
  final double height;

  const _TaskActionCapsule({
    required this.label,
    required this.icon,
    required this.onTap,
    this.accentColor = Colors.white,
    this.height = 64,
  });

  @override
  Widget build(BuildContext context) {
    final bool isGreen = accentColor == _TaskPalette.green;
    final bool isRed = accentColor == _TaskPalette.red;
    final bool isSilver = accentColor.value == const Color(0xFF9AA4B5).value;

    final List<Color> gradientColors = isGreen
        ? const [
      Color(0xFF2F7F64),
      Color(0xFF2A6E58),
    ]
        : isRed
        ? const [
      Color(0xFF7B2335),
      Color(0xFF611A29),
    ]
        : isSilver
        ? const [
      Color(0xFF9AA4B5),
      Color(0xFF7E889A),
    ]
        : const [
      Color(0xFF2A2E35),
      Color(0xFF20242B),
    ];

    final Color borderColor = isGreen
        ? const Color(0xFF3E9A79)
        : isRed
        ? const Color(0xFFA73E57)
        : isSilver
        ? Colors.white.withOpacity(0.16)
        : Colors.white.withOpacity(0.08);

    final Color glowColor = isGreen
        ? const Color(0xFF2F7F64)
        : isRed
        ? const Color(0xFF7B2335)
        : isSilver
        ? const Color(0xFF9AA4B5)
        : Colors.black;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: gradientColors,
            ),
            border: Border.all(
              color: borderColor,
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: glowColor.withOpacity(isGreen || isRed ? 0.20 : 0.18),
                blurRadius: 16,
                spreadRadius: -6,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: Colors.white,
                size: 19,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 14.4,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskInput extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final String hint;
  final int maxLines;
  final IconData icon;
  final Color iconColor;

  const _TaskInput({
    required this.controller,
    required this.label,
    required this.hint,
    required this.maxLines,
    required this.icon,
    required this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B313D),
            Color(0xFF232934),
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
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.36),
              fontWeight: FontWeight.w700,
              fontSize: 10.8,
              letterSpacing: 0.7,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment:
            maxLines > 1 ? CrossAxisAlignment.start : CrossAxisAlignment.center,
            children: [
              Padding(
                padding: EdgeInsets.only(top: maxLines > 1 ? 2 : 0),
                child: Icon(
                  icon,
                  size: 18,
                  color: iconColor,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: maxLines,
                  style: const TextStyle(
                    color: _TaskPalette.textMain,
                    fontWeight: FontWeight.w700,
                    fontSize: 14.6,
                    height: 1.3,
                  ),
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    isCollapsed: true,
                    hintText: hint,
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.30),
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _FieldTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final VoidCallback? onTap;
  final Color? iconColor;
  final Color? valueColor;

  const _FieldTile({
    required this.label,
    required this.value,
    required this.icon,
    this.onTap,
    this.iconColor,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final body = Container(
      height: 76,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B313D),
            Color(0xFF232934),
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
          BoxShadow(
            color: Colors.white.withOpacity(0.025),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: Colors.white.withOpacity(0.36),
              fontWeight: FontWeight.w700,
              fontSize: 10.8,
              letterSpacing: 0.7,
            ),
          ),
          const Spacer(),
          Row(
            children: [
              Icon(
                icon,
                size: 18,
                color: iconColor ?? Colors.white.withOpacity(0.74),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: valueColor ?? _TaskPalette.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.6,
                  ),
                ),
              ),
              if (onTap != null)
                Icon(
                  Icons.keyboard_arrow_down_rounded,
                  color: Colors.white.withOpacity(0.48),
                ),
            ],
          ),
        ],
      ),
    );

    if (onTap == null) return body;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: body,
      ),
    );
  }
}

class _PriorityPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _PriorityPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    PopupMenuEntry<String> item({
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 48,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    PopupMenuEntry<String> divider() {
      return PopupMenuItem<String>(
        enabled: false,
        height: 8,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.14),
                Colors.white.withOpacity(0.07),
                Colors.transparent,
              ],
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      color: const Color(0xFF1E242D),
      elevation: 14,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      onSelected: onChanged,
      itemBuilder: (_) => [
        item(
          value: 'low',
          label: 'Low',
          icon: Icons.south_rounded,
          color: Colors.white.withOpacity(0.72),
        ),
        divider(),
        item(
          value: 'normal',
          label: 'Normal',
          icon: Icons.drag_handle_rounded,
          color: _TaskPalette.blue,
        ),
        divider(),
        item(
          value: 'high',
          label: 'High',
          icon: Icons.priority_high_rounded,
          color: _TaskPalette.orange,
        ),
        divider(),
        item(
          value: 'urgent',
          label: 'Urgent',
          icon: Icons.local_fire_department_rounded,
          color: _TaskPalette.red,
        ),
      ],
      child: _MiniSelectCard(
        label: 'Priority',
        value: _pretty(value),
        icon: _icon(value),
        iconColor: _color(value),
      ),
    );
  }

  String _pretty(String v) {
    switch (v) {
      case 'low':
        return 'Low';
      case 'high':
        return 'High';
      case 'urgent':
        return 'Urgent';
      default:
        return 'Normal';
    }
  }

  IconData _icon(String v) {
    switch (v) {
      case 'low':
        return Icons.south_rounded;
      case 'high':
        return Icons.priority_high_rounded;
      case 'urgent':
        return Icons.local_fire_department_rounded;
      default:
        return Icons.drag_handle_rounded;
    }
  }

  Color _color(String v) {
    switch (v) {
      case 'high':
        return _TaskPalette.orange;
      case 'urgent':
        return _TaskPalette.red;
      case 'low':
        return Colors.white.withOpacity(0.72);
      default:
        return _TaskPalette.green;
    }
  }
}

Future<DateTime?> showModernDueDatePicker(
    BuildContext context, {
      DateTime? initial,
    }) async {
  final pickedDate = await showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _DatePickerSheet(initial: initial ?? DateTime.now()),
  );

  if (pickedDate == null) return null;
  if (!context.mounted) return null;

  final pickedTime = await showModalBottomSheet<DateTime>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _TimePickerSheet(initial: pickedDate),
  );

  return pickedTime;
}

class _PickerButtonGhost extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerButtonGhost({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              color: Colors.white.withOpacity(0.04),
              border: Border.all(color: Colors.white.withOpacity(0.07)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 18, color: Colors.white.withOpacity(0.56)),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.70),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.6,
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

class _PickerButtonPrimary extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _PickerButtonPrimary({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Color(0xFF2F7F64),
                  Color(0xFF2A6E58),
                ],
              ),
              border: Border.all(
                color: Color(0xFF3E9A79),
                width: 1,
              ),
              boxShadow: [
                BoxShadow(
                  color: Color(0xFF2F7F64),
                  blurRadius: 14,
                  spreadRadius: -6,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: Colors.white,
                ),
                const SizedBox(width: 8),
                Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.8,
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

class _DatePickerSheet extends StatefulWidget {
  final DateTime initial;

  const _DatePickerSheet({
    required this.initial,
  });

  @override
  State<_DatePickerSheet> createState() => _DatePickerSheetState();
}

class _DatePickerSheetState extends State<_DatePickerSheet> {
  late DateTime _selected;
  late DateTime _visibleMonth;
  bool _forward = true;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
    _visibleMonth = DateTime(widget.initial.year, widget.initial.month, 1);
  }

  void _changeMonth(int delta) {
    setState(() {
      _forward = delta > 0;
      _visibleMonth = DateTime(_visibleMonth.year, _visibleMonth.month + delta, 1);
    });
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_visibleMonth);
    final daysInMonth = DateUtils.getDaysInMonth(_visibleMonth.year, _visibleMonth.month);
    final firstWeekday = DateTime(_visibleMonth.year, _visibleMonth.month, 1).weekday % 7;

    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 40, 10, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF2C3037),
                  Color(0xFF24282F),
                  Color(0xFF1D2128),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select date',
                        style: TextStyle(
                          color: _TaskPalette.textMain,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.calendar_month_rounded,
                      color: _TaskPalette.blue,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    gradient: const LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color(0xFF303542),
                        Color(0xFF262B36),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withOpacity(0.10)),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.20),
                        blurRadius: 10,
                        offset: const Offset(0, 5),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.event_available_rounded,
                          color: _TaskPalette.green,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('EEE, MMM d').format(_selected),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _TaskPalette.textMain,
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    IconButton(
                      onPressed: () => _changeMonth(-1),
                      icon: Icon(
                        Icons.chevron_left_rounded,
                        color: Colors.white.withOpacity(0.72),
                      ),
                    ),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 260),
                        transitionBuilder: (child, animation) {
                          final begin = _forward ? const Offset(0.25, 0) : const Offset(-0.25, 0);
                          return FadeTransition(
                            opacity: animation,
                            child: SlideTransition(
                              position: Tween<Offset>(
                                begin: begin,
                                end: Offset.zero,
                              ).animate(animation),
                              child: child,
                            ),
                          );
                        },
                        child: Text(
                          monthLabel,
                          key: ValueKey(monthLabel),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _TaskPalette.textMain,
                            fontWeight: FontWeight.w800,
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => _changeMonth(1),
                      icon: Icon(
                        Icons.chevron_right_rounded,
                        color: Colors.white.withOpacity(0.72),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 4),
                  child: Row(
                    children: [
                      Expanded(child: Center(child: Text('S', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                      Expanded(child: Center(child: Text('M', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                      Expanded(child: Center(child: Text('T', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                      Expanded(child: Center(child: Text('W', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                      Expanded(child: Center(child: Text('T', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                      Expanded(child: Center(child: Text('F', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                      Expanded(child: Center(child: Text('S', style: TextStyle(color: Colors.white54, fontWeight: FontWeight.w700)))),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 260),
                  transitionBuilder: (child, animation) {
                    final begin = _forward ? const Offset(0.22, 0) : const Offset(-0.22, 0);
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: begin,
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: SizedBox(
                    key: ValueKey('${_visibleMonth.year}-${_visibleMonth.month}'),
                    height: 288,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 42,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                      ),
                      itemBuilder: (context, index) {
                        final dayNumber = index - firstWeekday + 1;
                        if (dayNumber < 1 || dayNumber > daysInMonth) {
                          return const SizedBox.shrink();
                        }

                        final date = DateTime(_visibleMonth.year, _visibleMonth.month, dayNumber);
                        final isSelected =
                            date.year == _selected.year &&
                                date.month == _selected.month &&
                                date.day == _selected.day;

                        final isToday = DateUtils.isSameDay(date, DateTime.now());

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(18),
                            onTap: () => setState(() => _selected = date),
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                color: isSelected
                                    ? _TaskPalette.green
                                    : (isToday
                                    ? Colors.white.withOpacity(0.045)
                                    : Colors.transparent),
                                border: isSelected
                                    ? null
                                    : Border.all(
                                  color: isToday
                                      ? Colors.white.withOpacity(0.12)
                                      : Colors.transparent,
                                ),
                                boxShadow: isSelected
                                    ? [
                                  BoxShadow(
                                    color: _TaskPalette.green.withOpacity(0.18),
                                    blurRadius: 14,
                                    spreadRadius: -6,
                                  ),
                                ]
                                    : null,
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                '$dayNumber',
                                style: TextStyle(
                                  color: isSelected ? Colors.white : _TaskPalette.textMain,
                                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w700,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PickerButtonGhost(
                      label: 'Cancel',
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    _PickerButtonPrimary(
                      label: 'Next',
                      icon: Icons.arrow_forward_rounded,
                      onTap: () => Navigator.pop(
                        context,
                        DateTime(
                          _selected.year,
                          _selected.month,
                          _selected.day,
                          widget.initial.hour,
                          widget.initial.minute,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _TimePickerSheet extends StatefulWidget {
  final DateTime initial;

  const _TimePickerSheet({
    required this.initial,
  });

  @override
  State<_TimePickerSheet> createState() => _TimePickerSheetState();
}

class _TimePickerSheetState extends State<_TimePickerSheet> {
  late DateTime _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initial;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 40, 10, 10),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(30),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(30),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF232833),
                  Color(0xFF181D25),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.08)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select time',
                        style: TextStyle(
                          color: _TaskPalette.textMain,
                          fontWeight: FontWeight.w900,
                          fontSize: 17,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.access_time_filled_rounded,
                      color: _TaskPalette.blue,
                      size: 20,
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(22),
                    color: Colors.white.withOpacity(0.035),
                    border: Border.all(color: Colors.white.withOpacity(0.07)),
                  ),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.schedule_rounded,
                          color: _TaskPalette.green,
                          size: 20,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          DateFormat('hh:mm a').format(_selected),
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: _TaskPalette.textMain,
                            fontWeight: FontWeight.w900,
                            fontSize: 26,
                            letterSpacing: 0.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 220,
                  child: CupertinoTheme(
                    data: const CupertinoThemeData(
                      brightness: Brightness.dark,
                      primaryColor: _TaskPalette.green,
                    ),
                    child: CupertinoDatePicker(
                      mode: CupertinoDatePickerMode.time,
                      use24hFormat: false,
                      initialDateTime: _selected,
                      onDateTimeChanged: (v) => setState(() => _selected = v),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _PickerButtonGhost(
                      label: 'Cancel',
                      icon: Icons.close_rounded,
                      onTap: () => Navigator.pop(context),
                    ),
                    const SizedBox(width: 10),
                    _PickerButtonPrimary(
                      label: 'Apply',
                      icon: Icons.check_rounded,
                      onTap: () => Navigator.pop(context, _selected),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPicker extends StatelessWidget {
  final String value;
  final ValueChanged<String> onChanged;

  const _StatusPicker({
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    PopupMenuEntry<String> item({
      required String value,
      required String label,
      required IconData icon,
      required Color color,
    }) {
      return PopupMenuItem<String>(
        value: value,
        height: 48,
        child: Row(
          children: [
            Icon(icon, size: 18, color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w800,
                  fontSize: 13.4,
                ),
              ),
            ),
          ],
        ),
      );
    }

    PopupMenuEntry<String> divider() {
      return PopupMenuItem<String>(
        enabled: false,
        height: 8,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                Colors.white.withOpacity(0.14),
                Colors.white.withOpacity(0.07),
                Colors.transparent,
              ],
            ),
          ),
        ),
      );
    }

    return PopupMenuButton<String>(
      color: const Color(0xFF1E242D),
      elevation: 14,
      offset: const Offset(0, 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: Colors.white.withOpacity(0.08)),
      ),
      onSelected: onChanged,
      itemBuilder: (_) => [
        item(
          value: 'todo',
          label: 'Todo',
          icon: Icons.radio_button_unchecked_rounded,
          color: const Color(0xFFA47551),
        ),
        divider(),
        item(
          value: 'done',
          label: 'Done',
          icon: Icons.check_circle_rounded,
          color: _TaskPalette.green,
        ),
        divider(),
        item(
          value: 'cancelled',
          label: 'Cancelled',
          icon: Icons.cancel_rounded,
          color: _TaskPalette.red,
        ),
      ],
      child: _MiniSelectCard(
        label: 'Status',
        value: _label(value),
        icon: _icon(value),
        iconColor: _color(value),
      ),
    );
  }

  String _label(String v) {
    switch (v) {
      case 'in_progress':
        return 'In progress';
      case 'needs_review':
        return 'Needs review';
      case 'done':
        return 'Done';
      case 'cancelled':
        return 'Cancelled';
      default:
        return 'Todo';
    }
  }

  IconData _icon(String v) {
    switch (v) {
      case 'in_progress':
        return Icons.timelapse_rounded;
      case 'needs_review':
        return Icons.rate_review_rounded;
      case 'done':
        return Icons.check_circle_rounded;
      case 'cancelled':
        return Icons.cancel_rounded;
      default:
        return Icons.radio_button_unchecked_rounded;
    }
  }

  Color _color(String v) {
    switch (v) {
      case 'in_progress':
        return _TaskPalette.blue;
      case 'needs_review':
        return _TaskPalette.orange;
      case 'done':
        return _TaskPalette.green;
      case 'cancelled':
        return _TaskPalette.red;
      default:
        return const Color(0xFFA47551);
    }
  }
}

class _FormButtons extends StatelessWidget {
  final VoidCallback onCancel;
  final VoidCallback onSubmit;
  final String submitText;
  final IconData? submitIcon;

  const _FormButtons({
    required this.onCancel,
    required this.onSubmit,
    required this.submitText,
    this.submitIcon,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onCancel,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Color(0xFF2A2E35),
                      Color(0xFF20242B),
                    ],
                  ),
                  border: Border.all(
                    color: Colors.white.withOpacity(0.08),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.18),
                      blurRadius: 12,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Text(
                  'Cancel',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.78),
                    fontWeight: FontWeight.w800,
                    fontSize: 14.5,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onSubmit,
              child: Container(
                height: 60,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(22),
                  gradient: const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Color(0xFF2E735D),
                      Color(0xFF245845),
                    ],
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: _TaskPalette.green.withOpacity(0.16),
                      blurRadius: 18,
                      spreadRadius: -6,
                    ),
                  ],
                ),
                alignment: Alignment.center,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (submitIcon != null) ...[
                      Icon(
                        submitIcon,
                        color: Colors.white,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      submitText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _ActionSoftButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? iconColor;

  const _ActionSoftButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF262C37),
                Color(0xFF1E242D),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: iconColor ?? Colors.white,
                size: 19,
              ),
              const SizedBox(width: 10),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 14.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskAttachmentsPreview extends StatelessWidget {
  final String taskId;

  const _TaskAttachmentsPreview({
    required this.taskId,
  });

  String _s(Object? v) => (v ?? '').toString().trim();

  String _role(Map<String, dynamic> item) =>
      _s(item['uploaded_by_role']).toLowerCase();

  Color _uploaderColor(Map<String, dynamic> item) {
    final role = _role(item);

    if (role == 'admin') return const Color(0xFF7C9BFF);
    if (role == 'worker') return _TaskPalette.green;

    return Colors.white.withOpacity(0.18);
  }

  String _uploaderBadge(Map<String, dynamic> item) {
    final role = _role(item);

    if (role == 'admin') return 'A';
    if (role == 'worker') return 'W';

    return '';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: TaskService.watchTaskAttachments(taskId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Map<String, dynamic>>[];

        if (items.isEmpty) return const SizedBox.shrink();

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                const Color(0xFF232833).withOpacity(0.92),
                const Color(0xFF1A1F28).withOpacity(0.96),
                const Color(0xFF141922).withOpacity(0.98),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.attach_file_rounded,
                    color: Colors.white.withOpacity(0.56),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    items.length == 1
                        ? '1 attachment'
                        : '${items.length} attachments',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.60),
                      fontWeight: FontWeight.w800,
                      fontSize: 11.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              LayoutBuilder(
                builder: (context, constraints) {
                  const tileSize = 58.0;
                  const gap = 8.0;

                  final capacityRaw =
                  ((constraints.maxWidth + gap) / (tileSize + gap)).floor();
                  final capacity = capacityRaw < 1 ? 1 : capacityRaw;

                  bool hasExtra = items.length > capacity;
                  int visibleCount = items.length;

                  if (hasExtra) {
                    visibleCount = (capacity - 1).clamp(1, items.length);
                  }

                  final visible = items.take(visibleCount).toList();
                  final extra = items.length - visible.length;

                  Widget buildThumb(Map<String, dynamic> item) {
                    final type = _s(item['attachment_type']).toLowerCase();
                    final url = _s(item['media_url']);
                    final accent = _uploaderColor(item);
                    final badge = _uploaderBadge(item);

                    return Container(
                      width: tileSize,
                      height: tileSize,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        color: Colors.white.withOpacity(0.03),
                        border: Border.all(
                          color: accent.withOpacity(0.30),
                        ),
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          Positioned.fill(
                            child: ClipRRect(
                              borderRadius: BorderRadius.circular(16),
                              child: type == 'image' && url.isNotEmpty
                                  ? Image.network(
                                url,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  Icons.broken_image_outlined,
                                  color: Colors.white.withOpacity(0.40),
                                  size: 18,
                                ),
                              )
                                  : Icon(
                                Icons.insert_drive_file_outlined,
                                color: accent,
                                size: 20,
                              ),
                            ),
                          ),
                          if (badge.isNotEmpty)
                            Positioned(
                              top: -6,
                              left: -4,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF171B22),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: accent.withOpacity(0.70),
                                  ),
                                ),
                                child: Text(
                                  badge,
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 8.5,
                                    height: 1,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    );
                  }

                  return SizedBox(
                    height: tileSize,
                    child: Row(
                      children: [
                        ...List.generate(visible.length, (index) {
                          final item = visible[index];
                          return Padding(
                            padding: EdgeInsets.only(
                              right: index == visible.length - 1 &&
                                  !hasExtra
                                  ? 0
                                  : gap,
                            ),
                            child: buildThumb(item),
                          );
                        }),
                        if (hasExtra)
                          Container(
                            width: tileSize,
                            height: tileSize,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              color: Colors.white.withOpacity(0.035),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.08),
                              ),
                            ),
                            child: Text(
                              '+$extra',
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.60),
                                fontWeight: FontWeight.w900,
                                fontSize: 15,
                              ),
                            ),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}

class _TaskDayGroup {
  final String key;
  final String title;
  final List<Map<String, dynamic>> tasks;

  const _TaskDayGroup({
    required this.key,
    required this.title,
    required this.tasks,
  });
}

class _TaskDayHeader extends StatelessWidget {
  final String title;
  final int count;

  const _TaskDayHeader({
    required this.title,
    required this.count,
  });

  IconData _iconForTitle(String v) {
    final s = v.toLowerCase();
    if (s.contains('today')) return Icons.wb_sunny_rounded;
    if (s.contains('tomorrow')) return Icons.upcoming_rounded;
    if (s.contains('recent')) return Icons.history_rounded;
    if (s.contains('no due')) return Icons.event_busy_rounded;
    return Icons.calendar_today_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
          bottom: Radius.circular(14),
        ),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF232A35),
            Color(0xFF1B212B),
            Color(0xFF151A22),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.28),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _iconForTitle(title),
            size: 18,
            color: Colors.white.withOpacity(0.74),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _TaskPalette.textMain,
                fontWeight: FontWeight.w900,
                fontSize: 15.5,
              ),
            ),
          ),
          Text(
            '$count tasks',
            style: TextStyle(
              color: Colors.white.withOpacity(0.62),
              fontWeight: FontWeight.w800,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _ArchiveModeSwitch extends StatelessWidget {
  final bool showArchived;
  final ValueChanged<bool> onChanged;

  const _ArchiveModeSwitch({
    required this.showArchived,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF2E3440),
            Color(0xFF232834),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.18),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.03),
            blurRadius: 10,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = constraints.maxWidth / 2;

          return Stack(
            children: [
              AnimatedPositioned(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                left: showArchived ? itemWidth : 0,
                top: 0,
                bottom: 0,
                width: itemWidth,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: showArchived
                            ? const [
                          Color(0xFF5A6270),
                          Color(0xFF474F5D),
                        ]
                            : const [
                          Color(0xFF3C7D69),
                          Color(0xFF2D6152),
                        ],
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: showArchived
                              ? Colors.white.withOpacity(0.05)
                              : _TaskPalette.green.withOpacity(0.14),
                          blurRadius: 14,
                          spreadRadius: -6,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  Expanded(
                    child: _ArchiveModeFancyTab(
                      label: 'Active',
                      selected: !showArchived,
                      onTap: () => onChanged(false),
                    ),
                  ),
                  Expanded(
                    child: _ArchiveModeFancyTab(
                      label: 'Archived',
                      selected: showArchived,
                      onTap: () => onChanged(true),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ArchiveModeFancyTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ArchiveModeFancyTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isActiveTab = label == 'Active';

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        overlayColor: WidgetStateProperty.all(Colors.transparent),
        child: Center(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 240),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.08, 0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: selected
                ? Text(
              label,
              key: ValueKey('selected_$label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: label == 'Active'
                    ? Colors.white.withOpacity(0.96)
                    : const Color(0xFFE5E7EB),
                fontWeight: FontWeight.w800,
                fontSize: 12.6,
              ),
            )
                : Text(
              label,
              key: ValueKey('idle_$label'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: Colors.white.withOpacity(0.58),
                fontWeight: FontWeight.w700,
                fontSize: 10.9,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _TaskImageCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final void Function(String url)? onOpen;
  final void Function(Map<String, dynamic> attachment)? onDelete;
  final bool Function(Map<String, dynamic> attachment)? canDelete;
  final ValueChanged<Map<String, dynamic>>? onVisibleImageChanged;

  const _TaskImageCarousel({
    required this.images,
    this.onOpen,
    this.onDelete,
    this.canDelete,
    this.onVisibleImageChanged,
  });

  @override
  State<_TaskImageCarousel> createState() => _TaskImageCarouselState();
}

class _TaskImageCarouselState extends State<_TaskImageCarousel> {
  late final PageController _controller;
  int _page = 1000;

  @override
  void initState() {
    super.initState();
    _controller = PageController(initialPage: _page);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || widget.images.isEmpty) return;
      widget.onVisibleImageChanged?.call(widget.images[_realIndex(_page)]);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  int get _count => widget.images.length;

  int _realIndex(int page) {
    if (_count == 0) return 0;
    return page % _count;
  }

  String _s(Object? v) => (v ?? '').toString().trim();

  String _roleLabel(Map<String, dynamic> image) {
    final role = _s(image['uploaded_by_role']).toLowerCase();
    if (role == 'admin') return 'Admin';
    if (role == 'worker') return 'Worker';
    return '';
  }

  Color _roleColor(String roleLabel) {
    switch (roleLabel) {
      case 'Admin':
        return const Color(0xFF9AB7FF);
      case 'Worker':
        return _TaskPalette.green;
      default:
        return Colors.white70;
    }
  }

  String _proofTitle(Map<String, dynamic> image) {
    final rawMeta = image['proof_meta'];
    if (rawMeta is Map) {
      final meta = Map<String, dynamic>.from(rawMeta);
      final title = _s(meta['subtask_title']).isNotEmpty
          ? _s(meta['subtask_title'])
          : _s(meta['item_title']).isNotEmpty
          ? _s(meta['item_title'])
          : _s(meta['title']);
      if (title.isNotEmpty) return title;
    }
    return '';
  }

  @override
  Widget build(BuildContext context) {
    if (widget.images.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 320,
      child: PageView.builder(
        controller: _controller,
        scrollDirection: Axis.vertical,
        physics: _count > 1
            ? const BouncingScrollPhysics()
            : const NeverScrollableScrollPhysics(),
        onPageChanged: (value) {
          setState(() {
            _page = value;
          });
          widget.onVisibleImageChanged?.call(widget.images[_realIndex(value)]);
        },
        itemBuilder: (context, index) {
          final image = widget.images[_realIndex(index)];
          final url = _s(image['media_url']);
          final fileName = _s(image['file_name']).isEmpty
              ? 'Image'
              : _s(image['file_name']);

          final canDelete = widget.canDelete == null
              ? true
              : widget.canDelete!(image);

          final roleLabel = _roleLabel(image);
          final roleColor = _roleColor(roleLabel);
          final proofSubtaskId = _s(image['proof_subtask_id']);
          final proofTitle = _proofTitle(image);
          final hasProof = proofSubtaskId.isNotEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withOpacity(0.04),
                border: Border.all(
                  color: hasProof
                      ? _TaskPalette.green.withOpacity(0.22)
                      : Colors.white.withOpacity(0.08),
                ),
                boxShadow: hasProof
                    ? [
                  BoxShadow(
                    color: _TaskPalette.green.withOpacity(0.12),
                    blurRadius: 12,
                    spreadRadius: -6,
                  ),
                ]
                    : const [],
              ),
              child: Stack(
                children: [
                  Positioned.fill(
                    child: InkWell(
                      borderRadius: BorderRadius.circular(22),
                      onTap: url.isEmpty
                          ? null
                          : () => widget.onOpen?.call(url),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(22),
                        child: Image.network(
                          url,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            color: Colors.white.withOpacity(0.03),
                            alignment: Alignment.center,
                            child: const Text(
                              'Image failed to load',
                              style: TextStyle(color: Colors.white70),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    top: 12,
                    right: 12,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.10),
                        ),
                      ),
                      child: Text(
                        '${_realIndex(index) + 1}/$_count',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),

                  Positioned(
                    left: 12,
                    right: 12,
                    bottom: 12,
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Expanded(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.48),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    if (roleLabel.isNotEmpty)
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: roleColor.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: roleColor.withOpacity(0.24),
                                          ),
                                        ),
                                        child: Text(
                                          roleLabel,
                                          style: TextStyle(
                                            color: roleColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10.6,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    if (hasProof) ...[
                                      if (roleLabel.isNotEmpty) const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 8,
                                          vertical: 5,
                                        ),
                                        decoration: BoxDecoration(
                                          color: _TaskPalette.green.withOpacity(0.14),
                                          borderRadius: BorderRadius.circular(999),
                                          border: Border.all(
                                            color: _TaskPalette.green.withOpacity(0.24),
                                          ),
                                        ),
                                        child: const Text(
                                          'Proof',
                                          style: TextStyle(
                                            color: _TaskPalette.green,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10.6,
                                            height: 1,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  fileName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12.6,
                                  ),
                                ),
                                if (hasProof) ...[
                                  const SizedBox(height: 6),
                                  Text(
                                    proofTitle.isEmpty
                                        ? 'Linked to checklist item'
                                        : 'For: $proofTitle',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.82),
                                      fontWeight: FontWeight.w700,
                                      fontSize: 11.4,
                                      height: 1.2,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                        if (widget.onDelete != null && canDelete) ...[
                          const SizedBox(width: 8),
                          Material(
                            color: Colors.black.withOpacity(0.45),
                            borderRadius: BorderRadius.circular(16),
                            child: IconButton(
                              onPressed: () => widget.onDelete!(image),
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                color: Colors.redAccent,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _TaskDaySection extends StatelessWidget {
  final String title;
  final int count;
  final List<Widget> children;
  final Widget? leading;

  const _TaskDaySection({
    required this.title,
    required this.count,
    required this.children,
    this.leading,
  });

  IconData _iconForTitle(String v) {
    final s = v.toLowerCase();
    if (s.contains('today')) return Icons.wb_sunny_outlined;
    if (s.contains('tomorrow')) return Icons.upcoming_rounded;
    if (s.contains('recent')) return Icons.history_rounded;
    if (s.contains('no due')) return Icons.event_busy_rounded;
    return Icons.calendar_today_rounded;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2B2F36),
            Color(0xFF23272E),
            Color(0xFF1B1F26),
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
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 14),
              decoration: BoxDecoration(
                color: const Color(0xFF232830),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.white.withOpacity(0.07),
                  ),
                ),
              ),
              child: Row(
                children: [
                  leading ??
                      Icon(
                        _iconForTitle(title),
                        color: const Color(0xFF35E0B6),
                        size: 18,
                      ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                        color: _TaskPalette.textMain,
                        fontWeight: FontWeight.w900,
                        fontSize: 15.5,
                      ),
                    ),
                  ),
                  Text(
                    '$count tasks',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.62),
                      fontWeight: FontWeight.w800,
                      fontSize: 12.6,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 12, 10, 10),
              child: Column(
                children: children,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TaskStripDivider extends StatelessWidget {
  const _TaskStripDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      height: 1,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            Colors.transparent,
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.10),
            Colors.transparent,
          ],
        ),
      ),
    );
  }
}

class _TaskStatChip extends StatelessWidget {
  final String label;
  final int value;
  final IconData icon;
  final Color color;

  const _TaskStatChip({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 46,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.035),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: color.withOpacity(0.16),
        ),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.06),
            blurRadius: 10,
            spreadRadius: -6,
          ),
        ],
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: color,
            ),
            const SizedBox(width: 8),
            Text(
              '$value',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _TaskPalette.textMain,
                fontWeight: FontWeight.w900,
                fontSize: 15,
                height: 1,
              ),
            ),
          ],
        ),
      ),
    );
  }
}