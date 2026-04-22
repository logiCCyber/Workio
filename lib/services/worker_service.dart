import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

class WorkerService {
  final SupabaseClient _db = Supabase.instance.client;

  User get _user {
    final u = _db.auth.currentUser;
    if (u == null) throw Exception('Not authenticated');
    return u;
  }

  Future<String> getCurrentAddress() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      return 'Location disabled';
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      return 'Location permission denied';
    }

    Position pos;
    try {
      pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
        timeLimit: const Duration(seconds: 10),
      );
    } catch (_) {
      return 'Location not available';
    }

    List<Placemark> placemarks;
    try {
      placemarks = await placemarkFromCoordinates(
        pos.latitude,
        pos.longitude,
      );
    } catch (_) {
      return 'Unknown location';
    }

    if (placemarks.isEmpty) return 'Unknown address';

    final p = placemarks.first;

    return [
      if ((p.street ?? '').isNotEmpty) p.street,
      if ((p.locality ?? '').isNotEmpty) p.locality,
      if ((p.administrativeArea ?? '').isNotEmpty) p.administrativeArea,
      if ((p.country ?? '').isNotEmpty) p.country,
    ].join(', ');
  }



  Future<Map<String, dynamic>?> getActiveShift() async {
    final res = await _db
        .from('work_logs')
        .select('id, start_time, end_time, total_hours, total_payment, pay_rate')
        .eq('user_id', _user.id)
        .isFilter('end_time', null)
        .maybeSingle();
    return res;
  }

  Future<Map<String, dynamic>?> getLastCompletedShift() async {
    final res = await _db
        .from('work_logs')
        .select('id, start_time, end_time, total_hours, total_payment, pay_rate')
        .eq('user_id', _user.id)
        .not('end_time', 'is', null)
        .order('start_time', ascending: false)
        .limit(1)
        .maybeSingle();
    return res;
  }

  /// Totals are computed in Dart (minimal + stable).
  Future<({double totalHours, double totalEarned})> getTotals() async {
    final rows = await _db
        .from('work_logs')
        .select('total_hours, total_payment, end_time')
        .eq('user_id', _user.id)
        .not('end_time', 'is', null)
        .order('start_time', ascending: false);

    double h = 0;
    double e = 0;

    for (final r in (rows as List)) {
      final th = r['total_hours'];
      final te = r['total_payment'];
      h += _toDouble(th) ?? 0;
      e += _toDouble(te) ?? 0;
    }

    return (totalHours: h, totalEarned: e);
  }

  Future<Map<String, dynamic>?> getWorkerProfile() async {
    return await _db
        .from('workers')
        .select('name, avatar_url, hourly_rate, access_mode, can_view_address, is_active, view_only_at, suspended_at')
        .eq('auth_user_id', _user.id)
        .maybeSingle();
  }

  Future<Map<String, dynamic>?> getLastPayment() async {
    return await _db
        .from('payments')
        .select('id, period_from, period_to, total_hours, total_amount, created_at')
        .eq('worker_auth_id', _user.id)
        .order('created_at', ascending: false)
        .limit(1)
        .maybeSingle();
  }

  Future<void> startShift() async {
    final active = await getActiveShift();
    if (active != null) {
      throw Exception('Shift already active');
    }

    final worker = await _db
        .from('workers')
        .select('name, hourly_rate')
        .eq('auth_user_id', _user.id)
        .maybeSingle();

    if (worker == null) {
      throw Exception('Worker profile not found');
    }

    final hourlyRate = _toDouble(worker['hourly_rate']) ?? 0;
    if (hourlyRate <= 0) {
      throw Exception('Hourly rate is invalid');
    }

    final rawName = worker['name']?.toString().trim();
    final userName = (rawName != null && rawName.isNotEmpty)
        ? rawName
        : (_user.email ?? 'Worker');

    final nowUtc = DateTime.now().toUtc();
    final address = await getCurrentAddress();

    await _db.from('work_logs').insert({
      'user_id': _user.id,
      'user_name': userName,
      'start_time': nowUtc.toIso8601String(),
      'pay_rate': hourlyRate,
      'address_start': address,
    });

    await sendShiftEvent(
      eventType: 'start',
      startedAt: nowUtc.toIso8601String(),
      addressText: address,
    );
  }


  Future<({Duration duration, double payment, double hours})> endShift({
    required String shiftId,
    required DateTime startUtc,
  }) async {
    final shift = await _db
        .from('work_logs')
        .select('id, pay_rate, end_time')
        .eq('id', shiftId)
        .eq('user_id', _user.id)
        .isFilter('end_time', null)
        .maybeSingle();

    if (shift == null) {
      throw Exception('Active shift not found');
    }

    final hourlyRate = _toDouble(shift['pay_rate']) ?? 0;
    if (hourlyRate <= 0) {
      throw Exception('Pay rate is invalid');
    }

    final endUtc = DateTime.now().toUtc();
    final dur = endUtc.difference(startUtc);
    final hours = dur.inSeconds / 3600.0;
    final payment = hours * hourlyRate;

    final address = await getCurrentAddress();

    await _db.from('work_logs').update({
      'end_time': endUtc.toIso8601String(),
      'total_hours': hours,
      'total_payment': payment,
      'address_end': address,
    }).eq('id', shiftId).eq('user_id', _user.id);

    await sendShiftEvent(
      eventType: 'end',
      startedAt: startUtc.toIso8601String(),
      endedAt: endUtc.toIso8601String(),
      hours: hours,
      earned: payment,
      addressText: address,
    );

    return (duration: dur, payment: payment, hours: hours);
  }


  Future<void> logout() => _db.auth.signOut();

  double? _toDouble(dynamic v) {
    if (v == null) return null;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString());
  }
  Future<List<Map<String, dynamic>>> getHistory() async {
    final workerRow = await _db
        .from('workers')
        .select('can_view_address')
        .eq('auth_user_id', _user.id)
        .maybeSingle();

    final canViewAddress = workerRow?['can_view_address'] == true;

    final res = await _db
        .from('work_logs')
        .select('''
      id,
      start_time,
      end_time,
      total_hours,
      total_payment,
      pay_rate,
      address_start,
      address_end,
      payment_status,
      paid_at
    ''')
        .eq('user_id', _user.id)
        .order('start_time', ascending: false);

    final rows = List<Map<String, dynamic>>.from(res);

    return rows.map((row) {
      return {
        ...row,
        'can_view_address': canViewAddress,
        'address_start': canViewAddress ? row['address_start'] : null,
        'address_end': canViewAddress ? row['address_end'] : null,
      };
    }).toList();
  }
  /// 🔔 Notify admin about shift start / end
  Future<void> sendShiftEvent({
    required String eventType, // start | end
    String? startedAt,
    String? endedAt,
    double? hours,
    double? earned,
    String? addressText, // 👈 ВАЖНО
  }) async {
    final user = _db.auth.currentUser;
    if (user == null) return;

    await _db.functions.invoke(
      'shift-event',
      body: {
        'event_type': eventType,
        'worker_id': user.id,
        'worker_email': user.email,
        'started_at': startedAt,
        'ended_at': endedAt,
        'hours': hours,
        'earned': earned,
        'address_text': addressText, // 👈 ОТПРАВЛЯЕМ
      },
    );
  }





}

