import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:get_storage/get_storage.dart';
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
  late final HomeController home = Get.find<HomeController>();
  bool isTesting = false;

  bool get _isConfigured => url.text.trim().isNotEmpty;

  @override
  void initState() {
    super.initState();
    url.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    url.dispose();
    super.dispose();
  }

  Future<bool> _saveAddress() async {
    final baseUrl = url.text.trim().replaceAll(RegExp(r'/+$'), '');
    if (!baseUrl.startsWith('https://') && !baseUrl.startsWith('http://')) {
      showSnackBar(context, 'Geçersiz adres',
          'API adresi http:// veya https:// ile başlamalıdır.', Colors.red);
      return false;
    }
    await storage.write(SmsGatewayService.apiBaseUrlKey, baseUrl);
    return true;
  }

  Future<void> _testConnection() async {
    if (!await _saveAddress() || !mounted) return;
    setState(() => isTesting = true);
    final gateway = SmsGatewayService();
    try {
      await gateway.heartbeat();
      if (mounted) {
        showSnackBar(context, 'Bağlantı başarılı',
            'Gateway bağlantısı hazır.', const Color(0xff157a50));
      }
    } on GatewayException catch (error) {
      if (mounted) {
        showSnackBar(
            context, 'Bağlantı kurulamadı', error.message, Colors.red);
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
    home.stop();
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
            _connectionStatusBanner(),
            const SizedBox(height: 22),
            _sectionCard(
              icon: HugeIcons.strokeRoundedServerStack01,
              title: 'Backend bağlantısı',
              subtitle:
                  'SMS Gateway\'in görev almak için ulaşacağı yerel/uzak API adresi.',
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
                      hintText: 'https://a7-tagam.com.tm/api/v1',
                      border: InputBorder.none,
                    ),
                  ),
                ),
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

  /// Surfaces the current connection state up front, separate from the
  /// address input below, so it's clear at a glance whether the device is
  /// still in local/unconfigured mode.
  Widget _connectionStatusBanner() {
    final configured = _isConfigured;
    final color =
        configured ? const Color(0xff157a50) : const Color(0xff9a7300);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: color.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            configured
                ? 'Bağlantı yapılandırıldı'
                : 'Yerel mod — bağlantı henüz ayarlanmadı',
            style: TextStyle(
                color: color, fontSize: 13.5, fontWeight: FontWeight.w700),
          ),
        ),
      ]),
    );
  }

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
