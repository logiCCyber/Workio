import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/message_service.dart';
import 'admin_chat_screen.dart';
import 'package:file_picker/file_picker.dart';
import 'package:cross_file/cross_file.dart';

class AdminInboxScreen extends StatefulWidget {
  const AdminInboxScreen({super.key});

  @override
  State<AdminInboxScreen> createState() => _AdminInboxScreenState();
}

class _AdminInboxScreenState extends State<AdminInboxScreen> {
  final TextEditingController _searchCtrl = TextEditingController();

  String _q = '';

  RealtimeChannel? _appPresenceChannel;
  final Set<String> _appOnlineIds = {};

  @override
  void dispose() {
    _searchCtrl.dispose();

    final ch = _appPresenceChannel;
    _appPresenceChannel = null;

    if (ch != null) {
      ch.untrack();
      Supabase.instance.client.removeChannel(ch);
    }

    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initAppPresenceWatcher();
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

  Future<void> _openThreadChat({
    required String threadId,
    required String workerName,
    required String workerEmail,
    required String avatarUrl,
    required String workerAuthId,
  }) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminChatScreen(
          threadId: threadId,
          workerName: workerName,
          workerEmail: workerEmail,
          avatarUrl: avatarUrl,
          workerAuthId: workerAuthId,
        ),
      ),
    );

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openNewChatPicker() async {
    try {
      final workers = await MessageService.fetchAdminWorkers();

      if (!mounted) return;

      if (workers.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No workers available')),
        );
        return;
      }

      final result = await showModalBottomSheet<_WorkerPickerResult>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (_) => _WorkerPickerSheet(workers: workers),
      );

      if (result == null || !mounted) return;

      if (result.mode == _WorkerPickerMode.personal) {
        final selected = result.worker;
        if (selected == null) return;

        final workerId = _s(selected['id']);
        final workerAuthId = _s(selected['auth_user_id']);
        final workerName =
        _s(selected['name']).isEmpty ? 'Worker' : _s(selected['name']);
        final workerEmail = _s(selected['email']);
        final avatarUrl = _s(selected['avatar_url']);

        final thread = await MessageService.getOrCreateAdminThread(
          workerId: workerId,
          workerAuthId: workerAuthId,
        );

        if (!mounted) return;

        await _openThreadChat(
          threadId: _s(thread['id']),
          workerName: workerName,
          workerEmail: workerEmail,
          avatarUrl: avatarUrl,
          workerAuthId: workerAuthId,
        );

        return;
      }

      final pickedWorkers = result.workers;
      if (pickedWorkers.isEmpty) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Broadcast selected: ${pickedWorkers.length} workers'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('New chat error: $e')),
      );
    }
  }

  String _s(Object? v) => (v ?? '').toString().trim();

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    return Scaffold(
      backgroundColor: _InboxPalette.bg,
      body: Stack(
        children: [
          const _InboxBackground(),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                  child: _GlassHeader(
                    title: 'Messages',
                    subtitle: 'Internal inbox',
                    onBack: () => Navigator.pop(context),
                  ),
                ),

                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: _SearchBar(
                          controller: _searchCtrl,
                          onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _NewChatButton(
                        onTap: _openNewChatPicker,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                Expanded(
                  child: StreamBuilder<List<Map<String, dynamic>>>(
                    stream: MessageService.watchAdminThreads(),
                    builder: (context, snapshot) {
                      if (snapshot.connectionState == ConnectionState.waiting &&
                          !(snapshot.hasData)) {
                        return const _LoadingState();
                      }

                      final all = snapshot.data ?? <Map<String, dynamic>>[];

                      final filtered = all.where((t) {
                        final worker =
                        Map<String, dynamic>.from((t['workers'] ?? {}) as Map);
                        final name = _s(worker['name']).toLowerCase();
                        final email = _s(worker['email']).toLowerCase();
                        final q = _q;
                        if (q.isEmpty) return true;
                        return name.contains(q) || email.contains(q);
                      }).toList();

                      if (filtered.isEmpty) {
                        return _EmptyState(
                          hasSearch: _q.isNotEmpty,
                          bottomPadding: mq.padding.bottom,
                        );
                      }

                      return ListView.separated(
                        padding: EdgeInsets.fromLTRB(
                          12,
                          0,
                          12,
                          18 + mq.padding.bottom,
                        ),
                        itemCount: filtered.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 10),
                        itemBuilder: (context, index) {
                          final thread = filtered[index];
                          final worker =
                          Map<String, dynamic>.from((thread['workers'] ?? {}) as Map);

                          final threadId = _s(thread['id']);
                          final workerName = _s(worker['name']).isEmpty
                              ? 'Worker'
                              : _s(worker['name']);
                          final workerEmail = _s(worker['email']);
                          final avatarUrl = _s(worker['avatar_url']);
                          final lastMessageAt = _parseDate(thread['last_message_at']);
                          final workerAuthId = _s(worker['auth_user_id']);

                          return _ThreadTile(
                            workerName: workerName,
                            workerEmail: workerEmail,
                            avatarUrl: avatarUrl,
                            lastMessageAt: lastMessageAt,
                            threadId: threadId,
                            isOnline: _appOnlineIds.contains(workerAuthId),
                            onTap: () async {
                              await _openThreadChat(
                                threadId: threadId,
                                workerName: workerName,
                                workerEmail: workerEmail,
                                avatarUrl: avatarUrl,
                                workerAuthId: workerAuthId,
                              );
                            },
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

  DateTime? _parseDate(Object? v) {
    final s = _s(v);
    if (s.isEmpty) return null;
    return DateTime.tryParse(s)?.toLocal();
  }
}

class _InboxPalette {
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
  static const orange = Color(0xFFF59E0B);
  static const blue = Color(0xFF38BDF8);
  static const red = Color(0xFFFB7185);
}

class _InboxBackground extends StatelessWidget {
  const _InboxBackground();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: _InboxPalette.bg,
    );
  }
}

class _GlassHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onBack;

  const _GlassHeader({
    required this.title,
    required this.subtitle,
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
          child: Stack(
            children: [
              Row(
                children: [
                  _IconBtn(
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
                            color: _InboxPalette.textMain,
                            fontWeight: FontWeight.w900,
                            fontSize: 20,
                            letterSpacing: 0.2,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(
                            color: Colors.white.withOpacity(0.55),
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.forum_rounded,
                    size: 28,
                    color: const Color(0xFF55A7FF),
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

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _IconBtn({
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
            border: Border.all(
              color: Colors.white.withOpacity(0.06),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.24),
                blurRadius: 12,
                offset: const Offset(0, 6),
              ),
            ],
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

class _MetaLine extends StatelessWidget {
  final IconData icon;
  final Widget child;
  final Color? iconColor;

  const _MetaLine({
    required this.icon,
    required this.child,
    this.iconColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Icon(
          icon,
          size: 13,
          color: iconColor ?? Colors.white.withOpacity(0.40),
        ),
        const SizedBox(width: 6),
        Expanded(child: child),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchBar({
    required this.controller,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0xFF363C47),
            Color(0xFF2C323D),
            Color(0xFF232933),
          ],
        ),
        border: Border.all(
          color: Colors.white.withOpacity(0.075),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.26),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFF5EA8FF).withOpacity(0.05),
            blurRadius: 10,
            spreadRadius: 0.5,
          ),
          BoxShadow(
            color: Colors.white.withOpacity(0.04),
            blurRadius: 8,
            spreadRadius: -4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              color: Colors.white.withOpacity(0.80),
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Center(
                child: TextField(
                  controller: controller,
                  onChanged: onChanged,
                  maxLines: 1,
                  textAlignVertical: TextAlignVertical.center,
                  style: const TextStyle(
                    color: _InboxPalette.textMain,
                    fontWeight: FontWeight.w800,
                    fontSize: 15,
                    height: 1.0,
                  ),
                  decoration: InputDecoration(
                    isCollapsed: true,
                    border: InputBorder.none,
                    hintText: 'Search worker',
                    hintStyle: TextStyle(
                      color: Colors.white.withOpacity(0.38),
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      height: 1.0,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThreadTile extends StatelessWidget {
  final String workerName;
  final String workerEmail;
  final String avatarUrl;
  final DateTime? lastMessageAt;
  final String threadId;
  final VoidCallback onTap;
  final bool isOnline;

  const _ThreadTile({
    required this.workerName,
    required this.workerEmail,
    required this.avatarUrl,
    required this.lastMessageAt,
    required this.threadId,
    required this.onTap,
    required this.isOnline,
  });

  String _fmtTime(DateTime? dt) {
    if (dt == null) return '—';
    final now = DateTime.now();
    final sameDay =
        dt.year == now.year && dt.month == now.month && dt.day == now.day;
    if (sameDay) {
      final hh = dt.hour.toString().padLeft(2, '0');
      final mm = dt.minute.toString().padLeft(2, '0');
      return '$hh:$mm';
    }
    return '${dt.month}/${dt.day}';
  }

  Widget _buildLastMessagePreview() {
    return StreamBuilder<List<Map<String, dynamic>>>(
      stream: MessageService.watchMessages(threadId),
      builder: (context, snapshot) {
        final messages = snapshot.data ?? const <Map<String, dynamic>>[];

        if (messages.isEmpty) {
          return Text(
            'No messages yet',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white.withOpacity(0.42),
              fontWeight: FontWeight.w700,
              fontSize: 12.1,
            ),
          );
        }

        final last = messages.last;
        final senderRole =
        (last['sender_role'] ?? '').toString().trim().toLowerCase();
        final messageType =
        (last['message_type'] ?? '').toString().trim().toLowerCase();
        final fileName = (last['file_name'] ?? '').toString().trim();
        final isDeleted =
            (last['deleted_at'] ?? '').toString().trim().isNotEmpty;
        final body = (last['body'] ?? '')
            .toString()
            .trim()
            .replaceAll('\n', ' ')
            .replaceAll(RegExp(r'\s+'), ' ');

        final prefix = senderRole == 'admin' ? 'You' : workerName;

        final previewText = isDeleted
            ? 'Message deleted'
            : messageType == 'image'
            ? 'Photo'
            : messageType == 'file'
            ? (fileName.isEmpty ? 'File' : 'File: $fileName')
            : (body.isEmpty ? 'Empty message' : body);

        return Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: '$prefix: ',
                style: TextStyle(
                  color: senderRole == 'admin'
                      ? const Color(0xFF59D7B7)
                      : const Color(0xFF7AB8FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 12.4,
                ),
              ),
              TextSpan(
                text: previewText,
                style: TextStyle(
                  color: Colors.white.withOpacity(0.60),
                  fontWeight: FontWeight.w700,
                  fontSize: 12.35,
                ),
              ),
            ],
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(26),
        onTap: onTap,
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(26),
            color: const Color(0xFF1C2129),
            border: Border.all(
              color: Colors.white.withOpacity(0.065),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.30),
                blurRadius: 18,
                offset: const Offset(0, 10),
              ),
              BoxShadow(
                color: const Color(0xFF5EA8FF).withOpacity(0.05),
                blurRadius: 12,
                spreadRadius: 0.5,
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.035),
                blurRadius: 8,
                spreadRadius: -4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _AvatarBox(
                        avatarUrl: avatarUrl,
                        isOnline: isOnline,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _fmtTime(lastMessageAt),
                        style: TextStyle(
                          color: Colors.white.withOpacity(0.48),
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          height: 1.0,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  const _ThreadSoftDivider(),

                  const SizedBox(width: 12),

                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        color: const Color(0xFF222833),
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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_rounded,
                                size: 14,
                                color: Colors.white.withOpacity(0.48),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  workerName,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: _InboxPalette.textMain,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 15.8,
                                    letterSpacing: 0.15,
                                    height: 1.0,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                            ],
                          ),
                          const SizedBox(height: 7),
                          _MetaLine(
                            icon: Icons.alternate_email_rounded,
                            child: Text(
                              workerEmail.isEmpty ? 'No email' : workerEmail,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: Colors.white.withOpacity(0.52),
                                fontWeight: FontWeight.w700,
                                fontSize: 11.8,
                                height: 1.0,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          _MetaLine(
                            icon: Icons.chat_bubble_outline_rounded,
                            child: _buildLastMessagePreview(),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 10),

                  FutureBuilder<int>(
                    future: MessageService.countUnreadForAdminThread(threadId),
                    builder: (context, snap) {
                      final unread = snap.data ?? 0;
                      final unreadLabel = unread > 99 ? '99+' : '$unread';
                      final badgeWidth = unreadLabel.length == 1
                          ? 28.0
                          : unreadLabel.length == 2
                          ? 34.0
                          : 40.0;

                      return Align(
                        alignment: Alignment.center,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (unread > 0) ...[
                              Container(
                                width: badgeWidth,
                                height: 28,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(999),
                                  gradient: const LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Color(0xFF69B7FF),
                                      Color(0xFF2D6BFF),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: const Color(0xFF2D6BFF).withOpacity(0.28),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                                ),
                                child: Center(
                                  child: Text(
                                    unreadLabel,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w900,
                                      fontSize: 10.2,
                                      height: 1.0,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                            ],
                            Icon(
                              Icons.chevron_right_rounded,
                              size: 22,
                              color: Colors.white.withOpacity(0.22),
                            ),
                          ],
                        ),
                      );
                    },
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

class _AvatarBox extends StatelessWidget {
  final String avatarUrl;
  final bool isOnline;

  const _AvatarBox({
    required this.avatarUrl,
    required this.isOnline,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Colors.white.withOpacity(0.06),
                border: Border.all(color: Colors.white.withOpacity(0.12)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.34),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: avatarUrl.isEmpty
                    ? Icon(
                  Icons.person_rounded,
                  color: Colors.white.withOpacity(0.52),
                  size: 21,
                )
                    : Image.network(
                  avatarUrl,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Icon(
                    Icons.person_rounded,
                    color: Colors.white.withOpacity(0.52),
                    size: 21,
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
                color: isOnline ? _InboxPalette.green : Colors.grey,
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

class _ThreadSoftDivider extends StatelessWidget {
  const _ThreadSoftDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1.2,
      margin: const EdgeInsets.symmetric(vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withOpacity(0.03),
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.14),
            Colors.white.withOpacity(0.08),
            Colors.white.withOpacity(0.03),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.22),
            blurRadius: 6,
          ),
        ],
      ),
    );
  }
}

class _LoadingState extends StatelessWidget {
  const _LoadingState();

  @override
  @override
  Widget build(BuildContext context) {
    return const Center(
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          strokeWidth: 2.4,
          color: _InboxPalette.green,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final bool hasSearch;
  final double bottomPadding;

  const _EmptyState({
    required this.hasSearch,
    required this.bottomPadding,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsets.fromLTRB(12, 0, 12, 20 + bottomPadding),
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                _InboxPalette.cardTop.withOpacity(0.97),
                _InboxPalette.cardBottom.withOpacity(0.96),
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.08)),
          ),
          child: Column(
            children: [
              Icon(
                hasSearch
                    ? Icons.search_off_rounded
                    : Icons.mark_email_unread_outlined,
                size: 28,
                color: Colors.white.withOpacity(0.58),
              ),
              const SizedBox(height: 10),
              Text(
                hasSearch ? 'Nothing found' : 'No messages yet',
                style: const TextStyle(
                  color: _InboxPalette.textMain,
                  fontWeight: FontWeight.w900,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                hasSearch
                    ? 'Try another name or email.'
                    : 'When you start a chat with a worker, it will appear here.',
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
class _NewChatButton extends StatelessWidget {
  final VoidCallback onTap;

  const _NewChatButton({
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: Container(
          width: 60,
          height: 60,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color(0xFF3A3D46),
                Color(0xFF2C2F37),
                Color(0xFF1F222A),
              ],
            ),
            border: Border.all(
              color: Colors.white.withOpacity(0.10),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.22),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
              BoxShadow(
                color: Colors.white.withOpacity(0.04),
                blurRadius: 8,
                spreadRadius: -4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Stack(
            children: [
              Positioned(
                left: 10,
                right: 10,
                top: 8,
                child: Container(
                  height: 1,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.white.withOpacity(0.18),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),
              Center(
                child: Icon(
                  Icons.edit_square,
                  color: Colors.white.withOpacity(0.88),
                  size: 24,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _WorkerPickerMode {
  personal,
  broadcast,
}

class _WorkerPickerResult {
  final _WorkerPickerMode mode;
  final Map<String, dynamic>? worker;
  final List<Map<String, dynamic>> workers;

  const _WorkerPickerResult.personal(this.worker)
      : mode = _WorkerPickerMode.personal,
        workers = const [];

  const _WorkerPickerResult.broadcast(this.workers)
      : mode = _WorkerPickerMode.broadcast,
        worker = null;
}

class _BroadcastAttachButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _BroadcastAttachButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Container(
          height: 48,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
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
                size: 18,
                color: Colors.white.withOpacity(0.82),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BroadcastPickedFileRow extends StatelessWidget {
  final IconData icon;
  final String name;
  final VoidCallback onRemove;

  const _BroadcastPickedFileRow({
    required this.icon,
    required this.name,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white.withOpacity(0.04),
        border: Border.all(
          color: Colors.white.withOpacity(0.06),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: const Color(0xFF7AB8FF),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: onRemove,
            child: Container(
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: Colors.white.withOpacity(0.05),
              ),
              child: const Icon(
                Icons.close_rounded,
                size: 16,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkerPickerSheet extends StatefulWidget {
  final List<Map<String, dynamic>> workers;

  const _WorkerPickerSheet({
    required this.workers,
  });

  @override
  State<_WorkerPickerSheet> createState() => _WorkerPickerSheetState();
}

class _WorkerPickerSheetState extends State<_WorkerPickerSheet> {
  final TextEditingController _searchCtrl = TextEditingController();

  final TextEditingController _broadcastCtrl = TextEditingController();

  bool _broadcastSending = false;
  XFile? _broadcastImage;
  PlatformFile? _broadcastFile;
  PlatformFile? _broadcastVideo;

  String _q = '';
  _WorkerPickerMode _mode = _WorkerPickerMode.personal;
  final Set<String> _selectedIds = {};

  String _s(Object? v) => (v ?? '').toString().trim();

  String _workerKey(Map<String, dynamic> w) {
    final id = _s(w['id']);
    if (id.isNotEmpty) return id;
    return _s(w['auth_user_id']);
  }

  bool _isSelected(Map<String, dynamic> w) {
    return _selectedIds.contains(_workerKey(w));
  }

  List<Map<String, dynamic>> _selectedWorkers() {
    return widget.workers.where((w) => _isSelected(w)).toList();
  }

  @override
  void initState() {
    super.initState();

    for (final w in widget.workers) {
      final key = _workerKey(w);
      if (key.isNotEmpty) {
        _selectedIds.add(key);
      }
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _broadcastCtrl.dispose();
    super.dispose();
  }

  void _toggleWorker(Map<String, dynamic> worker) {
    final key = _workerKey(worker);
    if (key.isEmpty) return;

    setState(() {
      if (_selectedIds.contains(key)) {
        _selectedIds.remove(key);
      } else {
        _selectedIds.add(key);
      }
    });
  }

  void _selectAll(List<Map<String, dynamic>> workers) {
    setState(() {
      for (final w in workers) {
        final key = _workerKey(w);
        if (key.isNotEmpty) {
          _selectedIds.add(key);
        }
      }
    });
  }

  void _clearAll(List<Map<String, dynamic>> workers) {
    setState(() {
      for (final w in workers) {
        final key = _workerKey(w);
        if (key.isNotEmpty) {
          _selectedIds.remove(key);
        }
      }
    });
  }

  Future<void> _pickBroadcastImage() async {
    final file = await MessageService.pickImageFromGallery();
    if (file == null || !mounted) return;

    setState(() {
      _broadcastImage = file;
    });
  }

  Future<void> _pickBroadcastFile() async {
    final file = await MessageService.pickAnyFile();
    if (file == null || !mounted) return;

    setState(() {
      _broadcastFile = file;
    });
  }

  Future<void> _pickBroadcastVideo() async {
    final file = await MessageService.pickAnyFile();
    if (file == null || !mounted) return;

    setState(() {
      _broadcastVideo = file;
    });
  }

  void _removeBroadcastImage() {
    setState(() {
      _broadcastImage = null;
    });
  }

  void _removeBroadcastFile() {
    setState(() {
      _broadcastFile = null;
    });
  }

  void _removeBroadcastVideo() {
    setState(() {
      _broadcastVideo = null;
    });
  }

  Future<void> _sendBroadcast() async {
    if (_broadcastSending) return;

    final selectedWorkers = _selectedWorkers();
    final text = _broadcastCtrl.text.trim();

    if (selectedWorkers.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No workers selected')),
      );
      return;
    }

    if (text.isEmpty &&
        _broadcastImage == null &&
        _broadcastFile == null &&
        _broadcastVideo == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write a message or attach a file')),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    setState(() {
      _broadcastSending = true;
    });

    try {
      for (final worker in selectedWorkers) {
        final workerId = _s(worker['id']);
        final workerAuthId = _s(worker['auth_user_id']);

        final thread = await MessageService.getOrCreateAdminThread(
          workerId: workerId,
          workerAuthId: workerAuthId,
        );

        final threadId = _s(thread['id']);

        if (text.isNotEmpty) {
          await MessageService.sendAdminMessage(
            threadId: threadId,
            text: text,
          );
        }

        if (_broadcastImage != null) {
          await MessageService.sendAdminImageMessage(
            threadId: threadId,
            file: _broadcastImage!,
          );
        }

        if (_broadcastFile != null) {
          await MessageService.sendAdminFileMessage(
            threadId: threadId,
            file: _broadcastFile!,
          );
        }

        if (_broadcastVideo != null) {
          await MessageService.sendAdminFileMessage(
            threadId: threadId,
            file: _broadcastVideo!,
          );
        }
      }

      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('Sent to ${selectedWorkers.length} workers'),
        ),
      );

      Navigator.pop(context);
    } catch (e) {
      if (!mounted) return;

      messenger.showSnackBar(
        SnackBar(
          content: Text('Broadcast send error: $e'),
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _broadcastSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    final filtered = widget.workers.where((w) {
      final name = _s(w['name']).toLowerCase();
      final email = _s(w['email']).toLowerCase();
      final q = _q.trim().toLowerCase();
      if (q.isEmpty) return true;
      return name.contains(q) || email.contains(q);
    }).toList();

    final selectedCount = _selectedWorkers().length;
    final allFilteredSelected = filtered.isNotEmpty &&
        filtered.every((w) => _isSelected(w));

    return Padding(
      padding: EdgeInsets.fromLTRB(10, 40, 10, 10 + mq.viewInsets.bottom),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 26, sigmaY: 26),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(28),
              gradient: const LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Color(0xFF262B36),
                  Color(0xFF1A1F2A),
                  Color(0xFF111621),
                ],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.09)),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.34),
                  blurRadius: 24,
                  offset: const Offset(0, 14),
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
                        Expanded(
                          child: Row(
                            children: [
                              Icon(
                                _mode == _WorkerPickerMode.broadcast
                                    ? Icons.groups_rounded
                                    : Icons.person_search_rounded,
                                size: 20,
                                color: _mode == _WorkerPickerMode.broadcast
                                    ? const Color(0xFFFFC14D)
                                    : Colors.white.withOpacity(0.82),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                _mode == _WorkerPickerMode.personal
                                    ? 'Select worker'
                                    : 'Select workers',
                                style: const TextStyle(
                                  color: _InboxPalette.textMain,
                                  fontWeight: FontWeight.w900,
                                  fontSize: 18,
                                ),
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: Icon(
                            Icons.close_rounded,
                            color: Colors.white.withOpacity(0.72),
                          ),
                        ),
                      ],
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 2, 16, 8),
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            const Color(0xFF5EA8FF).withOpacity(0.16),
                            Colors.white.withOpacity(0.10),
                            const Color(0xFF5EA8FF).withOpacity(0.16),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                    child: Container(
                      height: 48,
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        gradient: const LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Color(0xFF323844),
                            Color(0xFF2A303A),
                            Color(0xFF222832),
                          ],
                        ),
                        border: Border.all(
                          color: Colors.white.withOpacity(0.075),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.22),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                          BoxShadow(
                            color: const Color(0xFF5EA8FF).withOpacity(0.04),
                            blurRadius: 10,
                            spreadRadius: 0.5,
                          ),
                          BoxShadow(
                            color: Colors.white.withOpacity(0.035),
                            blurRadius: 8,
                            spreadRadius: -4,
                            offset: const Offset(0, -2),
                          ),
                        ],
                      ),
                      child: Stack(
                        children: [
                          AnimatedAlign(
                            duration: const Duration(milliseconds: 240),
                            curve: Curves.easeOutCubic,
                            alignment: _mode == _WorkerPickerMode.personal
                                ? Alignment.centerLeft
                                : Alignment.centerRight,
                            child: FractionallySizedBox(
                              widthFactor: 0.5,
                              child: Container(
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(14),
                                  gradient: _mode == _WorkerPickerMode.personal
                                      ? const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFF4EA1FF),
                                      Color(0xFF2D6BFF),
                                      Color(0xFF1F56D8),
                                    ],
                                  )
                                      : const LinearGradient(
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                    colors: [
                                      Color(0xFFFFC14D),
                                      Color(0xFFF59E0B),
                                      Color(0xFFD97706),
                                    ],
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: (_mode == _WorkerPickerMode.personal
                                          ? const Color(0xFF2D6BFF)
                                          : const Color(0xFFF59E0B))
                                          .withOpacity(0.22),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                    BoxShadow(
                                      color: Colors.white.withOpacity(0.04),
                                      blurRadius: 8,
                                      spreadRadius: -4,
                                      offset: const Offset(0, -2),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Row(
                            children: [
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      if (_mode == _WorkerPickerMode.personal) return;
                                      setState(() {
                                        _mode = _WorkerPickerMode.personal;
                                      });
                                    },
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.person_rounded,
                                            size: 14,
                                            color: Colors.white.withOpacity(
                                              _mode == _WorkerPickerMode.personal ? 0.96 : 0.64,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          AnimatedDefaultTextStyle(
                                            duration: const Duration(milliseconds: 180),
                                            curve: Curves.easeOut,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                _mode == _WorkerPickerMode.personal ? 0.96 : 0.64,
                                              ),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                            child: const Text('Personal'),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    borderRadius: BorderRadius.circular(14),
                                    onTap: () {
                                      if (_mode == _WorkerPickerMode.broadcast) return;
                                      setState(() {
                                        _mode = _WorkerPickerMode.broadcast;
                                      });
                                    },
                                    child: Center(
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.groups_rounded,
                                            size: 15,
                                            color: Colors.white.withOpacity(
                                              _mode == _WorkerPickerMode.broadcast ? 0.96 : 0.64,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          AnimatedDefaultTextStyle(
                                            duration: const Duration(milliseconds: 180),
                                            curve: Curves.easeOut,
                                            style: TextStyle(
                                              color: Colors.white.withOpacity(
                                                _mode == _WorkerPickerMode.broadcast ? 0.96 : 0.64,
                                              ),
                                              fontWeight: FontWeight.w800,
                                              fontSize: 13,
                                            ),
                                            child: const Text('Broadcast'),
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

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _SearchBar(
                      controller: _searchCtrl,
                      onChanged: (v) => setState(() => _q = v),
                    ),
                  ),

                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                    child: Container(
                      height: 1,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            const Color(0xFFFFC14D).withOpacity(0.10),
                            Colors.white.withOpacity(0.08),
                            const Color(0xFFFFC14D).withOpacity(0.10),
                            Colors.transparent,
                          ],
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  Flexible(
                    child: filtered.isEmpty
                        ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(18, 20, 18, 20),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          color: Colors.white.withOpacity(0.03),
                          border: Border.all(
                            color: Colors.white.withOpacity(0.07),
                          ),
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 28,
                              color: Colors.white.withOpacity(0.55),
                            ),
                            const SizedBox(height: 10),
                            const Text(
                              'Nothing found',
                              style: TextStyle(
                                color: _InboxPalette.textMain,
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        : ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
                      itemCount: filtered.length,
                      separatorBuilder: (_, __) =>
                      const SizedBox(height: 10),
                      itemBuilder: (context, index) {
                        final worker = filtered[index];
                        final name = _s(worker['name']).isEmpty
                            ? 'Worker'
                            : _s(worker['name']);
                        final email = _s(worker['email']);
                        final avatarUrl = _s(worker['avatar_url']);
                        final isOnline = worker['on_shift'] == true;
                        final isSelected = _isSelected(worker);

                        return Material(
                          color: Colors.transparent,
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () {
                              if (_mode == _WorkerPickerMode.personal) {
                                Navigator.pop(
                                  context,
                                  _WorkerPickerResult.personal(worker),
                                );
                                return;
                              }

                              _toggleWorker(worker);
                            },
                            child: Container(
                              clipBehavior: Clip.antiAlias,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                gradient: const LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [
                                    Color(0xFF21344F),
                                    Color(0xFF16253C),
                                    Color(0xFF101A2C),
                                  ],
                                ),
                                border: Border.all(
                                  color: _mode == _WorkerPickerMode.broadcast && isSelected
                                      ? const Color(0xFF4EA1FF)
                                      : Colors.white.withOpacity(0.08),
                                  width: _mode == _WorkerPickerMode.broadcast && isSelected ? 1.25 : 1,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.28),
                                    blurRadius: 18,
                                    offset: const Offset(0, 10),
                                  ),
                                  BoxShadow(
                                    color: Colors.white.withOpacity(0.04),
                                    blurRadius: 8,
                                    spreadRadius: -4,
                                    offset: const Offset(0, -2),
                                  ),
                                  if (_mode == _WorkerPickerMode.broadcast && isSelected)
                                    BoxShadow(
                                      color: const Color(0xFF4EA1FF).withOpacity(0.24),
                                      blurRadius: 12,
                                      spreadRadius: 0.5,
                                    ),
                                ],
                              ),
                              child: Stack(
                                children: [
                                  Positioned(
                                    left: 14,
                                    right: 14,
                                    top: 10,
                                    child: Container(
                                      height: 1,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          colors: [
                                            Colors.transparent,
                                            Colors.white.withOpacity(0.10),
                                            Colors.transparent,
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                  Padding(
                                    padding: const EdgeInsets.fromLTRB(14, 13, 14, 13),
                                    child: Row(
                                      children: [
                                        _AvatarBox(
                                          avatarUrl: avatarUrl,
                                          isOnline: isOnline,
                                        ),
                                        const SizedBox(width: 12),
                                        const _ThreadSoftDivider(),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.person_rounded,
                                                    size: 14,
                                                    color: Colors.white.withOpacity(0.46),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(
                                                        color: _InboxPalette.textMain,
                                                        fontWeight: FontWeight.w900,
                                                        fontSize: 15.5,
                                                        height: 1.0,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                              const SizedBox(height: 8),
                                              Row(
                                                children: [
                                                  Icon(
                                                    Icons.alternate_email_rounded,
                                                    size: 13,
                                                    color: Colors.white.withOpacity(0.38),
                                                  ),
                                                  const SizedBox(width: 6),
                                                  Expanded(
                                                    child: Text(
                                                      email.isEmpty ? 'No email' : email,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        color: Colors.white.withOpacity(0.58),
                                                        fontWeight: FontWeight.w700,
                                                        fontSize: 12.3,
                                                        height: 1.0,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 10),
                                        if (_mode ==
                                            _WorkerPickerMode.personal)
                                          Icon(
                                            Icons.chevron_right_rounded,
                                            color: Colors.white
                                                .withOpacity(0.28),
                                          )
                                        else
                                          AnimatedContainer(
                                            duration: const Duration(
                                                milliseconds: 140),
                                            width: 24,
                                            height: 24,
                                            decoration: BoxDecoration(
                                              shape: BoxShape.circle,
                                              gradient: isSelected
                                                  ? const LinearGradient(
                                                begin: Alignment.topCenter,
                                                end: Alignment.bottomCenter,
                                                colors: [
                                                  Color(0xFF61B0FF),
                                                  Color(0xFF2D6BFF),
                                                ],
                                              )
                                                  : null,
                                              color: isSelected ? null : Colors.white.withOpacity(0.05),
                                              border: Border.all(
                                                color: isSelected
                                                    ? const Color(0xFF7BC0FF).withOpacity(0.55)
                                                    : Colors.white.withOpacity(0.18),
                                              ),
                                              boxShadow: isSelected
                                                  ? [
                                                BoxShadow(
                                                  color: const Color(0xFF2D6BFF).withOpacity(0.34),
                                                  blurRadius: 10,
                                                ),
                                              ]
                                                  : null,
                                            ),
                                            child: isSelected
                                                ? const Center(
                                              child: Icon(
                                                Icons.check_rounded,
                                                size: 15,
                                                color: Colors.white,
                                              ),
                                            )
                                                : null,
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _mode == _WorkerPickerMode.broadcast
                        ? Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
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
                            color: Colors.white.withOpacity(0.07),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.24),
                              blurRadius: 16,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.campaign_rounded,
                                  size: 18,
                                  color: const Color(0xFFFFC14D),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  '$selectedCount selected',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w900,
                                    fontSize: 13.2,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
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
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.18),
                                    blurRadius: 10,
                                    offset: const Offset(0, 5),
                                  ),
                                ],
                              ),
                              child: TextField(
                                controller: _broadcastCtrl,
                                minLines: 1,
                                maxLines: 4,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 14,
                                ),
                                decoration: InputDecoration(
                                  contentPadding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                                  border: InputBorder.none,
                                  hintText: 'Write message to selected workers',
                                  hintStyle: TextStyle(
                                    color: Colors.white.withOpacity(0.32),
                                    fontWeight: FontWeight.w700,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Row(
                              children: [
                                Expanded(
                                  child: _BroadcastAttachButton(
                                    icon: Icons.image_rounded,
                                    label: 'Image',
                                    onTap: _pickBroadcastImage,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _BroadcastAttachButton(
                                    icon: Icons.attach_file_rounded,
                                    label: 'File',
                                    onTap: _pickBroadcastFile,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: _BroadcastAttachButton(
                                    icon: Icons.videocam_rounded,
                                    label: 'Video',
                                    onTap: _pickBroadcastVideo,
                                  ),
                                ),
                              ],
                            ),
                            if (_broadcastImage != null ||
                                _broadcastFile != null ||
                                _broadcastVideo != null) ...[
                              const SizedBox(height: 12),
                              if (_broadcastImage != null)
                                _BroadcastPickedFileRow(
                                  icon: Icons.image_rounded,
                                  name: _broadcastImage!.name,
                                  onRemove: _removeBroadcastImage,
                                ),
                              if (_broadcastFile != null) ...[
                                if (_broadcastImage != null) const SizedBox(height: 8),
                                _BroadcastPickedFileRow(
                                  icon: Icons.attach_file_rounded,
                                  name: _broadcastFile!.name,
                                  onRemove: _removeBroadcastFile,
                                ),
                              ],
                              if (_broadcastVideo != null) ...[
                                if (_broadcastImage != null || _broadcastFile != null)
                                  const SizedBox(height: 8),
                                _BroadcastPickedFileRow(
                                  icon: Icons.videocam_rounded,
                                  name: _broadcastVideo!.name,
                                  onRemove: _removeBroadcastVideo,
                                ),
                              ],
                            ],
                            const SizedBox(height: 14),
                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: ElevatedButton(
                                onPressed: _broadcastSending ? null : _sendBroadcast,
                                style: ElevatedButton.styleFrom(
                                  elevation: 0,
                                  backgroundColor: const Color(0xFF2D6BFF),
                                  disabledBackgroundColor: Colors.white.withOpacity(0.08),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(18),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const Icon(
                                      Icons.send_rounded,
                                      size: 18,
                                      color: Colors.white,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      _broadcastSending ? 'Sending...' : 'Send',
                                      style: const TextStyle(
                                        color: Colors.white,
                                        fontWeight: FontWeight.w900,
                                        fontSize: 14.2,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                        : const SizedBox.shrink(),
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