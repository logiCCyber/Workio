import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'package:table_calendar/table_calendar.dart';

class WorkerDetailsMock extends StatefulWidget {
  final String workerId;

  const WorkerDetailsMock({
    super.key,
    required this.workerId,
  });

  @override
  State<WorkerDetailsMock> createState() => _WorkerDetailsMockState();
}

class _WorkerDetailsMockState extends State<WorkerDetailsMock> {
  Timer? _timer;
  final supabase = Supabase.instance.client;
  Map<String, dynamic>? activeShift;
  bool onShift = false;
  List<Map<String, dynamic>> history = [];
  DateTime? startTime;
  double workedHours = 0;
  double earned = 0;
  int _historyLimit = 10;
  bool _hasMoreHistory = true;
  bool _loadingMore = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  final Map<DateTime, List<Map<String, dynamic>>> _workDays = {};


  Map<String, List<Map<String, dynamic>>> _groupHistoryByDate() {
    final Map<String, List<Map<String, dynamic>>> grouped = {};

    for (final row in history) {
      final start = DateTime.parse(row['start_time']).toLocal();
      final dateKey = DateFormat.yMMMd().format(start); // Dec 21, 2025

      grouped.putIfAbsent(dateKey, () => []);
      grouped[dateKey]!.add(row);
    }

    return grouped;
  }

  double get unpaidTotal {
    double sum = 0;

    for (final row in history) {
      if (row['paid_at'] == null) {
        sum += (row['total_payment'] ?? 0).toDouble();
      }
    }

    return sum;
  }

  int get unpaidCount {
    return history.where((r) => r['paid_at'] == null).length;
  }


  @override
  void initState() {
    super.initState();
    _loadWorker();
  }

  Future<void> _forceEndShift() async {
    if (activeShift == null) return;

    final start = DateTime.parse(activeShift!['start_time']);
    final end = DateTime.now();

    final hours = end.difference(start).inSeconds / 3600;

    final rate =
    (activeShift!['pay_rate'] ?? worker?['hourly_rate'] ?? 0).toDouble();

    final total = hours * rate;

    final res = await supabase
        .from('work_logs')
        .update({
      'end_time': end.toIso8601String(),
      'total_hours': hours,
      'total_payment': total,
    })
        .eq('id', activeShift!['id']);

    debugPrint('UPDATE RESULT = $res');

    _timer?.cancel(); // 🔥 СТОП ТАЙМЕР

    if (!mounted) return;

    setState(() {
      activeShift = null;
      onShift = false;
      startTime = null;
      workedHours = 0;
      earned = 0;
    });

    await _loadWorker(); // 🔁 перечитать состояние
  }

  /// 💰 ОТМЕТИТЬ СМЕНУ КАК ОПЛАЧЕННУЮ
  Future<void> _markAsPaid(String workLogId) async {
    await supabase
        .from('work_logs')
        .update({
      'paid_at': DateTime.now().toUtc().toIso8601String(),
    })
        .eq('id', workLogId);

    await _loadWorker();
  }

  Future<void> _loadWorker() async {
    try {
      debugPrint('LOAD WORKER ID = ${widget.workerId}');

      final workerData = await supabase
          .from('workers')
          .select()
          .eq('id', widget.workerId)
          .maybeSingle();

      final authId = workerData?['auth_user_id'];

      final shiftData = await supabase
          .from('work_logs')
          .select()
          .eq('user_id', authId)
          .filter('end_time', 'is', null)
          .order('start_time', ascending: false)
          .limit(1)
          .maybeSingle();

      final historyData = await supabase
          .from('work_logs')
          .select()
          .eq('user_id', authId)
          .not('end_time', 'is', null)
          .order('start_time', ascending: false)
          .limit(_historyLimit);


      final newHistory = List<Map<String, dynamic>>.from(historyData);

      _workDays.clear();
      for (final row in newHistory) {
        final start = DateTime.parse(row['start_time']).toLocal();
        final day = DateTime(start.year, start.month, start.day);

        _workDays.putIfAbsent(day, () => []);
        _workDays[day]!.add(row);
      }

      if (!mounted) return;

      setState(() {
        worker = workerData;
        activeShift = shiftData;
        onShift = shiftData != null;
        history = newHistory;
        loading = false;
      });



      if (shiftData != null) {
          startTime = DateTime.parse(shiftData['start_time']);
          _timer?.cancel();

          _timer = Timer.periodic(const Duration(seconds: 1), (_) {
            if (!mounted || startTime == null) return;

            final now = DateTime.now();
            final diff = now.difference(startTime!);

            setState(() {
              workedHours = diff.inSeconds / 3600;

              final rate =
              (activeShift?['pay_rate'] ?? worker?['hourly_rate'] ?? 0).toDouble();

              earned = workedHours * rate;
            });
          });

          final now = DateTime.now();
          final diff = now.difference(startTime!);

          workedHours = diff.inSeconds / 3600;

          final rate =
          (shiftData['pay_rate'] ?? workerData?['hourly_rate'] ?? 0).toDouble();

          earned = workedHours * rate;
        }

    } catch (e) {
      debugPrint('LOAD WORKER ERROR: $e');
      if (!mounted) return;
      setState(() => loading = false);
    }
  }




  Map<String, dynamic>? worker;
  bool loading = true;

  void _onPayWorkerPressed() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Pay worker — coming next step'),
      ),
    );
  }
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final avatarUrl = worker?['avatar_url'];
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      backgroundColor: cs.background,
      appBar: AppBar(
        title: const Text('Worker'),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(), // 🌊 мягкий скролл
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [

                // ================= HEADER =================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        backgroundColor: Colors.transparent,
                        backgroundImage:
                        (avatarUrl != null && avatarUrl.toString().isNotEmpty)
                            ? NetworkImage(avatarUrl)
                            : const AssetImage(
                          'assets/images/avatar_placeholder.png',
                        ) as ImageProvider,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              worker?['email'] ?? 'Unknown worker',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              onShift ? 'ON SHIFT • LIVE' : 'OFF SHIFT',
                              style: TextStyle(
                                color:
                                onShift ? Colors.greenAccent : cs.outline,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'id: ${widget.workerId}',
                              style: TextStyle(
                                color: cs.outline,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ================= HOURLY RATE =================
                _InfoRow(
                  icon: Icons.attach_money,
                  label: 'Hourly rate',
                  value: '\$${worker?['hourly_rate'] ?? 0}',
                  color: Colors.redAccent,
                ),

                const SizedBox(height: 12),

                // ================= CURRENT SHIFT =================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Current shift',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MiniRow(
                        'Started',
                        activeShift != null
                            ? DateFormat('HH:mm').format(
                          DateTime.parse(
                            activeShift!['start_time'],
                          ).toLocal(),
                        )
                            : '—',
                      ),
                      _MiniRow(
                        'Worked',
                        startTime != null
                            ? '${workedHours.toStringAsFixed(2)} h'
                            : '--',
                      ),
                      const SizedBox(height: 12),
                      Center(
                        child: Text(
                          '\$${earned.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 32,
                            fontWeight: FontWeight.w900,
                            color: Colors.greenAccent,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 18),

                // ================= FORCE END SHIFT =================
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF7A1E2B),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  onPressed: onShift ? _onForceEndPressed : null,
                  child: const Text(
                    'Force end shift',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                ),

                const SizedBox(height: 18),

                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: TableCalendar(
                    firstDay: DateTime.utc(2023, 1, 1),
                    lastDay: DateTime.now(),
                    focusedDay: _focusedDay,
                    selectedDayPredicate: (day) =>
                    _selectedDay != null && isSameDay(day, _selectedDay),
                    onDaySelected: (selected, focused) {
                      setState(() {
                        _selectedDay = selected;
                        _focusedDay = focused;
                      });
                    },
                    calendarStyle: const CalendarStyle(
                      markerDecoration: BoxDecoration(
                        color: Colors.greenAccent,
                        shape: BoxShape.circle,
                      ),
                    ),
                    eventLoader: (day) {
                      final key = DateTime(day.year, day.month, day.day);
                      return _workDays[key] ?? [];
                    },
                  ),
                ),


                if (unpaidCount > 0)
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orangeAccent.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: Colors.orangeAccent.withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Unpaid shifts',
                          style: TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '$unpaidCount shifts • \$${unpaidTotal.toStringAsFixed(2)}',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w900,
                            color: Colors.orangeAccent,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _onPayWorkerPressed,
                            child: const Text(
                              'Pay this worker',
                              style: TextStyle(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),


                // ================= HISTORY =================
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: cs.surface,
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: cs.outlineVariant),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'History',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                      const SizedBox(height: 12),

                      if (history.isEmpty)
                        const Text('No history yet')
                      else
                        Builder(
                          builder: (context) {
                            final grouped = _groupHistoryByDate();

                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [

                                // 📅 DAYS
                                ...grouped.entries.map((entry) {
                                  final date = entry.key;
                                  final rows = entry.value;

                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [

                                        // ===== DATE HEADER =====
                                        Text(
                                          date,
                                          style: TextStyle(
                                            fontWeight: FontWeight.w900,
                                            fontSize: 14,
                                            color: cs.onSurface,
                                          ),
                                        ),
                                        const SizedBox(height: 8),

                                        // ===== SHIFTS FOR DAY =====
                                        ...rows.map((row) {
                                          final start = DateTime.parse(row['start_time']).toLocal();
                                          final end = DateTime.parse(row['end_time']).toLocal();
                                          final bool paid = row['paid_at'] != null;

                                          return Padding(
                                            padding: const EdgeInsets.only(bottom: 12),
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.stretch,
                                              children: [

                                                Row(
                                                  children: [
                                                    Expanded(
                                                      child: _HistoryRow(
                                                        date: '',
                                                        time: '${DateFormat.Hm().format(start)} → ${DateFormat.Hm().format(end)}',
                                                        earned: '\$${(row['total_payment'] ?? 0).toStringAsFixed(2)}',
                                                      ),
                                                    ),
                                                    const SizedBox(width: 10),
                                                    Container(
                                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                                      decoration: BoxDecoration(
                                                        color: paid
                                                            ? Colors.green.withOpacity(0.15)
                                                            : Colors.orange.withOpacity(0.15),
                                                        borderRadius: BorderRadius.circular(12),
                                                      ),
                                                      child: Text(
                                                        paid ? 'PAID' : 'UNPAID',
                                                        style: TextStyle(
                                                          color: paid ? Colors.green : Colors.orange,
                                                          fontWeight: FontWeight.w800,
                                                          fontSize: 12,
                                                        ),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ],
                                            ),
                                          );
                                        }).toList(),

                                      ],
                                    ),
                                  );
                                }),

                                // ===== SHOW MORE =====
                                if (_hasMoreHistory)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 8),
                                    child: Center(
                                      child: TextButton(
                                        onPressed: _loadingMore
                                            ? null
                                            : () async {
                                          setState(() => _loadingMore = true);

                                          _historyLimit += 10;
                                          await _loadWorker();

                                          if (mounted) {
                                            setState(() => _loadingMore = false);
                                          }
                                        },
                                        child: _loadingMore
                                            ? const SizedBox(
                                          width: 20,
                                          height: 20,
                                          child:
                                          CircularProgressIndicator(strokeWidth: 2),
                                        )
                                            : const Text('Show more'),
                                      ),
                                    ),
                                  ),
                              ],
                            );
                          },
                        ),


                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),

    );
  }
  Future<void> _onForceEndPressed() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Force end shift'),
        content: const Text(
          'This will immediately stop the shift and calculate payment.\n\nAre you sure?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Force End'),
          ),
        ],
      ),
    );

    if (ok == true) {
      await _forceEndShift();

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Shift force-ended')),
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

}

// ====== SMALL UI PARTS ======

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: cs.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: cs.outline),
            ),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _MiniRow extends StatelessWidget {
  final String label;
  final String value;

  const _MiniRow(this.label, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(color: cs.outline),
            ),
          ),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _HistoryRow extends StatelessWidget {
  final String date;
  final String time;
  final String earned;

  const _HistoryRow({
    required this.date,
    required this.time,
    required this.earned,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(date, style: const TextStyle(fontWeight: FontWeight.w700)),
              Text(time, style: TextStyle(color: cs.outline)),
            ],
          ),
        ),
        Text(
          earned,
          style: const TextStyle(
            fontWeight: FontWeight.w900,
            color: Colors.greenAccent,
          ),
        ),
      ],
    );
  }
}
