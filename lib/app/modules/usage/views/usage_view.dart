import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:sms_otp/app/data/usage_service.dart';
import 'package:sms_otp/app/modules/usage/controllers/usage_controller.dart';

class UsageView extends StatefulWidget {
  const UsageView({super.key});

  @override
  State<UsageView> createState() => _UsageViewState();
}

class _UsageViewState extends State<UsageView> {
  final controller = Get.put(UsageController());

  @override
  void dispose() {
    Get.delete<UsageController>();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: const Color(0xfff5f7fb),
        appBar: AppBar(
          backgroundColor: const Color(0xfff5f7fb),
          surfaceTintColor: Colors.transparent,
          title: const Text('Veri kullanımı',
              style: TextStyle(
                  color: Color(0xff17233b), fontWeight: FontWeight.w800)),
          actions: [
            IconButton(
              onPressed: _confirmReset,
              tooltip: 'Sayacı sıfırla',
              icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedRefresh,
                  color: Color(0xff536078)),
            ),
          ],
        ),
        body: Obx(
          () => ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 32),
            children: [
              _totalCard(),
              const SizedBox(height: 16),
              _sinceBanner(),
              const SizedBox(height: 16),
              if (controller.isTrafficSupported) ...[
                _breakdown(),
                const SizedBox(height: 16),
                _dailyCard(),
              ] else
                _unsupportedBanner(),
            ],
          ),
        ),
      );

  /// Sayfanın ana çıktısı: bu uygulamanın taşıdığı toplam veri.
  Widget _totalCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
              colors: [Color(0xff202d51), Color(0xff35497c)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33203051),
                blurRadius: 22,
                offset: Offset(0, 12))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(9),
              decoration: BoxDecoration(
                  color: const Color(0xff75f0b2).withValues(alpha: .17),
                  borderRadius: BorderRadius.circular(13)),
              child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDatabase01,
                  color: Color(0xff75f0b2)),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text('Bu uygulamanın kullandığı veri',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w800)),
            ),
          ]),
          const SizedBox(height: 18),
          Text(
            controller.formatBytes(controller.totalBytes),
            style: const TextStyle(
                color: Colors.white, fontSize: 38, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Cihazın toplamı değil, yalnızca bu uygulamanın indirdiği ve '
            'gönderdiği veri.',
            style: TextStyle(
                color: Color(0xffdbe5ff), fontSize: 12.5, height: 1.35),
          ),
        ]),
      );

  Widget _breakdown() => Container(
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
              child: const HugeIcon(
                  icon: HugeIcons.strokeRoundedWifiConnected03,
                  size: 18,
                  color: Color(0xff304b85)),
            ),
            const SizedBox(width: 10),
            const Expanded(
              child: Text('Bağlantıya göre',
                  style: TextStyle(
                      fontSize: 16.5,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff1d2b45))),
            ),
          ]),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(
                child: _statCard(
                    controller.formatBytes(controller.mobileBytes.value),
                    'Mobil veri',
                    HugeIcons.strokeRoundedSignal,
                    const Color(0xffc07a45))),
            const SizedBox(width: 10),
            Expanded(
                child: _statCard(
                    controller.formatBytes(controller.wifiBytes.value),
                    'Wi-Fi',
                    HugeIcons.strokeRoundedWifi01,
                    const Color(0xff157a50))),
          ]),
        ]),
      );

  /// Gun gun kullanim. Toplam yukarida duruyor; buradaki cubuklar gunleri
  /// birbirine gore olcekliyor, cunku "12 MB" tek basina cok mu az mi belli
  /// degil — yanindaki gunlerle karsilastirilinca belli oluyor.
  Widget _dailyCard() {
    final days = controller.days;
    final busiest = controller.busiestDayBytes;

    return Container(
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
            child: const HugeIcon(
                icon: HugeIcons.strokeRoundedCalendar03,
                size: 18,
                color: Color(0xff304b85)),
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text('Günlük kullanım',
                style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff1d2b45))),
          ),
          if (days.isNotEmpty)
            Text('${days.length} gün',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff758097))),
        ]),
        const SizedBox(height: 6),
        if (days.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 14),
            child: Text(
                'Henüz kayıt yok. Uygulama veri taşıdıkça günler burada '
                'birikir.',
                style: TextStyle(
                    fontSize: 13, height: 1.35, color: Color(0xff758097))),
          )
        else
          for (final day in days) _dailyRow(day, busiest),
      ]),
    );
  }

  Widget _dailyRow(UsageDay day, int busiest) {
    // Sifira bolmeyi onler ve tek gun varken cubugu dolu gosterir.
    final ratio = busiest <= 0 ? 0.0 : day.bytes / busiest;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(controller.dayLabel(day.date),
                style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff1d2b45))),
          ),
          Text(controller.formatBytes(day.bytes),
              style: const TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                  color: Color(0xff304b85))),
        ]),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(99),
          child: LinearProgressIndicator(
            value: ratio.clamp(0.0, 1.0),
            minHeight: 6,
            backgroundColor: const Color(0xfff5f7fb),
            valueColor:
                const AlwaysStoppedAnimation<Color>(Color(0xff4c6bb3)),
          ),
        ),
      ]),
    );
  }

  Widget _sinceBanner() {
    final date = controller.since.value;
    final text = '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:'
        '${date.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
          color: const Color(0xff304b85).withValues(alpha: .08),
          borderRadius: BorderRadius.circular(18)),
      child: Row(children: [
        const HugeIcon(
            icon: HugeIcons.strokeRoundedTime01,
            size: 18,
            color: Color(0xff304b85)),
        const SizedBox(width: 10),
        Expanded(
          child: Text('$text tarihinden beri sayılıyor',
              style: const TextStyle(
                  color: Color(0xff304b85),
                  fontSize: 13,
                  fontWeight: FontWeight.w700)),
        ),
      ]),
    );
  }

  Widget _unsupportedBanner() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
            color: const Color(0xff9a7300).withValues(alpha: .08),
            borderRadius: BorderRadius.circular(18)),
        child: const Row(children: [
          HugeIcon(
              icon: HugeIcons.strokeRoundedAlertCircle,
              size: 18,
              color: Color(0xff9a7300)),
          SizedBox(width: 10),
          Expanded(
            child: Text(
                'Bu cihaz uygulama başına veri sayacını desteklemiyor.',
                style: TextStyle(
                    color: Color(0xff9a7300),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
          ),
        ]),
      );

  Widget _statCard(
          String value, String label, List<List<dynamic>> icon, Color color) =>
      Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
            color: const Color(0xfff5f7fb),
            borderRadius: BorderRadius.circular(18)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          HugeIcon(icon: icon, size: 19, color: color),
          const SizedBox(height: 10),
          Text(value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  color: Color(0xff1e2a44))),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(fontSize: 11, color: Color(0xff758097))),
        ]),
      );

  void _confirmReset() {
    Get.dialog(AlertDialog(
      title: const Text('Sayaç sıfırlansın mı?'),
      content: const Text(
          'Veri sayacı sıfırlanır ve sayım bugünden yeniden başlar.'),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Vazgeç')),
        TextButton(
          onPressed: () {
            controller.reset();
            Get.back();
          },
          child: const Text('Sıfırla',
              style: TextStyle(
                  color: Color(0xffc04545), fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }
}
