import 'dart:async';

import 'package:get/get.dart';
import 'package:sms_otp/app/data/usage_service.dart';

class UsageController extends GetxController {
  final _service = UsageService.instance;

  final mobileBytes = 0.obs;
  final wifiBytes = 0.obs;
  final since = Rx<DateTime>(DateTime.now());

  /// Gun bazinda kullanim, yeniden eskiye.
  final days = <UsageDay>[].obs;

  Timer? _timer;

  bool get isTrafficSupported => _service.isTrafficSupported;
  int get totalBytes => mobileBytes.value + wifiBytes.value;

  @override
  void onInit() {
    super.onInit();
    _refresh();
    _sampleNow();
    // Sayfa açıkken canlı kalsın; kapanınca timer iptal ediliyor.
    _timer = Timer.periodic(const Duration(seconds: 5), (_) => _sampleNow());
  }

  Future<void> _sampleNow() async {
    await _service.sample();
    _refresh();
  }

  void _refresh() {
    mobileBytes.value = _service.mobileBytes;
    wifiBytes.value = _service.wifiBytes;
    since.value = _service.since;
    days.assignAll(_service.dailyUsage);
  }

  Future<void> reset() async {
    await _service.resetAll();
    _refresh();
  }

  String formatBytes(int bytes) => UsageService.formatBytes(bytes);

  /// Listedeki en yuksek gun — satir cubuklarini oranlamak icin.
  int get busiestDayBytes =>
      days.isEmpty ? 0 : days.map((day) => day.bytes).reduce((a, b) => a > b ? a : b);

  /// Bugun ve dun icin tarih yerine isim: listede aranan gun genelde bunlar.
  String dayLabel(DateTime date) {
    final today = DateTime.now();
    final key = UsageService.dayKey(date);
    if (key == UsageService.dayKey(today)) return 'Bugün';
    if (key == UsageService.dayKey(today.subtract(const Duration(days: 1)))) {
      return 'Dün';
    }
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  @override
  void onClose() {
    _timer?.cancel();
    super.onClose();
  }
}
