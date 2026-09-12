import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';
import 'package:sms_otp/app/data/usage_service.dart';

class HomeController extends GetxController {
  static const _eventsKey = 'events';
  static const _pollingIntervalKey = 'pollingIntervalSeconds';
  static const supportedPollingIntervals = <int>[3, 30, 60, 120];

  /// Kayıt listesi sınırsız büyürse hem RAM hem de her yazmada yapılan JSON
  /// serileştirmesi arayüzü kilitliyor; son [_maxEvents] kayıt yeterli.
  static const _maxEvents = 200;

  final events = <Map<String, String>>[].obs;
  final state = 'Bağlanıyor'.obs;
  final isPolling = false.obs;
  final pollingIntervalSeconds = 60.obs;
  final lastSuccessfulSync = Rxn<DateTime>();
  final sentCount = 0.obs;
  final failedCount = 0.obs;
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

  @override
  void onInit() {
    super.onInit();
    final saved = _storage.read<List<dynamic>>(_eventsKey) ?? [];
    events.assignAll(saved
        .map((item) => Map<String, String>.from(item as Map))
        .where((item) => item.containsKey('phone'))
        .take(_maxEvents));
    _recountStats();
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
    events.insert(0, {
      'phone': phone,
      'otp': otp,
      'status': status,
      'time': DateTime.now().toLocal().toString().substring(0, 19)
    });
    if (events.length > _maxEvents) {
      events.removeRange(_maxEvents, events.length);
    }
    _recountStats();
    _persistEvents();
  }

  /// Sayaçları listeyle birlikte bir kez güncelliyoruz; aksi halde her kare
  /// yeniden çiziminde tüm liste iki kez taranıyordu.
  void _recountStats() {
    var sent = 0;
    var failed = 0;
    for (final event in events) {
      if (event['status'] == 'sent') {
        sent++;
      } else if (event['status'] == 'failed') {
        failed++;
      }
    }
    sentCount.value = sent;
    failedCount.value = failed;
  }

  /// Disk yazımını kısa bir süre geciktirip toplu yapıyoruz: art arda gelen
  /// değişikliklerde tüm listeyi tekrar tekrar JSON'a çevirmek jank yaratıyor.
  void _persistEvents() {
    _persistTimer?.cancel();
    _persistTimer = Timer(const Duration(milliseconds: 400), () {
      _storage.write(_eventsKey, events.toList());
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
    events.removeAt(index);
    _recountStats();
    _persistEvents();
  }

  void clearEvents() {
    events.clear();
    _recountStats();
    _persistEvents();
  }

  @override
  void onClose() {
    _timer?.cancel();
    _heartbeatTimer?.cancel();
    _persistTimer?.cancel();
    _storage.write(_eventsKey, events.toList());
    _gateway.dispose();
    super.onClose();
  }
}
