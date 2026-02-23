import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class AppSettingsService extends GetxService {
  static const String _getSmsUrlKey = 'settings_get_sms_url';
  static const String _sendSmsUrlKey = 'settings_send_sms_url';
  static const String _fetchIntervalKey = 'settings_fetch_interval_seconds';

  static const String defaultGetSmsUrl = 'http://yhlaslynazar.com.tm:8000/getsms/';
  static const String defaultSendSmsUrl = 'http://yhlaslynazar.com.tm:8000/sendsms/';
  static const int defaultFetchIntervalSeconds = 60;

  final GetStorage _storage = GetStorage();

  final RxString getSmsUrl = defaultGetSmsUrl.obs;
  final RxString sendSmsUrl = defaultSendSmsUrl.obs;
  final RxInt fetchIntervalSeconds = defaultFetchIntervalSeconds.obs;

  Future<AppSettingsService> init() async {
    getSmsUrl.value = _normalizeUrl(_storage.read(_getSmsUrlKey) as String? ?? defaultGetSmsUrl);
    sendSmsUrl.value = _normalizeUrl(_storage.read(_sendSmsUrlKey) as String? ?? defaultSendSmsUrl);

    final int? savedInterval = _storage.read(_fetchIntervalKey) as int?;
    fetchIntervalSeconds.value = savedInterval ?? defaultFetchIntervalSeconds;
    return this;
  }

  Future<void> updateGetSmsUrl(String value) async {
    final String normalizedValue = _normalizeUrl(value);
    getSmsUrl.value = normalizedValue;
    await _storage.write(_getSmsUrlKey, normalizedValue);
  }

  Future<void> updateSendSmsUrl(String value) async {
    final String normalizedValue = _normalizeUrl(value);
    sendSmsUrl.value = normalizedValue;
    await _storage.write(_sendSmsUrlKey, normalizedValue);
  }

  Future<void> updateFetchInterval(int seconds) async {
    fetchIntervalSeconds.value = seconds;
    await _storage.write(_fetchIntervalKey, seconds);
  }

  String _normalizeUrl(String value) {
    return value.trim();
  }
}
