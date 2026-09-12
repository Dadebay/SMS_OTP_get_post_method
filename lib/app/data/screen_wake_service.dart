import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

/// Uygulama açıkken ekranın kapanmasını engeller.
///
/// Android'de wakelock, Activity penceresine `FLAG_KEEP_SCREEN_ON` ekleyerek
/// çalışır. Bayrak pencereye bağlı olduğu için uygulama arka plana alınıp geri
/// döndüğünde (ya da Activity yeniden oluşturulduğunda) kaybolabiliyor; bu
/// yüzden yaşam döngüsünü dinleyip `resumed` olduğunda tekrar açıyoruz.
class ScreenWakeService with WidgetsBindingObserver {
  ScreenWakeService._();

  static final ScreenWakeService instance = ScreenWakeService._();

  bool _started = false;

  /// İlk kareden sonra çağrılmalı: eklenti, bayrağı uygulamak için bağlı bir
  /// Activity'ye ihtiyaç duyar.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    await _enable();
  }

  Future<void> stop() async {
    if (!_started) return;
    _started = false;
    WidgetsBinding.instance.removeObserver(this);
    await _disable();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (!_started) return;
    if (state == AppLifecycleState.resumed) {
      _enable();
    }
  }

  Future<void> _enable() async {
    try {
      if (!await WakelockPlus.enabled) await WakelockPlus.enable();
    } catch (_) {
      // Platform desteklemiyorsa sessizce geç.
    }
  }

  Future<void> _disable() async {
    try {
      if (await WakelockPlus.enabled) await WakelockPlus.disable();
    } catch (_) {}
  }
}
