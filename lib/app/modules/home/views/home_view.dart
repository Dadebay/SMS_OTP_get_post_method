import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/modules/home/controllers/home_controller.dart';
import 'package:sms_otp/app/data/screen_wake_service.dart';
import 'package:sms_otp/app/modules/settings/views/settings_view.dart';
import 'package:sms_otp/app/modules/usage/views/usage_view.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final controller = Get.put(HomeController());

  @override
  void initState() {
    super.initState();
    ScreenWakeService.instance.start();
    _requestSmsPermission();
  }

  Future<void> _requestSmsPermission() async {
    final status = await Permission.sms.request();
    if (!status.isGranted && mounted) {
      showSnackBar(context, 'SMS izni gerekli', 'SMS gönderebilmek için telefon ayarlarından izin verin.', Colors.red);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfff5f7fb),
        body: SafeArea(
          child: RefreshIndicator(
            onRefresh: controller.poll,
            // Her `Obx` yalnızca kendi bağlı olduğu değeri dinliyor: poll
            // döngüsü artık tüm sayfayı değil sadece ilgili küçük parçayı
            // yeniden çiziyor.
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  sliver: SliverList(
                    delegate: SliverChildListDelegate.fixed([
                      _header(),
                      Obx(_quickStats),
                      Obx(_eventsHeader),
                      const SizedBox(height: 10),
                    ]),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
                  sliver: Obx(() {
                    final visible = controller.events
                        .where((event) => event['status'] != 'idle')
                        .toList(growable: false);
                    if (visible.isEmpty) {
                      return SliverToBoxAdapter(child: _emptyState());
                    }
                    // `ListView(children: [...])` tüm kartları bir anda
                    // kuruyordu; builder yalnızca ekranda görüneni kurar.
                    return SliverList.builder(
                      itemCount: visible.length,
                      itemBuilder: (_, index) => _eventCard(visible[index]),
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      );

  Widget _header() => Row(
        children: [
          const Expanded(
            child: Text('SMS Gateway', style: TextStyle(fontSize: 28, fontWeight: FontWeight.w800, color: Color(0xff17233b))),
          ),
          _circleButton(HugeIcons.strokeRoundedRefresh, controller.poll),
          const SizedBox(width: 10),
          _circleButton(HugeIcons.strokeRoundedDatabase01, () => Get.to(() => const UsageView())),
          const SizedBox(width: 10),
          _circleButton(HugeIcons.strokeRoundedSettings02, () => Get.to(() => const SettingsView())),
        ],
      );

  Widget _eventsHeader() => Row(
        children: [
          const Expanded(
            child: Text('Son işlemler', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Color(0xff17233b))),
          ),
          if (controller.events.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClearEvents,
              icon: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: Color(0xffc04545), size: 16),
              label: const Text('Tümünü temizle', style: TextStyle(color: Color(0xffc04545), fontWeight: FontWeight.w700, fontSize: 13)),
              style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
        ],
      );

  void _confirmClearEvents() {
    Get.dialog(AlertDialog(
      title: const Text('Tüm işlemler silinsin mi?'),
      content: const Text('Kaydedilen tüm SMS işlem geçmişi cihazdan kalıcı olarak silinecek.'),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Vazgeç')),
        TextButton(
          onPressed: () {
            controller.clearEvents();
            Get.back();
          },
          child: const Text('Sil', style: TextStyle(color: Color(0xffc04545), fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  Widget _circleButton(List<List<dynamic>> icon, VoidCallback onTap) => Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(width: 48, height: 48, child: Center(child: HugeIcon(icon: icon, color: const Color(0xff24304a)))),
        ),
      );

  Widget _statusCard() {
    final online = controller.isPolling.value;
    final configured = controller.isConfigured;
    final activeColor = online ? const Color(0xff75f0b2) : const Color(0xffffca83);
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(28),
        gradient: const LinearGradient(colors: [Color(0xff202d51), Color(0xff35497c)], begin: Alignment.topLeft, end: Alignment.bottomRight),
        boxShadow: const [BoxShadow(color: Color(0x33203051), blurRadius: 22, offset: Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(color: activeColor.withValues(alpha: .17), borderRadius: BorderRadius.circular(13)),
            child: HugeIcon(icon: online ? HugeIcons.strokeRoundedWifiConnected03 : HugeIcons.strokeRoundedWifiOff01, color: activeColor),
          ),
          const SizedBox(width: 12),
          Expanded(child: Text(online ? 'Gateway aktif' : (configured ? 'Gateway durduruldu' : 'Yerel mod'), style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
          Container(width: 10, height: 10, decoration: BoxDecoration(color: activeColor, shape: BoxShape.circle)),
        ]),
        const SizedBox(height: 18),
        Text(controller.state.value, style: const TextStyle(color: Color(0xffdbe5ff), fontSize: 15, height: 1.35)),
        const SizedBox(height: 22),
        FilledButton.icon(
          onPressed: configured ? (online ? controller.stop : controller.start) : () => Get.to(() => const SettingsView()),
          icon: HugeIcon(icon: configured ? (online ? HugeIcons.strokeRoundedPauseCircle : HugeIcons.strokeRoundedPlay) : HugeIcons.strokeRoundedSettings02, color: const Color(0xff263860), size: 20),
          label: Text(configured ? (online ? 'Gateway’i durdur' : 'Gateway’i başlat') : 'Bağlantıyı ayarla'),
          style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: const Color(0xff263860), padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14)),
        ),
      ]),
    );
  }

  Widget _quickStats() {
    // Sayaçlar controller'da liste değiştikçe bir kez hesaplanıyor; burada her
    // çizimde listeyi baştan taramıyoruz.
    final sent = controller.sentCount.value;
    final failed = controller.failedCount.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(children: [
        Expanded(child: _statCard('$sent', 'Gönderildi', HugeIcons.strokeRoundedSent, const Color(0xff157a50))),
        const SizedBox(width: 10),
        Expanded(child: _statCard('$failed', 'Başarısız', HugeIcons.strokeRoundedAlertCircle, const Color(0xffc04545))),
      ]),
    );
  }

  Widget _statCard(String value, String label, List<List<dynamic>> icon, Color color, {bool compact = false}) => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HugeIcon(icon: icon, size: 19, color: color),
          const SizedBox(height: 10),
          Text(value, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(fontSize: compact ? 14 : 21, fontWeight: FontWeight.w800, color: const Color(0xff1e2a44))),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(fontSize: 11, color: Color(0xff758097))),
        ]),
      );

  Widget _emptyState() => Container(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: const Column(children: [
          HugeIcon(icon: HugeIcons.strokeRoundedBubbleChat, color: Color(0xff9aa6bd), size: 42),
          SizedBox(height: 12),
          Text('Henüz işlem yok', style: TextStyle(fontWeight: FontWeight.w800, color: Color(0xff33415c))),
          SizedBox(height: 5),
          Text('Gateway başlatıldığında SMS işlemleri burada görünür.', textAlign: TextAlign.center, style: TextStyle(color: Color(0xff758097))),
        ]),
      );

  Widget _eventCard(Map<String, String> event) {
    final failed = event['status'] == 'failed';
    final color = failed ? const Color(0xffc44545) : const Color(0xff148457);
    final icon = failed ? HugeIcons.strokeRoundedAlertCircle : HugeIcons.strokeRoundedMessage01;
    final otp = event['otp'] ?? '';
    return Dismissible(
      key: ObjectKey(event),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => controller.deleteEventRef(event),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(color: const Color(0xffc44545), borderRadius: BorderRadius.circular(18)),
        child: const HugeIcon(icon: HugeIcons.strokeRoundedDelete02, color: Colors.white),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
        child: Row(children: [
          Container(
              padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: color.withValues(alpha: .12), borderRadius: BorderRadius.circular(13)), child: HugeIcon(icon: icon, color: color)),
          const SizedBox(width: 12),
          Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(event['phone'] ?? '', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xff283652))),
            const SizedBox(height: 4),
            Text(otp.isEmpty ? '—' : 'OTP: $otp', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: color)),
          ])),
          Text(event['time'] ?? '', style: const TextStyle(fontSize: 12, color: Color(0xff8490a5))),
        ]),
      ),
    );
  }
}
