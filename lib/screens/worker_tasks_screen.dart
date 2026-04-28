import 'dart:ui';
import 'dart:io';
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/task_service.dart';

class WorkerTasksScreen extends StatefulWidget {
  const WorkerTasksScreen({super.key, required bool isViewOnly});

  @override
  State<WorkerTasksScreen> createState() => _WorkerTasksScreenState();
}

class _WorkerTasksScreenState extends State<WorkerTasksScreen> {
  String _statusFilter = 'all';
  final Set<String> _shownTerminalSheets = {};

  Timer? _refreshTimer;

  String _s(Object? v) => (v ?? '').toString().trim();

  final Map<String, String?> _reasonTargetSubtaskByTask = {};
  final Map<String, String?> _reasonTargetStatusByTask = {};
  final Map<String, bool> _expandedSubtasks = {};

  final Map<String, TextEditingController> _noteCtrls = {};

  String _uploadedByLabel(Map<String, dynamic> attachment) {
    final role = _s(attachment['uploaded_by_role']).toLowerCase();

    if (role == 'admin') return 'Uploaded by Admin';
    if (role == 'worker') return 'Uploaded by Worker';

    return 'Uploaded';
  }

  bool _isChecklistProofAttachment(Map<String, dynamic> attachment) {
    final fileName = _s(attachment['file_name']).toLowerCase();
    final mediaUrl = Uri.decodeFull(_s(attachment['media_url'])).toLowerCase();
    final filePath = Uri.decodeFull(_s(attachment['file_path'])).toLowerCase();
    final storagePath =
    Uri.decodeFull(_s(attachment['storage_path'])).toLowerCase();

    return fileName.startsWith('proof__') ||
        mediaUrl.contains('proof__') ||
        filePath.contains('proof__') ||
        storagePath.contains('proof__');
  }

  bool _canWorkerDeleteAttachment(Map<String, dynamic> attachment) {
    if (_isChecklistProofAttachment(attachment)) {
      return false;
    }

    return _s(attachment['uploaded_by_role']).toLowerCase() == 'worker';
  }

  PopupMenuItem<String> _statusMenuItem({
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
        return Colors.white.withOpacity(0.72);
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

  String _reasonPrefix(String status) {
    switch (status) {
      case 'blocked':
        return 'Blocked: ';
      case 'not_needed':
        return 'Not needed: ';
      case 'partial':
        return 'Partially done: ';
      default:
        return '';
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

  Future<bool?> _showWorkerTerminalTaskSheet({
    required String taskId,
    required bool isDone,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2B2F36),
                Color(0xFF23272E),
                Color(0xFF1B1F26),
              ],
            ),
            border: Border.all(color: Colors.white24),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isDone ? 'Task completed' : 'Task cancelled',
                  style: const TextStyle(
                    color: _TaskPalette.textMain,
                    fontWeight: FontWeight.w900,
                    fontSize: 18,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  isDone
                      ? 'This task is completed and locked. After you press OK, it will be removed from your active list.'
                      : 'This task was cancelled by admin and is locked. After you press OK, it will be removed from your active list.',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.72),
                    fontWeight: FontWeight.w700,
                    fontSize: 13.6,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _TaskActionCapsule(
                        label: 'Keep for now',
                        icon: Icons.visibility_rounded,
                        onTap: () => Navigator.pop(context, false),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _TaskActionCapsule(
                        label: 'OK',
                        icon: Icons.check_rounded,
                        accentColor: isDone
                            ? _TaskPalette.green
                            : _TaskPalette.red,
                        onTap: () => Navigator.pop(context, true),
                      ),
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

  String _sanitizeChecklistPhotoLabel(String input) {
    final cleaned = input
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    if (cleaned.isEmpty) return 'checklist_item';
    return cleaned.length > 40 ? cleaned.substring(0, 40) : cleaned;
  }

  Future<XFile> _prepareChecklistProofFile(
    XFile file,
    String subtaskTitle,
  ) async {
    try {
      final source = File(file.path);
      final extension = file.name.contains('.')
          ? file.name.substring(file.name.lastIndexOf('.'))
          : '.jpg';
      final safeLabel = _sanitizeChecklistPhotoLabel(subtaskTitle);
      final targetPath =
          '${Directory.systemTemp.path}/proof__${safeLabel}__${DateTime.now().millisecondsSinceEpoch}$extension';
      final copied = await source.copy(targetPath);
      return XFile(copied.path, name: copied.uri.pathSegments.last);
    } catch (_) {
      return file;
    }
  }

  Future<bool> _captureChecklistCompletionPhoto({
    required String taskId,
    required String subtaskTitle,
  }) async {
    try {
      final file = await TaskService.pickTaskImageFromCamera();
      if (file == null) return false;

      final proofFile = await _prepareChecklistProofFile(file, subtaskTitle);

      await TaskService.addWorkerTaskImage(
        taskId: taskId,
        file: proofFile,
      );

      if (!mounted) return true;
      _showTaskToast(
        'Completion photo attached',
        icon: Icons.photo_camera_rounded,
        accent: _TaskPalette.green,
      );
      return true;
    } catch (e) {
      if (!mounted) return false;
      _showTaskToast(
        'Camera upload failed: $e',
        icon: Icons.error_outline_rounded,
        accent: _TaskPalette.red,
      );
      return false;
    }
  }

  Future<void> _addTaskImageFromGallery(String taskId) async {
    try {
      final file = await TaskService.pickTaskImageFromGallery();
      if (file == null) return;

      await TaskService.addWorkerTaskImage(
        taskId: taskId,
        file: file,
      );

      if (!mounted) return;
      setState(() {});
      _showTaskToast(
        'Image uploaded',
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
    return 3;
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

        if (_groupRank(a) == 2) return ad.compareTo(bd);
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

  @override
  void initState() {
    super.initState();

    _refreshTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();

    for (final c in _noteCtrls.values) {
      c.dispose();
    }

    _hideTaskToast();
    super.dispose();
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

  Future<void> _addTaskImageFromCamera(String taskId) async {
    try {
      final file = await TaskService.pickTaskImageFromCamera();
      if (file == null) return;

      await TaskService.addWorkerTaskImage(
        taskId: taskId,
        file: file,
      );

      if (!mounted) return;
      setState(() {});
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

      await TaskService.addWorkerTaskFile(
        taskId: taskId,
        file: file,
      );

      if (!mounted) return;
      setState(() {});
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


  Future<bool> _confirmChecklistAction({
    required String title,
    required String message,
    required IconData icon,
    required Color accent,
  }) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(horizontal: 16),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(28),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
              child: Container(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(28),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF232833).withOpacity(0.97),
                      const Color(0xFF1A1F28).withOpacity(0.985),
                      const Color(0xFF141922).withOpacity(0.99),
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
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                accent.withOpacity(0.92),
                                accent.withOpacity(0.68),
                              ],
                            ),
                          ),
                          child: Icon(icon, color: Colors.white, size: 20),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: _TaskPalette.textMain,
                              fontWeight: FontWeight.w900,
                              fontSize: 19,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Text(
                      message,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.72),
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
                                  gradient: LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      accent.withOpacity(0.92),
                                      accent.withOpacity(0.68),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: accent.withOpacity(0.18),
                                      blurRadius: 12,
                                      spreadRadius: -4,
                                    ),
                                  ],
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.check_rounded,
                                      color: Colors.white,
                                      size: 18,
                                    ),
                                    SizedBox(width: 8),
                                    Text(
                                      'Continue',
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

    return result == true;
  }

  Widget _buildInlineTaskDetails({
    required Map<String, dynamic> task,
    required int taskIndex,
  }) {
    final taskId = _s(task['id']);
    if (taskId.isEmpty) return const SizedBox.shrink();

    final noteCtrl = _noteCtrls.putIfAbsent(
      taskId,
      () => TextEditingController(),
    );
    String status = _s(task['status']).isEmpty ? 'todo' : _s(task['status']);

    final description = _s(task['description']);
    final cleanDescription = TaskService.stripChecklistFromDescription(description);
    final priority = _s(task['priority']).toLowerCase();
    final savedWorkerNote = _s(task['worker_note']);

    final acknowledgedAt = _s(task['worker_acknowledged_at']);
    final statusLower = _s(task['status']).toLowerCase();
    final isTerminalTask = statusLower == 'done' || statusLower == 'cancelled';

    if (isTerminalTask &&
        acknowledgedAt.isEmpty &&
        !_shownTerminalSheets.contains(taskId)) {
      _shownTerminalSheets.add(taskId);

      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (!mounted) return;

        final confirmed = await _showWorkerTerminalTaskSheet(
          taskId: taskId,
          isDone: statusLower == 'done',
        );

        if (!mounted) return;

        if (confirmed == true) {
          try {
            await TaskService.acknowledgeWorkerTerminalTask(taskId: taskId);
            if (!mounted) return;
            setState(() {});
          } catch (e) {
            if (!mounted) return;
            _showTaskToast(
              'Acknowledge failed: $e',
              icon: Icons.error_outline_rounded,
              accent: _TaskPalette.red,
            );
          }
        }
      });
    }

    final dueRaw = _s(task['due_at']);
    final dueText = dueRaw.isEmpty
        ? ''
        : (() {
            final dt = DateTime.tryParse(dueRaw)?.toLocal();
            if (dt == null) return '';
            return DateFormat('MMM d, HH:mm').format(dt);
          })();

    final List<Color> cardGradient = taskIndex.isOdd
        ? const [
            Color(0xFF3A3E45),
            Color(0xFF2E3239),
          ]
        : const [
            Color(0xFF30343B),
            Color(0xFF24282F),
          ];

    return StatefulBuilder(
      builder: (context, setLocalState) {
        final reasonTargetSubtaskId = _reasonTargetSubtaskByTask[taskId];
        final reasonTargetStatus = _reasonTargetStatusByTask[taskId];
        final isReasonMode =
            reasonTargetSubtaskId != null && reasonTargetStatus != null;

        bool isDoneNow() => _s(status).toLowerCase() == 'done';
        bool isCancelledNow() => _s(status).toLowerCase() == 'cancelled';
        bool isLockedNow() => isDoneNow() || isCancelledNow();
        final saveLocked = isLockedNow() || isReasonMode;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.fromLTRB(0, 12, 0, 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: cardGradient,
            ),
            border: Border(
              bottom: BorderSide(
                color: Colors.white.withOpacity(0.06),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  height: 52,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
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
                        child: IgnorePointer(
                          ignoring: saveLocked,
                          child: Opacity(
                            opacity: saveLocked ? 0.55 : 1,
                            child: Center(
                              child: PopupMenuButton<String>(
                                padding: EdgeInsets.zero,
                                color: const Color(0xFF20242D),
                                elevation: 14,
                                offset: const Offset(0, 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                  side: BorderSide(
                                    color: Colors.white.withOpacity(0.08),
                                  ),
                                ),
                                onSelected: isLockedNow()
                                    ? (_) {}
                                    : (v) => setLocalState(() => status = v),
                                itemBuilder: (_) => [
                                  _statusMenuItem(
                                    value: 'todo',
                                    label: 'Todo',
                                    icon: Icons.radio_button_unchecked_rounded,
                                    color: const Color(0xFFA47551),
                                  ),
                                  _statusMenuItem(
                                    value: 'in_progress',
                                    label: 'In progress',
                                    icon: Icons.timelapse_rounded,
                                    color: _TaskPalette.blue,
                                  ),
                                  _statusMenuItem(
                                    value: 'needs_review',
                                    label: 'Needs review',
                                    icon: Icons.rate_review_rounded,
                                    color: _TaskPalette.orange,
                                  ),
                                ],
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      _taskStatusIcon(_s(status).toLowerCase()),
                                      size: 14,
                                      color: _statusColor(_s(status).toLowerCase()),
                                    ),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        _statusLabel(_s(status).toLowerCase()),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: Colors.white.withOpacity(0.86),
                                          fontWeight: FontWeight.w800,
                                          fontSize: 11.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 5),
                                    Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 16,
                                      color: Colors.white.withOpacity(0.58),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: Colors.white.withOpacity(0.08),
                      ),
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
                                color: _priorityColor(priority),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  priority,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: _priorityColor(priority),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 11.8,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        width: 1,
                        height: 18,
                        color: Colors.white.withOpacity(0.08),
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
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(18),
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
                        color: Colors.black.withOpacity(0.24),
                        blurRadius: 14,
                        spreadRadius: -6,
                        offset: const Offset(0, 8),
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
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.notes_rounded,
                                color: Color(0xFFF59E0B),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                cleanDescription,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.72),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.2,
                                  height: 1.30,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (savedWorkerNote.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(
                                Icons.campaign_rounded,
                                color: Color(0xFF8EA0FF),
                                size: 16,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                savedWorkerNote,
                                style: TextStyle(
                                  color: Colors.white.withOpacity(0.78),
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.1,
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

                          final doneCount = subtasks.where((e) => _s(e['status']).toLowerCase() == 'done' || e['is_done'] == true).length;
                          final totalCount = subtasks.length;
                          final countColor = doneCount == totalCount
                              ? _TaskPalette.green
                              : const Color(0xFFFB7185);

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
                              ...List.generate(subtasks.length, (index) {
                                final item = subtasks[index];
                                final subtaskId = _s(item['id']);
                                final itemStatus = _s(item['status']).toLowerCase().isEmpty
                                    ? (item['is_done'] == true ? 'done' : 'todo')
                                    : _s(item['status']).toLowerCase();
                                final title = _s(item['title']);
                                final statusNote = _s(item['status_note']);
                                final isExpanded = _expandedSubtasks[subtaskId] == true;
                                final bool showArrow = itemStatus == 'blocked' ||
                                    itemStatus == 'not_needed' ||
                                    itemStatus == 'partial';
                                final bool showCamera = itemStatus == 'todo';
                                final bool showReason = itemStatus == 'todo';
                                final bool showNothing = itemStatus == 'done';

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
                                        setLocalState(() {
                                          for (final st in subtasks) {
                                            final id = _s(st['id']);
                                            if (id.isNotEmpty && id != subtaskId) {
                                              _expandedSubtasks[id] = false;
                                            }
                                          }

                                          _expandedSubtasks[subtaskId] = !isExpanded;
                                        });
                                      }
                                          : null,
                                      child: Container(
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
                                            color: Colors.white.withOpacity(0.07),
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
                                                const SizedBox(width: 10),
                                                Expanded(
                                                  child: Text(
                                                    title,
                                                    style: TextStyle(
                                                      color: Colors.white.withOpacity(
                                                        itemStatus == 'done' ? 0.72 : 0.90,
                                                      ),
                                                      fontWeight: FontWeight.w700,
                                                      fontSize: 13,
                                                      height: 1.25,
                                                      decoration: itemStatus == 'done'
                                                          ? TextDecoration.lineThrough
                                                          : null,
                                                      decorationColor: Colors.white.withOpacity(0.42),
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                if (showCamera) ...[
                                                  _ChecklistMiniActionBtn(
                                                    icon: Icons.photo_camera_rounded,
                                                    color: _TaskPalette.green,
                                                    onTap: isLockedNow()
                                                        ? null
                                                        : () async {
                                                      final confirmed =
                                                      await _confirmChecklistAction(
                                                        title: 'Complete checklist item?',
                                                        message:
                                                        'After confirmation, this item will be marked as done and the worker action buttons for it will disappear.',
                                                        icon: Icons.photo_camera_rounded,
                                                        accent: _TaskPalette.green,
                                                      );

                                                      if (!confirmed) return;

                                                      final captured =
                                                      await _captureChecklistCompletionPhoto(
                                                        taskId: taskId,
                                                        subtaskTitle: title,
                                                      );

                                                      if (!captured) return;

                                                      try {
                                                        await TaskService.setTaskSubtaskStatus(
                                                          subtaskId: subtaskId,
                                                          status: 'done',
                                                        );

                                                        if (!mounted) return;
                                                        setState(() {});
                                                        _showTaskToast(
                                                          'Checklist item completed',
                                                          icon: Icons.check_circle_rounded,
                                                          accent: _TaskPalette.green,
                                                        );
                                                      } catch (e) {
                                                        if (!mounted) return;
                                                        _showTaskToast(
                                                          'Checklist update failed: $e',
                                                          icon: Icons.error_outline_rounded,
                                                          accent: _TaskPalette.red,
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],

                                                if (showReason) ...[
                                                  if (showCamera) const SizedBox(width: 6),
                                                  _ChecklistMiniActionBtn(
                                                    icon: Icons.block_rounded,
                                                    color: _TaskPalette.orange,
                                                    onTap: isLockedNow()
                                                        ? null
                                                        : () async {
                                                      final reason =
                                                      await showModalBottomSheet<String>(
                                                        context: context,
                                                        backgroundColor: Colors.transparent,
                                                        builder: (_) {
                                                          return Container(
                                                            margin: const EdgeInsets.fromLTRB(
                                                              12,
                                                              0,
                                                              12,
                                                              12,
                                                            ),
                                                            padding: const EdgeInsets.all(12),
                                                            decoration: BoxDecoration(
                                                              borderRadius: BorderRadius.circular(22),
                                                              gradient: const LinearGradient(
                                                                begin: Alignment.topLeft,
                                                                end: Alignment.bottomRight,
                                                                colors: [
                                                                  Color(0xFF2C3037),
                                                                  Color(0xFF23272E),
                                                                  Color(0xFF1D2128),
                                                                ],
                                                              ),
                                                              border: Border.all(
                                                                color: Colors.white24,
                                                              ),
                                                            ),
                                                            child: SafeArea(
                                                              top: false,
                                                              child: Column(
                                                                mainAxisSize: MainAxisSize.min,
                                                                children: [
                                                                  ListTile(
                                                                    leading: const Icon(
                                                                      Icons.block_rounded,
                                                                      color: _TaskPalette.orange,
                                                                    ),
                                                                    title: const Text(
                                                                      'Blocked',
                                                                      style: TextStyle(
                                                                        color: Colors.white,
                                                                      ),
                                                                    ),
                                                                    onTap: () => Navigator.pop(
                                                                      context,
                                                                      'blocked',
                                                                    ),
                                                                  ),
                                                                  ListTile(
                                                                    leading: const Icon(
                                                                      Icons.remove_circle_outline_rounded,
                                                                      color: _TaskPalette.orange,
                                                                    ),
                                                                    title: const Text(
                                                                      'Not needed',
                                                                      style: TextStyle(
                                                                        color: Colors.white,
                                                                      ),
                                                                    ),
                                                                    onTap: () => Navigator.pop(
                                                                      context,
                                                                      'not_needed',
                                                                    ),
                                                                  ),
                                                                  ListTile(
                                                                    leading: const Icon(
                                                                      Icons.timelapse_rounded,
                                                                      color: _TaskPalette.orange,
                                                                    ),
                                                                    title: const Text(
                                                                      'Partially done',
                                                                      style: TextStyle(
                                                                        color: Colors.white,
                                                                      ),
                                                                    ),
                                                                    onTap: () => Navigator.pop(
                                                                      context,
                                                                      'partial',
                                                                    ),
                                                                  ),
                                                                ],
                                                              ),
                                                            ),
                                                          );
                                                        },
                                                      );

                                                      if (reason == null || reason.isEmpty) return;

                                                      final reasonLabel = reason == 'blocked'
                                                          ? 'Blocked'
                                                          : reason == 'not_needed'
                                                          ? 'Not needed'
                                                          : 'Partially done';

                                                      final confirmed =
                                                      await _confirmChecklistAction(
                                                        title: 'Change checklist item status?',
                                                        message:
                                                        'The item will be switched to "$reasonLabel" and the worker action buttons for it will disappear.',
                                                        icon: Icons.block_rounded,
                                                        accent: _TaskPalette.orange,
                                                      );

                                                      if (!confirmed) return;

                                                      try {
                                                        await TaskService.setTaskSubtaskStatus(
                                                          subtaskId: subtaskId,
                                                          status: reason,
                                                        );

                                                        setLocalState(() {
                                                          for (final st in subtasks) {
                                                            final id = _s(st['id']);
                                                            if (id.isNotEmpty && id != subtaskId) {
                                                              _expandedSubtasks[id] = false;
                                                            }
                                                          }

                                                          _reasonTargetSubtaskByTask[taskId] = subtaskId;
                                                          _reasonTargetStatusByTask[taskId] = reason;
                                                          _expandedSubtasks[subtaskId] = true;
                                                          noteCtrl.text = _reasonPrefix(reason);
                                                          noteCtrl.selection = TextSelection.collapsed(
                                                            offset: noteCtrl.text.length,
                                                          );
                                                        });
                                                      } catch (e) {
                                                        if (!mounted) return;
                                                        _showTaskToast(
                                                          'Status update failed: $e',
                                                          icon: Icons.error_outline_rounded,
                                                          accent: _TaskPalette.red,
                                                        );
                                                      }
                                                    },
                                                  ),
                                                ],

                                                if (showArrow) ...[
                                                  const SizedBox(width: 6),
                                                  _ChecklistMiniActionBtn(
                                                    icon: isExpanded
                                                        ? Icons.keyboard_arrow_up_rounded
                                                        : Icons.keyboard_arrow_down_rounded,
                                                    color: _TaskPalette.green,
                                                    onTap: () {
                                                      setLocalState(() {
                                                        for (final st in subtasks) {
                                                          final id = _s(st['id']);
                                                          if (id.isNotEmpty && id != subtaskId) {
                                                            _expandedSubtasks[id] = false;
                                                          }
                                                        }

                                                        _expandedSubtasks[subtaskId] = !isExpanded;
                                                      });
                                                    },
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
                                                key: ValueKey('reason_open_$subtaskId'),
                                                padding: const EdgeInsets.only(top: 10),
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
                                                    statusNote.isEmpty ? 'No reason added yet.' : statusNote,
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
                                                key: ValueKey('reason_closed_$subtaskId'),
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
              const SizedBox(height: 14),
              if (isReasonMode) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: Colors.white.withOpacity(0.04),
                      border: Border.all(
                        color: _TaskPalette.green.withOpacity(0.16),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Padding(
                          padding: EdgeInsets.only(top: 1),
                          child: Icon(
                            Icons.edit_note_rounded,
                            color: _TaskPalette.green,
                            size: 16,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Write the reason for this checklist item and tap Send.',
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.74),
                              fontWeight: FontWeight.w700,
                              fontSize: 12.6,
                              height: 1.30,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 10),
              ],
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IgnorePointer(
                  ignoring: isDoneNow() || isLockedNow(),
                  child: Opacity(
                    opacity: (isDoneNow() || isLockedNow()) ? 0.55 : 1,
                    child: _TaskInput(
                      controller: noteCtrl,
                      hint: isReasonMode
                          ? 'Write the reason and tap Send'
                          : isCancelledNow()
                              ? 'Task was cancelled by admin'
                              : isDoneNow()
                                  ? 'Task is completed'
                                  : 'Worker note',
                      maxLines: 5,
                      icon: Icons.campaign_rounded,
                      iconColor: const Color(0xFF8EA0FF),
                      trailingIcon: isReasonMode ? Icons.send_rounded : null,
                      trailingIconColor: _TaskPalette.green,
                      onTrailingTap: isReasonMode
                          ? () async {
                              if (isDoneNow() || isLockedNow()) return;
                              final text = noteCtrl.text.trim();
                              if (text.isEmpty) return;
                              try {
                                await TaskService.setTaskSubtaskStatus(
                                  subtaskId: reasonTargetSubtaskId!,
                                  status: reasonTargetStatus!,
                                  note: text,
                                );
                                setLocalState(() {
                                  _expandedSubtasks[reasonTargetSubtaskId] = true;
                                  _reasonTargetSubtaskByTask.remove(taskId);
                                  _reasonTargetStatusByTask.remove(taskId);
                                  noteCtrl.clear();
                                });
                                if (!mounted) return;
                                _showTaskToast(
                                  'Reason sent',
                                  icon: Icons.send_rounded,
                                  accent: _TaskPalette.green,
                                );
                              } catch (e) {
                                if (!mounted) return;
                                _showTaskToast(
                                  'Reason send failed: $e',
                                  icon: Icons.error_outline_rounded,
                                  accent: _TaskPalette.red,
                                );
                              }
                            }
                          : null,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
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

                    final attachments = snapshot.data ?? <Map<String, dynamic>>[];

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
                      return _s(a['attachment_type']).toLowerCase() == 'image' &&
                          _s(a['media_url']).isNotEmpty;
                    }).toList();

                    final fileAttachments = attachments.where((a) {
                      return _s(a['attachment_type']).toLowerCase() != 'image';
                    }).toList();

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (imageAttachments.isNotEmpty) ...[
                          _TaskImageCarousel(
                            images: imageAttachments,
                            onOpen: _openImagePreview,
                            onDelete: (attachment) => _deleteAttachment(attachment),
                            canDelete: _canWorkerDeleteAttachment,
                          ),
                          const SizedBox(height: 10),
                        ],
                        ...fileAttachments.map((attachment) {
                          final url = _s(attachment['media_url']);
                          final fileName = _s(attachment['file_name']).isEmpty
                              ? 'File'
                              : _s(attachment['file_name']);
                          final uploadedBy = _uploadedByLabel(attachment);

                          final role = _s(attachment['uploaded_by_role']).toLowerCase();
                          final accent = role == 'admin'
                              ? const Color(0xFF7C9BFF)
                              : role == 'worker'
                                  ? _TaskPalette.green
                                  : Colors.white.withOpacity(0.10);
                          final canDelete = _canWorkerDeleteAttachment(attachment);

                          return Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: InkWell(
                              borderRadius: BorderRadius.circular(16),
                              onTap: url.isEmpty ? null : () => _openAttachmentUrl(url),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.04),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: accent.withOpacity(
                                      role.isEmpty ? 0.08 : 0.22,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Icon(
                                      Icons.insert_drive_file_outlined,
                                      color: accent,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            fileName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(
                                              color: _TaskPalette.textMain,
                                              fontWeight: FontWeight.w800,
                                            ),
                                          ),
                                          const SizedBox(height: 3),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: accent.withOpacity(0.12),
                                              borderRadius: BorderRadius.circular(999),
                                              border: Border.all(
                                                color: accent.withOpacity(0.28),
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
                                    if (canDelete)
                                      IconButton(
                                        onPressed: () => _deleteAttachment(attachment),
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
                          onTap: (isDoneNow() || isLockedNow())
                              ? null
                              : () => _addTaskImageFromGallery(taskId),
                        ),
                        const SizedBox(width: 10),
                        _MediaCapsuleAction(
                          label: 'Camera',
                          icon: Icons.photo_camera_outlined,
                          iconColor: Colors.white,
                          onTap: (isDoneNow() || isLockedNow())
                              ? null
                              : () => _addTaskImageFromCamera(taskId),
                        ),
                        const SizedBox(width: 10),
                        _MediaCapsuleAction(
                          label: 'Attach',
                          icon: Icons.attach_file_rounded,
                          iconColor: Colors.white.withOpacity(0.88),
                          onTap: (isDoneNow() || isLockedNow())
                              ? null
                              : () => _addTaskFile(taskId),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (isDoneNow()) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Text(
                      'Task is completed. You can reopen it by changing the status.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.2,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
              if (isCancelledNow()) ...[
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.04),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: Colors.white.withOpacity(0.08),
                      ),
                    ),
                    child: Text(
                      'Task was cancelled by admin. Editing is locked.',
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.62),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.2,
                        height: 1.3,
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 14),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: IgnorePointer(
                  ignoring: saveLocked,
                  child: Opacity(
                    opacity: saveLocked ? 0.45 : 1,
                    child: SizedBox(
                      width: double.infinity,
                      child: _TaskActionCapsule(
                        label: 'Save',
                        icon: Icons.check_rounded,
                        accentColor: _TaskPalette.green,
                        onTap: saveLocked
                            ? null
                            : () async {
                          final text = noteCtrl.text.trim();

                          try {
                            await TaskService.updateWorkerTask(
                              taskId: taskId,
                              status: _s(status).isEmpty ? 'todo' : _s(status),
                              workerNote: text.isEmpty ? savedWorkerNote : text,
                            );

                            setLocalState(() {
                              if (text.isNotEmpty) {
                                noteCtrl.clear();
                              }
                            });

                            if (!mounted) return;
                            setState(() {});
                            _showTaskToast(
                              text.isEmpty ? 'Status saved' : 'Task updated',
                              icon: Icons.check_circle_rounded,
                              accent: _TaskPalette.green,
                            );
                          } catch (e) {
                            if (!mounted) return;
                            _showTaskToast(
                              'Task update failed: $e',
                              icon: Icons.error_outline_rounded,
                              accent: _TaskPalette.red,
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _TaskPalette.bg,
      body: Stack(
        children: [
          const _TasksBackground(),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _TasksHeader(
                    title: 'Tasks',
                    subtitle: 'Worker task board',
                    onBack: () => Navigator.pop(context),
                  ),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: TaskService.watchWorkerTasks(),
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

                      var tasks = snapshot.data ?? <Map<String, dynamic>>[];

                      final now = DateTime.now();
                      final today = DateTime(now.year, now.month, now.day);

                      tasks = tasks.where((t) {
                        final status = _s(t['status']).toLowerCase();

                        if (status != 'done') return true;

                        final completedAt = DateTime.tryParse(_s(t['completed_at']))?.toLocal();
                        if (completedAt == null) return true;

                        final completedDay = DateTime(
                          completedAt.year,
                          completedAt.month,
                          completedAt.day,
                        );

                        return completedDay == today;
                      }).toList();

                      tasks = tasks.where((t) {
                        final due = DateTime.tryParse(_s(t['due_at']))?.toLocal();
                        if (due == null) return true;

                        return !due.isBefore(DateTime.now());
                      }).toList();

                      if (tasks.isNotEmpty) {
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          TaskService.markWorkerTaskEventsSeen(
                            taskIds: tasks
                                .map((e) => _s(e['id']))
                                .where((e) => e.isNotEmpty)
                                .toList(),
                          );
                        });
                      }

                      if (_statusFilter != 'all') {
                        tasks = tasks
                            .where((t) =>
                        _s(t['status']).toLowerCase() == _statusFilter)
                            .toList();
                      }

                      if (tasks.isEmpty) {
                        return const _TasksEmptyState();
                      }

                      final groups = _groupTasksByDay(tasks);

                      return ListView.builder(
                        padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
                        itemCount: groups.length,
                        itemBuilder: (context, groupIndex) {
                          final group = groups[groupIndex];

                          return Padding(
                            padding: EdgeInsets.only(
                              bottom: groupIndex == groups.length - 1 ? 0 : 14,
                            ),
                            child: _TaskDaySection(
                              title: group.title,
                              count: group.tasks.length,
                              leading: group.tasks.length == 1
                                  ? _DeadlineIndexBadge(
                                indexLabel: '01',
                                createdAtRaw: _s(group.tasks.first['created_at']),
                                dueAtRaw: _s(group.tasks.first['due_at']),
                                statusRaw: _s(group.tasks.first['status']),
                              )
                                  : null,
                              children: List.generate(group.tasks.length, (taskIndex) {
                                final task = group.tasks[taskIndex];

                                return Padding(
                                  padding: EdgeInsets.only(
                                    bottom: taskIndex == group.tasks.length - 1 ? 0 : 12,
                                  ),
                                  child: _buildInlineTaskDetails(
                                    task: task,
                                    taskIndex: taskIndex,
                                  ),
                                );
                              }),
                            ),
                          );
                        },
                      );
                    },
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

class _TaskPalette {
  static const bg = Color(0xFF0B0D12);
  static const cardTop = Color(0xFF232833);
  static const cardBottom = Color(0xFF1A1F28);
  static const pill = Color(0xFF1F2025);
  static const pillBorder = Color(0xFF34353C);
  static const textMain = Color(0xFFEDEFF6);
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

  const _TasksHeader({
    required this.title,
    required this.subtitle,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(26),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 14, 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF2C3037),
                Color(0xFF23272E),
                Color(0xFF1B1F26),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.34),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.025),
                blurRadius: 10,
                spreadRadius: -6,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              _HeaderBtn(
                icon: Icons.arrow_back_ios_new_rounded,
                onTap: onBack,
              ),
              const SizedBox(width: 12),
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
                        letterSpacing: 0.1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.54),
                        fontWeight: FontWeight.w700,
                        fontSize: 12.5,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 42,
                height: 42,
                alignment: Alignment.center,
                child: const Icon(
                  Icons.assignment_rounded,
                  color: _TaskPalette.green,
                  size: 27,
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
  final VoidCallback onTap;

  const _HeaderBtn({
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
            borderRadius: BorderRadius.circular(18),
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Color(0xFF353A42),
                Color(0xFF262B33),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                offset: const Offset(0, 5),
              ),
            ],
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
      default:
        return Icons.apps_rounded;
    }
  }

  Color _iconColor(String v) {
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
        return Colors.white.withOpacity(0.80);
    }
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
          BoxShadow(
            color: Colors.white.withOpacity(0.02),
            blurRadius: 10,
            spreadRadius: -6,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _MediaCapsuleAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final VoidCallback? onTap;

  const _MediaCapsuleAction({
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Expanded(
      child: Opacity(
        opacity: disabled ? 0.45 : 1,
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
                  BoxShadow(
                    color: Colors.white.withOpacity(0.03),
                    blurRadius: 10,
                    spreadRadius: -6,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    icon,
                    size: 22,
                    color: iconColor,
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
      ),
    );
  }
}

class _ChecklistMiniActionBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback? onTap;

  const _ChecklistMiniActionBtn({
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;

    return Opacity(
      opacity: disabled ? 0.42 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Icon(
              icon,
              size: 18,
              color: color,
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
  final VoidCallback? onTap;
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
    final Color resolvedTextColor = isGreen || isRed ? Colors.white : _TaskPalette.textMain;

    return Opacity(
      opacity: onTap == null ? 0.45 : 1,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(22),
          onTap: onTap,
          child: Container(
            height: height,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(22),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isGreen
                    ? const [
                        Color(0xFF356657),
                        Color(0xFF274C41),
                      ]
                    : isRed
                        ? const [
                            Color(0xFF7A2433),
                            Color(0xFF5A1B26),
                          ]
                        : const [
                            Color(0xFF232833),
                            Color(0xFF1A1F28),
                          ],
              ),
              border: Border.all(
                color: isGreen
                    ? _TaskPalette.green.withOpacity(0.20)
                    : isRed
                        ? _TaskPalette.red.withOpacity(0.24)
                        : Colors.white.withOpacity(0.08),
              ),
              boxShadow: [
                BoxShadow(
                  color: isGreen
                      ? _TaskPalette.green.withOpacity(0.14)
                      : isRed
                          ? _TaskPalette.red.withOpacity(0.18)
                          : Colors.black.withOpacity(0.20),
                  blurRadius: 12,
                  spreadRadius: -4,
                ),
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 10,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  icon,
                  color: resolvedTextColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Text(
                  label,
                  style: TextStyle(
                    color: resolvedTextColor,
                    fontWeight: FontWeight.w800,
                    fontSize: 14.4,
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

class _FieldBox extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _FieldBox({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(horizontal: 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.04),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withOpacity(0.72), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              value.replaceAll('_', ' '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: _TaskPalette.textMain,
                fontWeight: FontWeight.w800,
                fontSize: 13.2,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.42),
              fontWeight: FontWeight.w700,
              fontSize: 11.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskInput extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final int maxLines;
  final IconData? icon;
  final Color? iconColor;
  final IconData? trailingIcon;
  final Color? trailingIconColor;
  final VoidCallback? onTrailingTap;

  const _TaskInput({
    required this.controller,
    required this.hint,
    required this.maxLines,
    this.icon,
    this.iconColor,
    this.trailingIcon,
    this.trailingIconColor,
    this.onTrailingTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1A1E25),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (icon != null) ...[
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: Icon(
                icon,
                color: iconColor ?? Colors.white.withOpacity(0.55),
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: maxLines,
              style: const TextStyle(
                color: _TaskPalette.textMain,
                fontWeight: FontWeight.w700,
              ),
              decoration: InputDecoration(
                border: InputBorder.none,
                hintText: hint,
                hintStyle: TextStyle(
                  color: Colors.white.withOpacity(0.34),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: 10),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: onTrailingTap,
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(14),
                      color: Colors.transparent,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      trailingIcon,
                      size: 18,
                      color: trailingIconColor ?? _TaskPalette.green,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
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

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: TaskService.watchTaskSubtasks(taskId),
      builder: (context, snapshot) {
        final subtasks = snapshot.data ?? const <Map<String, dynamic>>[];
        if (subtasks.isEmpty) return const SizedBox.shrink();

        final visible = subtasks.take(2).toList();
        final doneCount = subtasks.where((e) => e['is_done'] == true).length;
        final totalCount = subtasks.length;
        final hasMore = totalCount > visible.length;
        final countColor = doneCount == totalCount
            ? _TaskPalette.green
            : const Color(0xFFFB7185);

        final content = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ...List.generate(visible.length, (index) {
              final item = visible[index];
              final isDone = item['is_done'] == true;
              final title = (item['title'] ?? '').toString().trim();

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
                      color: Colors.white.withOpacity(0.07),
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
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(
                        isDone
                            ? Icons.task_alt_rounded
                            : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isDone ? _TaskPalette.green : _TaskPalette.red,
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
                            decoration: isDone ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.white.withOpacity(0.42),
                          ),
                        ),
                      ),
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
                    fontSize: 13.0,
                  ),
                ),
              ],
            ),
          ],
        );

        if (embedded) return content;

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
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
                color: Colors.black.withOpacity(0.18),
                blurRadius: 10,
                spreadRadius: -6,
              ),
            ],
          ),
          child: content,
        );
      },
    );
  }
}


class _TasksEmptyState extends StatelessWidget {
  const _TasksEmptyState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 18),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
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
            border: Border.all(color: Colors.white.withOpacity(0.08)),
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
              Icon(
                Icons.task_alt_rounded,
                size: 28,
                color: Colors.white.withOpacity(0.56),
              ),
              const SizedBox(height: 10),
              const Text(
                'No tasks yet',
                style: TextStyle(
                  color: _TaskPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'When admin creates a task, it will appear here.',
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

class _TaskAttachmentsPreview extends StatelessWidget {
  final String taskId;

  const _TaskAttachmentsPreview({
    required this.taskId,
  });

  String _s(Object? v) => (v ?? '').toString().trim();

  Color _roleColor(Map<String, dynamic> item) {
    final role = _s(item['uploaded_by_role']).toLowerCase();
    if (role == 'admin') return const Color(0xFF9AB7FF);
    if (role == 'worker') return _TaskPalette.green;
    return Colors.white.withOpacity(0.18);
  }

  String _roleBadge(Map<String, dynamic> item) {
    final role = _s(item['uploaded_by_role']).toLowerCase();
    if (role == 'admin') return 'Admin';
    if (role == 'worker') return 'Worker';
    return '';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: TaskService.watchTaskAttachments(taskId),
      builder: (context, snapshot) {
        final items = snapshot.data ?? const <Map<String, dynamic>>[];
        if (items.isEmpty) return const SizedBox.shrink();

        final visible = items.take(3).toList();
        final extra = items.length - visible.length;

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
                    color: Colors.white.withOpacity(0.46),
                    size: 16,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    items.length == 1 ? '1 attachment' : '${items.length} attachments',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.56),
                      fontWeight: FontWeight.w800,
                      fontSize: 11.8,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                height: 56,
                child: Row(
                  children: [
                    ...visible.map((item) {
                      final type = _s(item['attachment_type']).toLowerCase();
                      final url = _s(item['media_url']);
                      final accent = _roleColor(item);
                      final badge = _roleBadge(item);

                      return Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(14),
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Colors.white.withOpacity(0.035),
                                    Colors.white.withOpacity(0.02),
                                  ],
                                ),
                                border: Border.all(
                                  color: Colors.white.withOpacity(0.06),
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(14),
                                child: type == 'image' && url.isNotEmpty
                                    ? Image.network(
                                        url,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) => Icon(
                                          Icons.broken_image_outlined,
                                          color: Colors.white.withOpacity(0.34),
                                          size: 18,
                                        ),
                                      )
                                    : Icon(
                                        Icons.insert_drive_file_outlined,
                                        color: Colors.white.withOpacity(0.40),
                                        size: 20,
                                      ),
                              ),
                            ),
                            if (badge.isNotEmpty)
                              Positioned(
                                top: -6,
                                right: -4,
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
                                      fontSize: 8.2,
                                      height: 1,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      );
                    }),
                    if (extra > 0)
                      Container(
                        width: 56,
                        height: 56,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(14),
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              Colors.white.withOpacity(0.035),
                              Colors.white.withOpacity(0.02),
                            ],
                          ),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.06),
                          ),
                        ),
                        child: Text(
                          '+$extra',
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.52),
                            fontWeight: FontWeight.w900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                  ],
                ),
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
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            _TaskPalette.cardTop.withOpacity(0.97),
            _TaskPalette.cardBottom.withOpacity(0.96),
            const Color(0xFF171A22).withOpacity(0.97),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.07),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.34),
            blurRadius: 24,
            offset: const Offset(0, 14),
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
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
            ...children,
          ],
        ),
      ),
    );
  }
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

  List<Color> _gradientForTitle(String v) {
    final s = v.toLowerCase();
    if (s.contains('today')) {
      return const [Color(0xFF19342D), Color(0xFF121D1D), Color(0xFF10141A)];
    }
    if (s.contains('tomorrow')) {
      return const [Color(0xFF232C45), Color(0xFF181E2E), Color(0xFF10141A)];
    }
    if (s.contains('recent')) {
      return const [Color(0xFF2F2A19), Color(0xFF1F1C14), Color(0xFF10141A)];
    }
    return const [Color(0xFF262A35), Color(0xFF1A1E28), Color(0xFF10141A)];
  }

  Color _accentForTitle(String v) {
    final s = v.toLowerCase();
    if (s.contains('today')) return const Color(0xFF34D399);
    if (s.contains('tomorrow')) return const Color(0xFF7C9BFF);
    if (s.contains('recent')) return const Color(0xFFF59E0B);
    return _TaskPalette.green;
  }

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 task' : '$count tasks';
    final accent = _accentForTitle(title);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: _gradientForTitle(title),
        ),
        border: Border.all(color: Colors.white.withOpacity(0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.24),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            _iconForTitle(title),
            color: accent,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: _TaskPalette.textMain,
                fontWeight: FontWeight.w900,
                fontSize: 15.2,
              ),
            ),
          ),
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withOpacity(0.78),
              fontWeight: FontWeight.w800,
              fontSize: 11.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskImageCarousel extends StatefulWidget {
  final List<Map<String, dynamic>> images;
  final void Function(String url)? onOpen;
  final void Function(Map<String, dynamic> attachment)? onDelete;
  final bool Function(Map<String, dynamic> attachment)? canDelete;

  const _TaskImageCarousel({
    required this.images,
    this.onOpen,
    this.onDelete,
    this.canDelete,
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

  String _proofChecklistLabel(String fileName) {
    if (!fileName.startsWith('proof__')) return '';

    final raw = fileName.split('__');
    if (raw.length < 2) return '';

    return raw[1]
        .replaceAll('_', ' ')
        .trim();
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
          final proofLabel = _proofChecklistLabel(fileName);

          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                color: Colors.white.withOpacity(0.04),
                border: Border.all(
                  color: roleLabel.isEmpty
                      ? Colors.white.withOpacity(0.08)
                      : roleColor.withOpacity(0.35),
                ),
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

                  if (proofLabel.isNotEmpty)
                    Positioned(
                      top: 12,
                      left: 12,
                      right: 84,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: _TaskPalette.green.withOpacity(0.18),
                          borderRadius: BorderRadius.circular(999),
                          border: Border.all(
                            color: _TaskPalette.green.withOpacity(0.34),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.task_alt_rounded,
                              color: _TaskPalette.green,
                              size: 14,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                proofLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 11.6,
                                ),
                              ),
                            ),
                          ],
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
                              color: Colors.black.withOpacity(0.45),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Colors.white.withOpacity(0.10),
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (roleLabel.isNotEmpty) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: roleColor.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(999),
                                      border: Border.all(
                                        color: roleColor.withOpacity(0.28),
                                      ),
                                    ),
                                    child: Text(
                                      roleLabel,
                                      style: TextStyle(
                                        color: roleColor,
                                        fontWeight: FontWeight.w800,
                                        fontSize: 10.8,
                                        height: 1,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                ],
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
            Colors.white.withOpacity(0.02),
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.10),
            Colors.white.withOpacity(0.02),
          ],
        ),
      ),
    );
  }
}
