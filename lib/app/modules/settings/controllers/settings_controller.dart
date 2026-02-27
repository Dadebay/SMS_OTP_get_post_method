import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:sms_otp/app/data/app_settings_service.dart';

class SettingsController extends GetxController {
  final GlobalKey<FormState> formKey = GlobalKey<FormState>();
  final TextEditingController getSmsUrlController = TextEditingController();
  final TextEditingController sendSmsUrlController = TextEditingController();
  final TextEditingController messageTemplateController = TextEditingController();
  final RxInt selectedInterval = AppSettingsService.defaultFetchIntervalSeconds.obs;
  final RxBool useTemplate = AppSettingsService.defaultUseTemplate.obs;
  final RxInt selectedSimSlot = AppSettingsService.defaultSimSlot.obs;

  late final AppSettingsService _settingsService;

  final List<int> intervalOptions = const <int>[15, 30, 45, 60, 120];

  @override
  void onInit() {
    super.onInit();
    _settingsService = Get.find<AppSettingsService>();
    getSmsUrlController.text = _settingsService.getSmsUrl.value;
    sendSmsUrlController.text = _settingsService.sendSmsUrl.value;
    selectedInterval.value = _settingsService.fetchIntervalSeconds.value;
    messageTemplateController.text = _settingsService.messageTemplate.value;
    useTemplate.value = _settingsService.useTemplate.value;
    selectedSimSlot.value = _settingsService.simSlot.value;
  }

  String? validateUrl(String? value) {
    final String url = value?.trim() ?? '';
    if (url.isEmpty) {
      return 'URL boş bolup bilmez';
    }

    final Uri? parsed = Uri.tryParse(url);
    if (parsed == null || !parsed.hasScheme || !parsed.hasAuthority) {
      return 'Dogry URL giriziň';
    }
    return null;
  }

  Future<bool> saveSettings() async {
    print('saveSettings called'); // Debug
    print('GET URL: ${getSmsUrlController.text}'); // Debug
    print('SEND URL: ${sendSmsUrlController.text}'); // Debug
    print('Interval: ${selectedInterval.value}'); // Debug

    final bool isValid = formKey.currentState?.validate() ?? false;
    print('Form validation result: $isValid'); // Debug

    if (!isValid) {
      print('Form validation failed'); // Debug
      return false;
    }

    try {
      await _settingsService.updateGetSmsUrl(getSmsUrlController.text);
      await _settingsService.updateSendSmsUrl(sendSmsUrlController.text);
      await _settingsService.updateFetchInterval(selectedInterval.value);
      await _settingsService.updateMessageTemplate(messageTemplateController.text);
      await _settingsService.updateUseTemplate(useTemplate.value);
      await _settingsService.updateSimSlot(selectedSimSlot.value);
      print('Settings saved successfully'); // Debug
      return true;
    } catch (e) {
      print('Error in saveSettings: $e'); // Debug
      return false;
    }
  }

  @override
  void onClose() {
    getSmsUrlController.dispose();
    sendSmsUrlController.dispose();
    messageTemplateController.dispose();
    super.onClose();
  }
}
