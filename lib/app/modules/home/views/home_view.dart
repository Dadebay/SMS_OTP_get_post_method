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

/// Liste içinde bir gün ayracı. Kayıtlarla aynı builder'dan çizildiği için
/// tek bir sliver hâlâ yalnızca ekranda görüneni kuruyor.
class _DaySeparator {
  const _DaySeparator(this.key);
  final String key;
}

class _HomeViewState extends State<HomeView> with WidgetsBindingObserver {
  final controller = Get.put(HomeController());

  /// Gün özetinde yalnızca bugün/dün mü yoksa tüm günler mi görünecek.
  bool _showAllDays = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ScreenWakeService.instance.start();
    _requestSmsPermission();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      controller.syncEventsFromTask();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  Future<void> _requestSmsPermission() async {
    final sms = await Permission.sms.request();
    final phone = await Permission.phone.request();
    if ((!sms.isGranted || !phone.isGranted) && mounted) {
      showSnackBar(context, 'İzin gerekli', 'SMS ve telefon izinlerini verin.',
          Colors.red);
    } else if (controller.isConfigured) {
      await controller.start();
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
                      const SizedBox(height: 14),
                      Obx(_statusCard),
                      Obx(_quickStats),
                      Obx(_eventsHeader),
                      const SizedBox(height: 8),
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
                    final items = _groupByDay(visible);
                    return SliverList.builder(
                      itemCount: items.length,
                      itemBuilder: (_, index) {
                        final item = items[index];
                        return item is _DaySeparator
                            ? _daySeparator(item.key, first: index == 0)
                            : _eventCard(item as Map<String, String>);
                      },
                    );
                  }),
                ),
              ],
            ),
          ),
        ),
      );

  /// Kayıtlar zaten yeniden eskiye sıralı; gün değiştikçe araya bir ayraç
  /// koyuyoruz.
  List<Object> _groupByDay(List<Map<String, String>> events) {
    final items = <Object>[];
    String? current;
    for (final event in events) {
      final day = _dayOf(event);
      if (day != current) {
        current = day;
        items.add(_DaySeparator(day));
      }
      items.add(event);
    }
    return items;
  }

  static String _dayOf(Map<String, String> event) {
    final time = event['time'];
    if (time != null && time.length >= 10) return time.substring(0, 10);
    return HomeController.dayKey(DateTime.now());
  }

  static String _timeOf(Map<String, String> event) {
    final time = event['time'] ?? '';
    return time.length >= 19 ? time.substring(11) : time;
  }

  static String _dayLabel(String key) {
    final now = DateTime.now();
    if (key == HomeController.dayKey(now)) return 'Bugün';
    if (key == HomeController.dayKey(now.subtract(const Duration(days: 1)))) {
      return 'Dün';
    }
    final date = DateTime.parse(key);
    return '${date.day.toString().padLeft(2, '0')}.'
        '${date.month.toString().padLeft(2, '0')}.${date.year}';
  }

  Widget _header() => AnimatedSize(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeInOutCubic,
        alignment: Alignment.topLeft,
        child: Row(
          children: [
            Expanded(
              child: Obx(() {
                final online = controller.isPolling.value;
                return Text(online ? 'Gateway aktif' : 'SMS Gateway',
                    maxLines: online ? 1 : 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: online ? 20 : 28,
                        fontWeight: FontWeight.w800,
                        color: online
                            ? const Color(0xff157a50)
                            : const Color(0xff17233b)));
              }),
            ),
            _circleButton(HugeIcons.strokeRoundedRefresh, controller.poll),
            const SizedBox(width: 10),
            _circleButton(HugeIcons.strokeRoundedDatabase01,
                () => Get.to(() => const UsageView())),
            const SizedBox(width: 10),
            _circleButton(HugeIcons.strokeRoundedSettings02,
                () => Get.to(() => const SettingsView())),
          ],
        ),
      );

  Widget _eventsHeader() => Row(
        children: [
          const Expanded(
            child: Text('Son işlemler',
                style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: Color(0xff17233b))),
          ),
          if (controller.events.isNotEmpty)
            TextButton.icon(
              onPressed: _confirmClearEvents,
              icon: const HugeIcon(
                  icon: HugeIcons.strokeRoundedDelete02,
                  color: Color(0xffc04545),
                  size: 16),
              label: const Text('Tümünü temizle',
                  style: TextStyle(
                      color: Color(0xffc04545),
                      fontWeight: FontWeight.w700,
                      fontSize: 13)),
              style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8)),
            ),
        ],
      );

  void _confirmClearEvents() {
    Get.dialog(AlertDialog(
      title: const Text('Tüm işlemler silinsin mi?'),
      content: const Text(
          'Kaydedilen tüm SMS işlem geçmişi ve sayaçlar cihazdan kalıcı olarak silinecek.'),
      actions: [
        TextButton(onPressed: Get.back, child: const Text('Vazgeç')),
        TextButton(
          onPressed: () {
            controller.clearEvents();
            Get.back();
          },
          child: const Text('Sil',
              style: TextStyle(
                  color: Color(0xffc04545), fontWeight: FontWeight.w700)),
        ),
      ],
    ));
  }

  Widget _circleButton(List<List<dynamic>> icon, VoidCallback onTap) =>
      Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                  child: HugeIcon(icon: icon, color: const Color(0xff24304a)))),
        ),
      );

  Widget _statusCard() {
    final online = controller.isPolling.value;
    final configured = controller.isConfigured;
    final activeColor =
        online ? const Color(0xff75f0b2) : const Color(0xffffca83);
    return AnimatedSize(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeInOutCubic,
      child: Container(
        padding: EdgeInsets.all(online ? 16 : 22),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          gradient: const LinearGradient(
              colors: [Color(0xff202d51), Color(0xff35497c)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight),
          boxShadow: const [
            BoxShadow(
                color: Color(0x33203051), blurRadius: 22, offset: Offset(0, 12))
          ],
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!online) ...[
            Row(children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                    color: activeColor.withValues(alpha: .17),
                    borderRadius: BorderRadius.circular(13)),
                child: HugeIcon(
                    icon: online
                        ? HugeIcons.strokeRoundedWifiConnected03
                        : HugeIcons.strokeRoundedWifiOff01,
                    color: activeColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      configured ? 'Gateway durduruldu' : 'Bağlantı gerekli',
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.w800))),
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: activeColor, shape: BoxShape.circle)),
            ]),
            const SizedBox(height: 18),
          ],
          Text(controller.state.value,
              style: const TextStyle(
                  color: Color(0xffdbe5ff), fontSize: 15, height: 1.35)),
          SizedBox(height: online ? 12 : 22),
          FilledButton.icon(
            onPressed: configured
                ? (online ? controller.stop : controller.start)
                : () => Get.to(() => const SettingsView()),
            icon: HugeIcon(
                icon: configured
                    ? (online
                        ? HugeIcons.strokeRoundedPauseCircle
                        : HugeIcons.strokeRoundedPlay)
                    : HugeIcons.strokeRoundedSettings02,
                color: const Color(0xff263860),
                size: 20),
            label: Text(configured
                ? (online ? 'Gateway’i durdur' : 'Gateway’i başlat')
                : 'Bağlantıyı ayarla'),
            style: FilledButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: const Color(0xff263860),
                padding: EdgeInsets.symmetric(
                    horizontal: 18, vertical: online ? 11 : 14)),
          ),
        ]),
      ),
    );
  }

  /// Üstte iki küçük toplam kartı, altında gün gün dökümü.
  Widget _quickStats() {
    final sent = controller.sentCount.value;
    final failed = controller.failedCount.value;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(children: [
        Row(children: [
          Expanded(
              child: _statCard('$sent', 'Gönderildi',
                  HugeIcons.strokeRoundedSent, const Color(0xff157a50))),
          const SizedBox(width: 8),
          Expanded(
              child: _statCard('$failed', 'Başarısız',
                  HugeIcons.strokeRoundedAlertCircle, const Color(0xffc04545))),
        ]),
        const SizedBox(height: 8),
        _dailyCard(),
      ]),
    );
  }

  /// Gün bazlı döküm: varsayılan olarak bugün ve dün, istenirse tüm günler.
  Widget _dailyCard() {
    final breakdown = controller.dailyBreakdown;
    final todayKey = HomeController.dayKey(DateTime.now());
    // Bugun her zaman gorunur (0 olsa bile). Yanina sabit bir "dun" satiri
    // koymak yerine kaydi olan en yeni gunleri aliyoruz: eski gonderimler
    // bugun/dun disinda bir tarihteyse artik 0 degil gercek sayilariyla cikiyor.
    final rows = _showAllDays
        ? <DayStat>[
            if (!breakdown
                .any((day) => HomeController.dayKey(day.day) == todayKey))
              controller.statForKey(todayKey),
            ...breakdown,
          ]
        : <DayStat>[
            controller.statForKey(todayKey),
            ...breakdown
                .where((day) => HomeController.dayKey(day.day) != todayKey)
                .take(2),
          ];
    final shown = rows.map((day) => HomeController.dayKey(day.day)).toSet();
    final hasMore =
        breakdown.any((day) => !shown.contains(HomeController.dayKey(day.day)));
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const HugeIcon(
              icon: HugeIcons.strokeRoundedCalendar03,
              size: 15,
              color: Color(0xff758097)),
          const SizedBox(width: 6),
          const Expanded(
            child: Text('Günlük gönderim',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff758097))),
          ),
          if (hasMore)
            GestureDetector(
              onTap: () => setState(() => _showAllDays = !_showAllDays),
              child: Text(_showAllDays ? 'Daha az' : 'Tüm günler',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Color(0xff2f4880))),
            ),
        ]),
        const SizedBox(height: 4),
        for (final day in rows) _dayRow(day),
      ]),
    );
  }

  Widget _dayRow(DayStat day) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(children: [
          Expanded(
            child: Text(_dayLabel(HomeController.dayKey(day.day)),
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: Color(0xff283652))),
          ),
          Text('${day.sent}',
              style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: Color(0xff157a50))),
          const SizedBox(width: 3),
          const Text('gönderildi',
              style: TextStyle(fontSize: 11, color: Color(0xff758097))),
          if (day.failed > 0) ...[
            const SizedBox(width: 8),
            Text('${day.failed}',
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: Color(0xffc04545))),
            const SizedBox(width: 3),
            const Text('hata',
                style: TextStyle(fontSize: 11, color: Color(0xff758097))),
          ],
        ]),
      );

  /// Küçültülmüş toplam kartı: ikon ve sayı aynı satırda.
  Widget _statCard(
          String value, String label, List<List<dynamic>> icon, Color color) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Row(children: [
          HugeIcon(icon: icon, size: 17, color: color),
          const SizedBox(width: 9),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: Color(0xff1e2a44))),
              Text(label,
                  style:
                      const TextStyle(fontSize: 11, color: Color(0xff758097))),
            ]),
          ),
        ]),
      );

  Widget _emptyState() => Container(
        padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(22)),
        child: const Column(children: [
          HugeIcon(
              icon: HugeIcons.strokeRoundedBubbleChat,
              color: Color(0xff9aa6bd),
              size: 42),
          SizedBox(height: 12),
          Text('Henüz işlem yok',
              style: TextStyle(
                  fontWeight: FontWeight.w800, color: Color(0xff33415c))),
          SizedBox(height: 5),
          Text('Gateway başlatıldığında SMS işlemleri burada görünür.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Color(0xff758097))),
        ]),
      );

  /// Gün ayracı. Sayılar listeden değil kalıcı sayaçlardan geliyor: liste
  /// kırpılsa da o günün gerçek toplamı görünür.
  Widget _daySeparator(String key, {required bool first}) {
    final stat = controller.statForKey(key);
    return Padding(
      padding:
          EdgeInsets.only(top: first ? 0 : 12, bottom: 7, left: 2, right: 2),
      child: Row(children: [
        Text(_dayLabel(key),
            style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w800,
                color: Color(0xff33415c))),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
              color: const Color(0xffe4ebf7),
              borderRadius: BorderRadius.circular(9)),
          child: Text(
            '${stat.sent} gönderildi${stat.failed > 0 ? ' · ${stat.failed} hata' : ''}',
            style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Color(0xff44557c)),
          ),
        ),
        const Expanded(child: Divider(indent: 10, color: Color(0xffdfe5f0))),
      ]),
    );
  }

  Widget _eventCard(Map<String, String> event) {
    final failed = event['status'] == 'failed';
    final color = failed ? const Color(0xffc44545) : const Color(0xff148457);
    final icon = failed
        ? HugeIcons.strokeRoundedAlertCircle
        : HugeIcons.strokeRoundedMessage01;
    return Dismissible(
      key: ObjectKey(event),
      direction: DismissDirection.endToStart,
      onDismissed: (_) => controller.deleteEventRef(event),
      background: Container(
        alignment: Alignment.centerRight,
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 18),
        decoration: BoxDecoration(
            color: const Color(0xffc44545),
            borderRadius: BorderRadius.circular(14)),
        child: const HugeIcon(
            icon: HugeIcons.strokeRoundedDelete02,
            color: Colors.white,
            size: 20),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 7),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
            color: Colors.white, borderRadius: BorderRadius.circular(14)),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
                color: color.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10)),
            child: HugeIcon(icon: icon, color: color, size: 17),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(event['phone'] ?? event['jobId'] ?? 'Eski işlem',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Color(0xff283652))),
                if (event['otp'] case final otp?) ...[
                  const SizedBox(height: 3),
                  Text('OTP: $otp',
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: Color(0xff536078))),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(failed ? 'Hata' : 'Gönderildi',
                style: TextStyle(
                    fontSize: 12, fontWeight: FontWeight.w700, color: color)),
            const SizedBox(height: 3),
            Text(_timeOf(event),
                style: const TextStyle(fontSize: 11, color: Color(0xff8490a5))),
          ]),
        ]),
      ),
    );
  }
}
