import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';
import 'package:sms_otp/app/data/usage_service.dart';

/// Tek bir günün gönderim özeti.
class DayStat {
  const DayStat({required this.day, required this.sent, required this.failed});

  final DateTime day;
  final int sent;
  final int failed;

  int get total => sent + failed;
}

class HomeController extends GetxController {
  static const _eventsKey = 'events';
  static const _statsKey = 'event_stats';
  static const _pollingIntervalKey = 'pollingIntervalSeconds';
  static const supportedPollingIntervals = <int>[3, 30, 60, 120];

  /// Kayıt listesi sınırsız büyürse hem RAM hem de her yazmada yapılan JSON
  /// serileştirmesi arayüzü kilitliyor; son [_maxEvents] kayıt yeterli.
  static const _maxEvents = 200;

  /// Günlük sayaçların kaç gün geriye saklandığı. Toplam sayaç bundan
  /// etkilenmez; o hiç kırpılmaz.
  static const retainedStatDays = 90;

  final events = <Map<String, String>>[].obs;
  final state = 'Bağlanıyor'.obs;
  final isPolling = false.obs;
  final pollingIntervalSeconds = 60.obs;
  final lastSuccessfulSync = Rxn<DateTime>();

  /// Toplam sayaçlar artık listeden türetilmiyor: liste [_maxEvents] kaydda
  /// kırpıldığı için sayaç 200'de takılıp kalıyordu. Bunlar kalıcı olarak
  /// diskte birikir ve yalnızca kullanıcı silerse azalır.
  final sentCount = 0.obs;
  final failedCount = 0.obs;

  /// Gün anahtarı (`yyyy-MM-dd`) -> {'sent': n, 'failed': n}
  final dailyStats = <String, Map<String, int>>{}.obs;

  final _storage = GetStorage();
  Timer? _timer;
  Timer? _heartbeatTimer;
  Timer? _persistTimer;
  bool _inFlight = false;

  // Tek bir servis örneği: her erişimde yeni bir `SmsGatewayService`
  // oluşturmak her istekte yeni bir HttpClient açıyor, keep-alive'ı bozuyor ve
  // soketleri hiç kapatmıyordu.
  final SmsGatewayService _gateway = SmsGatewayService();
  bool get isConfigured => _gateway.isConfigured;

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  /// Gün bazında özet, yeniden eskiye sıralı.
  List<DayStat> get dailyBreakdown {
    final keys = dailyStats.keys.toList()..sort((a, b) => b.compareTo(a));
    return [
      for (final key in keys)
        DayStat(
          day: DateTime.parse(key),
          sent: dailyStats[key]?['sent'] ?? 0,
          failed: dailyStats[key]?['failed'] ?? 0,
        ),
    ];
  }

  DayStat statForKey(String key) => DayStat(
        day: DateTime.parse(key),
        sent: dailyStats[key]?['sent'] ?? 0,
        failed: dailyStats[key]?['failed'] ?? 0,
      );

  DayStat get todayStat => statForKey(dayKey(DateTime.now()));

  DayStat get yesterdayStat =>
      statForKey(dayKey(DateTime.now().subtract(const Duration(days: 1))));

  @override
  void onInit() {
    super.onInit();
    final saved = _storage.read<List<dynamic>>(_eventsKey) ?? [];
    events.assignAll(saved
        .map((item) => Map<String, String>.from(item as Map))
        .where((item) => item.containsKey('phone'))
        .take(_maxEvents));
    _loadStats();
    _persistEvents();
    final savedInterval = _storage.read<int>(_pollingIntervalKey) ?? 3;
    pollingIntervalSeconds.value =
        supportedPollingIntervals.contains(savedInterval) ? savedInterval : 3;
    if (isConfigured) {
      start();
    } else {
      state.value = 'Bağlantı ayarları gerekli';
    }
  }

  /// Kalıcı sayaçları okur. İlk kez çalışıyorsa (eski sürümden gelen kurulum)
  /// eldeki kayıtlardan bir başlangıç değeri üretir.
  void _loadStats() {
    final raw = _storage.read<Map>(_statsKey);
    if (raw == null) {
      _seedStatsFromEvents();
      return;
    }
    sentCount.value = (raw['sent'] as num?)?.toInt() ?? 0;
    failedCount.value = (raw['failed'] as num?)?.toInt() ?? 0;
    final daily = raw['daily'];
    if (daily is Map) {
      dailyStats.assignAll({
        for (final entry in daily.entries)
          if (entry.value is Map)
            entry.key.toString(): {
              'sent': ((entry.value as Map)['sent'] as num?)?.toInt() ?? 0,
              'failed': ((entry.value as Map)['failed'] as num?)?.toInt() ?? 0,
            },
      });
    }
    // Gunluk dokum bos ama elde kayit varsa (eski surumden gelen kurulum ya da
    // yarim kalmis bir yazma) gunleri kayitlardan yeniden kur.
    if (dailyStats.isEmpty && events.isNotEmpty) _seedStatsFromEvents();
  }

  void _seedStatsFromEvents() {
    var sent = 0;
    var failed = 0;
    final daily = <String, Map<String, int>>{};
    for (final event in events) {
      final status = event['status'];
      if (status != 'sent' && status != 'failed') continue;
      if (status == 'sent') {
        sent++;
      } else {
        failed++;
      }
      final key = _eventDayKey(event);
      final bucket = daily.putIfAbsent(key, () => {'sent': 0, 'failed': 0});
      bucket[status!] = (bucket[status] ?? 0) + 1;
    }
    // Toplam sayac kayit listesinden buyuk olabilir (liste 200'de kirpiliyor);
    // tohumlama onu asla geriye cekmemeli.
    if (sent > sentCount.value) sentCount.value = sent;
    if (failed > failedCount.value) failedCount.value = failed;
    dailyStats.assignAll(daily);
    _persistStats();
  }

  /// Kaydın `time` alanı `yyyy-MM-dd HH:mm:ss` biçiminde; ilk 10 karakter gün.
  static String _eventDayKey(Map<String, String> event) {
    final time = event['time'];
    if (time != null && time.length >= 10) return time.substring(0, 10);
    return dayKey(DateTime.now());
  }

  Future<void> start() async {
    if (!isConfigured) {
      state.value = 'Ayarlar gerekli';
      return;
    }
    isPolling.value = true;
    try {
      await _gateway.heartbeat();
      lastSuccessfulSync.value = DateTime.now();
      state.value = 'Çevrimiçi — SMS bekleniyor';
      await poll();
      _schedulePolling();
      _scheduleHeartbeat();
    } on GatewayException catch (error) {
      state.value = error.message;
      isPolling.value = false;
    } catch (_) {
      // DNS, TLS and socket failures arrive as ClientException, not
      // GatewayException. `poll()` below already allows for that; here they
      // escaped as an unhandled exception and left the screen stuck on its
      // connecting state.
      state.value = 'Bağlantı hatası';
      isPolling.value = false;
    }
  }

  Future<void> poll() async {
    if (_inFlight || !isConfigured) return;
    _inFlight = true;
    try {
      await _gateway.processOne(onResult: addEvent);
      lastSuccessfulSync.value = DateTime.now();
      // Veri sayacı yalnızca örneklendiğinde ilerler; poll döngüsü bunun için
      // doğal bir tetikleyici.
      unawaited(UsageService.instance.sample());
      if (state.value != 'Ayarlar gerekli') {
        state.value = 'Çevrimiçi — SMS bekleniyor';
      }
    } on GatewayException catch (error) {
      state.value = error.message;
    } catch (_) {
      state.value = 'Bağlantı hatası';
    } finally {
      _inFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    isPolling.value = false;
    state.value = 'Durduruldu';
  }

  Future<void> setPollingInterval(int seconds) async {
    if (!supportedPollingIntervals.contains(seconds)) return;
    pollingIntervalSeconds.value = seconds;
    await _storage.write(_pollingIntervalKey, seconds);
    if (isPolling.value) _schedulePolling();
  }

  void _schedulePolling() {
    _timer?.cancel();
    _timer = Timer.periodic(
        Duration(seconds: pollingIntervalSeconds.value), (_) => poll());
  }

  void _scheduleHeartbeat() {
    _heartbeatTimer?.cancel();
    // Backend cihazı 30 saniye sonra offline kabul eder. Pull aralığı daha
    // uzun seçilse de gateway'in çevrimiçi kalması için heartbeat sürer.
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 20), (_) async {
      if (!isPolling.value || !isConfigured) return;
      try {
        await _gateway.heartbeat();
        lastSuccessfulSync.value = DateTime.now();
      } on GatewayException catch (error) {
        state.value = error.message;
      } catch (_) {
        state.value = 'Bağlantı hatası';
      }
    });
  }

  void addEvent(String phone, String otp, String status) {
    if (kDebugMode) _printOtpResult(phone: phone, otp: otp, status: status);
    final now = DateTime.now().toLocal();
    events.insert(0, {
      'phone': phone,
      'otp': otp,
      'status': status,
      'time': now.toString().substring(0, 19)
    });
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }
    _bumpStat(status, dayKey(now), 1);
    _persistEvents();
  }

  /// Toplam ve günlük sayaçları [delta] kadar ilerletir (silmede -1).
  void _bumpStat(String? status, String key, int delta) {
    if (status != 'sent' && status != 'failed') return;
    if (status == 'sent') {
      sentCount.value = (sentCount.value + delta).clamp(0, 1 << 52);
    } else {
      failedCount.value = (failedCount.value + delta).clamp(0, 1 << 52);
    }
    final bucket = {...?dailyStats[key]};
    bucket['sent'] ??= 0;
    bucket['failed'] ??= 0;
    bucket[status!] = ((bucket[status] ?? 0) + delta).clamp(0, 1 << 52);
    if (bucket['sent'] == 0 && bucket['failed'] == 0) {
      dailyStats.remove(key);
    } else {
      dailyStats[key] = bucket;
    }
    _trimDailyStats();
  }

  void _trimDailyStats() {
    if (dailyStats.length <= retainedStatDays) return;
    final oldestFirst = dailyStats.keys.toList()..sort();
    for (final key in oldestFirst.take(dailyStats.length - retainedStatDays)) {
      dailyStats.remove(key);
    }
  }

  void _persistStats() {
    _storage.write(_statsKey, {
      'sent': sentCount.value,
      'failed': failedCount.value,
      'daily': {
        for (final entry in dailyStats.entries)
          entry.key: Map<String, int>.from(entry.value),
      },
    });
  }

  /// Disk yazımını kısa bir süre geciktirip toplu yapıyoruz: art arda gelen
  /// değişikliklerde tüm listeyi tekrar tekrar JSON'a çevirmek jank yaratıyor.
  void _persistEvents() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      _storage.write(_eventsKey, events.toList());
      _persistStats();
    });
  }

  void _printOtpResult({
    required String phone,
    required String otp,
    required String status,
  }) {
    const green = '\x1B[1;32m';
    const yellow = '\x1B[1;33m';
    const cyan = '\x1B[1;36m';
    const reset = '\x1B[0m';
    debugPrint('$green╔════════════════════════════════════════╗$reset');
    debugPrint('$green║$reset ${cyan}PHONE: $phone$reset');
    debugPrint('$green║$reset ${yellow}OTP CODE: $otp$reset');
    debugPrint('$green║$reset STATUS: $status');
    debugPrint('$green╚════════════════════════════════════════╝$reset');
  }

  /// Liste filtrelenerek çizildiği için silme işlemi indeks yerine kaydın
  /// kendisiyle yapılıyor; aksi halde yanlış satır siliniyordu.
  void deleteEventRef(Map<String, String> event) {
    final index = events.indexWhere((item) => identical(item, event));
    if (index != -1) deleteEvent(index);
  }

  void deleteEvent(int index) {
    if (index < 0 || index >= events.length) return;
    final event = events[index];
    events.removeAt(index);
    _bumpStat(event['status'], _eventDayKey(event), -1);
    _persistEvents();
  }

  void clearEvents() {
    events.clear();
    sentCount.value = 0;
    failedCount.value = 0;
    dailyStats.clear();
    _persistStats();
    _persistEvents();
  }

  @override
  void onClose() {
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _persistTimer?.cancel();
    _storage.write(_eventsKey, events.toList());
    _persistStats();
    _gateway.dispose();
    super.onClose();
  }
}
