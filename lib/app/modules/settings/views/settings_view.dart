import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
import 'package:background_sms/background_sms.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';
import 'package:sms_otp/app/modules/home/controllers/home_controller.dart';

class SettingsView extends StatefulWidget {
  const SettingsView({super.key});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  final storage = GetStorage();
  late final url = TextEditingController(
    text: SmsGatewayService.effectiveApiBaseUrl(
      storage.read<String>(SmsGatewayService.apiBaseUrlKey),
    ),
  );
  final token = TextEditingController();
  List<SmsSubscription> subscriptions = const [];
  int? selectedSubscriptionId;
  late final HomeController home = Get.find<HomeController>();
  bool isTesting = false;

  bool get _isConfigured =>
      storage.read<bool>(SmsGatewayService.tokenConfiguredKey) == true ||
      token.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    url.addListener(() => setState(() {}));
    token.addListener(() => setState(() {}));
    selectedSubscriptionId =
        storage.read<int>(SmsGatewayService.subscriptionIdKey);
    _loadSubscriptions();
  }

  @override
  void dispose() {
    url.dispose();
    token.dispose();
    super.dispose();
  }

  Future<bool> _saveAddress() async {
    final baseUrl = url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!baseUrl.startsWith('https://')) {
      showSnackBar(context, 'Geçersiz adres',
          'Gateway için HTTPS adresi gerekli.', Colors.red);
      return false;
    }
    if (token.text.trim().isNotEmpty) {
      await const GatewaySecretStore().writeToken(token.text.trim());
      await storage.write(SmsGatewayService.tokenConfiguredKey, true);
      await storage.write(SmsGatewayService.tokenRejectedKey, false);
      token.clear();
    }
    if (storage.read<bool>(SmsGatewayService.tokenConfiguredKey) != true) {
      if (!mounted) return false;
      showSnackBar(context, 'Token gerekli',
          'Admin panelindeki cihaz tokenını girin.', Colors.red);
      return false;
    }
    if (selectedSubscriptionId == null) {
      if (!mounted) return false;
      showSnackBar(context, 'SIM gerekli', 'SMS gönderecek SIM kartını seçin.',
          Colors.red);
      return false;
    }
    await storage.write(
        SmsGatewayService.subscriptionIdKey, selectedSubscriptionId);
    await storage.write(SmsGatewayService.apiBaseUrlKey, baseUrl);
    return true;
  }

  Future<void> _loadSubscriptions() async {
    await Permission.phone.request();
    try {
      final found = await BackgroundSms.getSubscriptions();
      if (!mounted) return;
      setState(() {
        subscriptions = found;
        if (!found.any((sim) => sim.id == selectedSubscriptionId)) {
          selectedSubscriptionId = found.length == 1 ? found.first.id : null;
        }
      });
    } catch (_) {
      if (mounted) {
        showSnackBar(context, 'SIM okunamadı',
            'Telefon iznini ve SIM kartını kontrol edin.', Colors.red);
      }
    }
  }

  Future<void> _testConnection() async {
    if (!await _saveAddress() || !mounted) return;
    setState(() => isTesting = true);
    final gateway = SmsGatewayService();
    try {
      await gateway.heartbeat();
      if (mounted) {
        showSnackBar(context, 'Bağlantı başarılı', 'Gateway bağlantısı hazır.',
            const Color(0xff157a50));
      }
    } on GatewayException catch (error) {
      if (mounted) {
        showSnackBar(context, 'Bağlantı kurulamadı', error.message, Colors.red);
      }
    } catch (_) {
      if (mounted) {
        showSnackBar(context, 'Bağlantı kurulamadı',
            'Ağ erişimini ve API adresini kontrol edin.', Colors.red);
      }
    } finally {
      gateway.dispose();
      if (mounted) setState(() => isTesting = false);
    }
  }

  Future<void> _saveAndStart() async {
    if (!await _saveAddress()) return;
    await Permission.sms.request();
    if (!await FlutterForegroundTask.isIgnoringBatteryOptimizations) {
      await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    }
    await home.stop();
    await home.start();
    if (mounted) Get.back();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfff5f7fb),
        appBar: AppBar(
          backgroundColor: const Color(0xfff5f7fb),
          surfaceTintColor: Colors.transparent,
          title: const Text('Ayarlar',
              style: TextStyle(
                  color: Color(0xff17233b), fontWeight: FontWeight.w800)),
        ),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
          children: [
            _sectionCard(
              icon: HugeIcons.strokeRoundedServerStack01,
              title: 'Backend bağlantısı',
              subtitle: 'Aykitap OTP SMS API adresi ve bu cihazın tokenı.',
              child: Column(children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                      color: const Color(0xfff5f7fb),
                      borderRadius: BorderRadius.circular(16)),
                  child: TextField(
                    controller: url,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(
                      icon: HugeIcon(
                          icon: HugeIcons.strokeRoundedLink01,
                          color: Color(0xff496598)),
                      labelText: 'API adresi',
                      hintText: SmsGatewayService.defaultApiBaseUrl,
                      border: InputBorder.none,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: token,
                  obscureText: true,
                  autocorrect: false,
                  enableSuggestions: false,
                  decoration: InputDecoration(
                    labelText: 'Cihaz tokenı',
                    hintText: _isConfigured
                        ? 'Mevcut token korunacak'
                        : 'Admin panelinden alınan token',
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<int>(
                  key: ValueKey(selectedSubscriptionId),
                  initialValue: subscriptions
                          .any((sim) => sim.id == selectedSubscriptionId)
                      ? selectedSubscriptionId
                      : null,
                  decoration: const InputDecoration(
                      labelText: 'Gönderici SIM', border: OutlineInputBorder()),
                  items: [
                    for (final sim in subscriptions)
                      DropdownMenuItem(
                          value: sim.id,
                          child: Text('SIM ${sim.slot + 1} · ${sim.name}'))
                  ],
                  onChanged: (value) =>
                      setState(() => selectedSubscriptionId = value),
                ),
                if (subscriptions.isEmpty)
                  TextButton(
                      onPressed: _loadSubscriptions,
                      child: const Text('SIM listesini yenile')),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: isTesting ? null : _testConnection,
                    icon: isTesting
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2))
                        : const HugeIcon(
                            icon: HugeIcons.strokeRoundedWifiConnected03),
                    label: Text(isTesting
                        ? 'Bağlantı kontrol ediliyor…'
                        : 'Bağlantıyı test et'),
                    style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        foregroundColor: const Color(0xff304b85)),
                  ),
                ),
              ]),
            ),
            const SizedBox(height: 16),
            _sectionCard(
              icon: HugeIcons.strokeRoundedTime01,
              title: 'Kontrol sıklığı',
              subtitle: 'Gateway kuyruğun ne sıklıkla yoklanacağını belirler.',
              child: Obx(() => Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children:
                        HomeController.supportedPollingIntervals.map((seconds) {
                      final selected =
                          home.pollingIntervalSeconds.value == seconds;
                      return ChoiceChip(
                        label: Text('$seconds saniye'),
                        selected: selected,
                        onSelected: (_) => home.setPollingInterval(seconds),
                        backgroundColor: const Color(0xfff5f7fb),
                        selectedColor: const Color(0xffdce7ff),
                        labelStyle: TextStyle(
                            color: selected
                                ? const Color(0xff25477f)
                                : const Color(0xff536078),
                            fontWeight: FontWeight.w700),
                        side: BorderSide.none,
                      );
                    }).toList(),
                  )),
            ),
            const SizedBox(height: 28),
            FilledButton.icon(
              onPressed: _saveAndStart,
              icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedPlay, color: Colors.white),
              label: const Text('Kaydet ve başlat'),
              style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xff263d72),
                  padding: const EdgeInsets.symmetric(vertical: 17)),
            ),
          ],
        ),
      );

  Widget _sectionCard({
    required List<List<dynamic>> icon,
    required String title,
    required String subtitle,
    required Widget child,
  }) =>
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: const Color(0xff304b85).withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(12)),
              child: HugeIcon(
                  icon: icon, size: 18, color: const Color(0xff304b85)),
            ),
            const SizedBox(width: 10),
            Text(title,
                style: const TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff1d2b45))),
          ]),
          const SizedBox(height: 6),
          Text(subtitle,
              style: const TextStyle(
                  fontSize: 12.5, color: Color(0xff758097), height: 1.35)),
          const SizedBox(height: 14),
          child,
        ]),
      );
}
