import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';

class AppSettingsService extends GetxService {
  static const String _getSmsUrlKey = 'settings_get_sms_url';
  static const String _sendSmsUrlKey = 'settings_send_sms_url';
  static const String _fetchIntervalKey = 'settings_fetch_interval_seconds';
  static const String _messageTemplateKey = 'settings_message_template';
  static const String _useTemplateKey = 'settings_use_template';
  static const String _simSlotKey = 'settings_sim_slot';

  static const String defaultGetSmsUrl = 'http://216.250.11.255:7000/mobile/uzsms/';
  static const String defaultSendSmsUrl = 'http://216.250.11.255:7000/mobile/uzsms/';
  static const int defaultFetchIntervalSeconds = 60;
  static const String defaultMessageTemplate = 'Atelyam dasturi uchun SMS kodingiz: {code}';
  static const bool defaultUseTemplate = true;
  static const int defaultSimSlot = 0;

  final GetStorage _storage = GetStorage();

  final RxString getSmsUrl = defaultGetSmsUrl.obs;
  final RxString sendSmsUrl = defaultSendSmsUrl.obs;
  final RxInt fetchIntervalSeconds = defaultFetchIntervalSeconds.obs;
  final RxString messageTemplate = defaultMessageTemplate.obs;
  final RxBool useTemplate = defaultUseTemplate.obs;
  final RxInt simSlot = defaultSimSlot.obs;

  Future<AppSettingsService> init() async {
    getSmsUrl.value = _normalizeUrl(_storage.read(_getSmsUrlKey) as String? ?? defaultGetSmsUrl);
    sendSmsUrl.value = _normalizeUrl(_storage.read(_sendSmsUrlKey) as String? ?? defaultSendSmsUrl);

    final int? savedInterval = _storage.read(_fetchIntervalKey) as int?;
    fetchIntervalSeconds.value = savedInterval ?? defaultFetchIntervalSeconds;

    messageTemplate.value = _storage.read(_messageTemplateKey) as String? ?? defaultMessageTemplate;
    useTemplate.value = _storage.read(_useTemplateKey) as bool? ?? defaultUseTemplate;
    simSlot.value = _storage.read(_simSlotKey) as int? ?? defaultSimSlot;

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

  Future<void> updateMessageTemplate(String value) async {
    messageTemplate.value = value.trim();
    await _storage.write(_messageTemplateKey, value.trim());
  }

  Future<void> updateUseTemplate(bool value) async {
    useTemplate.value = value;
    await _storage.write(_useTemplateKey, value);
  }

  Future<void> updateSimSlot(int value) async {
    simSlot.value = value;
    await _storage.write(_simSlotKey, value);
  }

  /// Format the message with template. {code} is replaced with the actual OTP.
  String formatMessage(String otp) {
    if (!useTemplate.value) return otp;
    return messageTemplate.value.replaceAll('{code}', otp);
  }

  String _normalizeUrl(String value) {
    return value.trim();
  }
}
