import 'dart:async';
import 'dart:convert';

import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_otp/app/data/gateway_task.dart';
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
  static const supportedPollingIntervals = <int>[3, 5, 10];

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
  Timer? _persistTimer;
  bool _starting = false;

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
    events.assignAll(saved.map((item) {
      final event = Map<String, String>.from(item as Map);
      event['jobId'] ??= 'Eski işlem';
      return event;
    }).take(_maxEvents));
    _storage.write(_eventsKey, events.toList());
    _loadStats();
    _persistEvents();
    final savedInterval = _storage.read<int>(_pollingIntervalKey) ?? 3;
    pollingIntervalSeconds.value =
        supportedPollingIntervals.contains(savedInterval) ? savedInterval : 3;
    initializeGatewayTask(pollingIntervalSeconds.value);
    FlutterForegroundTask.addTaskDataCallback(_onTaskData);
    unawaited(syncEventsFromTask());
    if (_storage.read<bool>(SmsGatewayService.tokenRejectedKey) == true) {
      state.value = 'Cihaz tokenı iptal edilmiş. Ayarlardan yenileyin.';
    } else if (isConfigured) {
      unawaited(start());
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
    if (_starting) return;
    if (!isConfigured) {
      state.value = 'Ayarlar gerekli';
      return;
    }
    if (_storage.read<bool>(SmsGatewayService.tokenRejectedKey) == true) {
      state.value = 'Cihaz tokenı iptal edilmiş. Ayarlardan yenileyin.';
      return;
    }
    if (!await Permission.sms.isGranted || !await Permission.phone.isGranted) {
      state.value = 'SMS ve telefon izinleri gerekli';
      return;
    }
    if (_gateway.subscriptionId == null) {
      state.value = 'Ayarlardan gönderici SIM seçin';
      return;
    }
    _starting = true;
    try {
      if (await FlutterForegroundTask.checkNotificationPermission() !=
          NotificationPermission.granted) {
        await FlutterForegroundTask.requestNotificationPermission();
      }
      if (!await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.startService(
          serviceId: 256,
          serviceTypes: [ForegroundServiceTypes.remoteMessaging],
          notificationTitle: 'Aykitap OTP Gateway',
          notificationText: 'SMS kuyruğu izleniyor',
          callback: startGatewayTask,
        );
      }
      isPolling.value = await FlutterForegroundTask.isRunningService;
      state.value = isPolling.value ? 'Bağlanıyor' : 'Gateway başlatılamadı';
    } catch (_) {
      state.value = 'Gateway servisi başlatılamadı';
      isPolling.value = false;
    } finally {
      _starting = false;
    }
  }

  Future<void> poll() async {
    FlutterForegroundTask.sendDataToTask('poll');
  }

  Future<void> stop() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
    isPolling.value = false;
    state.value = 'Durduruldu';
  }

  Future<void> setPollingInterval(int seconds) async {
    if (!supportedPollingIntervals.contains(seconds)) return;
    pollingIntervalSeconds.value = seconds;
    await _storage.write(_pollingIntervalKey, seconds);
    initializeGatewayTask(seconds);
    if (isPolling.value) {
      await FlutterForegroundTask.updateService(
        foregroundTaskOptions: ForegroundTaskOptions(
          eventAction: ForegroundTaskEventAction.repeat(seconds * 1000),
          autoRunOnBoot: false,
          autoRunOnMyPackageReplaced: false,
          allowWakeLock: true,
          allowWifiLock: true,
        ),
      );
    }
  }

  void _onTaskData(Object data) {
    if (data is! Map) return;
    switch (data['type']) {
      case 'event':
        addEvent(data['jobId'] as String, data['status'] as String,
            time: data['time'] as String?,
            eventId: data['eventId'] as String?,
            phone: data['phone'] as String?,
            otp: data['otp'] as String?);
      case 'state':
        state.value = data['value'] as String;
        if (state.value.startsWith('Çevrimiçi')) {
          lastSuccessfulSync.value = DateTime.now();
          unawaited(UsageService.instance.sample());
        }
      case 'stopped':
        isPolling.value = false;
        state.value = data['value'] as String;
    }
  }

  Future<void> syncEventsFromTask() async {
    final raw = await FlutterForegroundTask.getData<String>(
        key: GatewayTaskHandler.eventsKey);
    final saved = raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
    for (final entry in saved.reversed) {
      final event = Map<String, String>.from(entry as Map);
      addEvent(event['jobId']!, event['status']!,
          time: event['time'],
          eventId: event['eventId'],
          phone: event['phone'],
          otp: event['otp']);
    }
  }

  void addEvent(String jobId, String status,
      {String? time, String? eventId, String? phone, String? otp}) {
    final id = eventId ?? '$jobId:${DateTime.now().microsecondsSinceEpoch}';
    if (events.any((event) => event['eventId'] == id)) return;
    final now = time == null ? DateTime.now().toLocal() : DateTime.parse(time);
    events.insert(0, {
      'eventId': id,
      'jobId': jobId,
      'status': status,
      'time': time ?? now.toString().substring(0, 19),
      if (phone != null) 'phone': phone,
      if (otp != null) 'otp': otp,
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
    _persistTimer?.cancel();
    _storage.write(_eventsKey, events.toList());
    _persistStats();
    _gateway.dispose();
    FlutterForegroundTask.removeTaskDataCallback(_onTaskData);
    super.onClose();
  }
}
