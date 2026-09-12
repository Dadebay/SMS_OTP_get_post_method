import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:get_storage/get_storage.dart';

/// Yalnızca bu uygulamanın taşıdığı veriyi kalıcı olarak biriktirir.
///
/// Veri, Android'in `TrafficStats` API'sinden bu uygulamanın kendi UID'si için
/// okunur — yani cihazın toplam trafiği değil, sadece bu uygulamanınki. O
/// sayaçlar cihaz her açıldığında sıfırlandığı için burada ham örnekler
/// arasındaki farkı toplayarak kalıcı bir toplam tutuyoruz.
/// Tek bir gunde bu uygulamanin tasidigi veri.
class UsageDay {
  const UsageDay({required this.date, required this.bytes});

  final DateTime date;
  final int bytes;
}

class UsageService {
  UsageService._();

  static final UsageService instance = UsageService._();

  static const _channel = MethodChannel('sms_otp/usage');

  static const _mobileBytesKey = 'usage_mobile_bytes';
  static const _dailyKey = 'usage_daily';
  static const _wifiBytesKey = 'usage_wifi_bytes';
  static const _sinceKey = 'usage_since';
  // Son ham örnek — cihazın yeniden başlatıldığını tespit etmek için.
  static const _lastRawRxKey = 'usage_last_raw_rx';
  static const _lastRawTxKey = 'usage_last_raw_tx';

  static const bytesPerMb = 1024 * 1024;

  /// Gunluk kayitlarin saklandigi gun sayisi. Liste bir telefonda yillarca
  /// buyumesin diye eski gunler dusuyor; toplam sayac bundan etkilenmiyor.
  static const retainedDays = 60;

  final _storage = GetStorage();

  bool _supported = true;

  /// Cihaz uygulama başına sayacı desteklemiyorsa false döner.
  bool get isTrafficSupported => _supported;

  int get mobileBytes => _storage.read<int>(_mobileBytesKey) ?? 0;
  int get wifiBytes => _storage.read<int>(_wifiBytesKey) ?? 0;
  int get totalBytes => mobileBytes + wifiBytes;

  /// Gun bazinda biriken trafik, yeniden eskiye sirali.
  List<UsageDay> get dailyUsage {
    final entries = _dailyBytes.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries
        .map((entry) =>
            UsageDay(date: DateTime.parse(entry.key), bytes: entry.value))
        .toList(growable: false);
  }

  Map<String, int> get _dailyBytes {
    final raw = _storage.read<Map>(_dailyKey);
    if (raw == null) return <String, int>{};
    return {
      for (final entry in raw.entries)
        entry.key.toString(): (entry.value as num).toInt(),
    };
  }

  /// Farki bugunun kovasina ekler ve [retainedDays] gunden eskileri atar.
  Future<void> _addToToday(int delta) async {
    final daily = _dailyBytes;
    final today = dayKey(DateTime.now());
    daily[today] = (daily[today] ?? 0) + delta;
    if (daily.length > retainedDays) {
      final oldestFirst = daily.keys.toList()..sort();
      for (final key in oldestFirst.take(daily.length - retainedDays)) {
        daily.remove(key);
      }
    }
    await _storage.write(_dailyKey, daily);
  }

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  DateTime get since {
    final saved = _storage.read<String>(_sinceKey);
    if (saved != null) return DateTime.parse(saved);
    final now = DateTime.now();
    _storage.write(_sinceKey, now.toIso8601String());
    return now;
  }

  Future<void> resetAll() async {
    await _storage.write(_mobileBytesKey, 0);
    await _storage.write(_wifiBytesKey, 0);
    await _storage.write(_sinceKey, DateTime.now().toIso8601String());
    await _storage.remove(_dailyKey);
    await _storage.remove(_lastRawRxKey);
    await _storage.remove(_lastRawTxKey);
  }

  /// Ham sayaçları okuyup son örnekten bu yana geçen farkı toplama ekler.
  /// Düzenli çağrılması gerekir: iki örnek arasında bağlantı türü değişirse
  /// aradaki trafik, örnekleme anındaki türe yazılır.
  Future<void> sample() async {
    if (!_supported) return;
    try {
      final stats =
          await _channel.invokeMapMethod<String, dynamic>('trafficStats');
      final rx = stats?['rx'] as int?;
      final tx = stats?['tx'] as int?;
      if (rx == null || tx == null) {
        _supported = false;
        return;
      }

      final lastRx = _storage.read<int>(_lastRawRxKey);
      final lastTx = _storage.read<int>(_lastRawTxKey);
      // Sayaç geriye gittiyse cihaz yeniden başlatılmıştır; o durumda mevcut
      // değerin tamamı yeni trafiktir.
      final deltaRx = (lastRx == null || rx < lastRx) ? rx : rx - lastRx;
      final deltaTx = (lastTx == null || tx < lastTx) ? tx : tx - lastTx;
      await _storage.write(_lastRawRxKey, rx);
      await _storage.write(_lastRawTxKey, tx);

      final delta = deltaRx + deltaTx;
      if (delta <= 0) return;

      final type = await _channel.invokeMethod<String>('networkType') ?? 'other';
      final key = type == 'wifi' ? _wifiBytesKey : _mobileBytesKey;
      await _storage.write(key, (_storage.read<int>(key) ?? 0) + delta);
      await _addToToday(delta);
      since; // ilk örnekte başlangıç tarihini sabitler
    } on MissingPluginException {
      // iOS ya da eski bir derleme: veri sayacı yok.
      _supported = false;
    } catch (error) {
      if (kDebugMode) debugPrint('[USAGE] sample failed: $error');
    }
  }

  static String formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / bytesPerMb).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * bytesPerMb)).toStringAsFixed(2)} GB';
  }
}
