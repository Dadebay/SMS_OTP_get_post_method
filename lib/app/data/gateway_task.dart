import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:get_storage/get_storage.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';

@pragma('vm:entry-point')
void startGatewayTask() {
  FlutterForegroundTask.setTaskHandler(GatewayTaskHandler());
}

void initializeGatewayTask(int pollSeconds) {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'aykitap_otp_gateway',
      channelName: 'Aykitap OTP Gateway',
      channelDescription:
          'OTP SMS kuyruğunu denetler ve gönderimleri bildirir.',
      onlyAlertOnce: true,
    ),
    iosNotificationOptions:
        const IOSNotificationOptions(showNotification: false, playSound: false),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.repeat(pollSeconds * 1000),
      autoRunOnBoot: false,
      autoRunOnMyPackageReplaced: false,
      allowWakeLock: true,
      allowWifiLock: true,
    ),
  );
}

class GatewayTaskHandler extends TaskHandler {
  static const eventsKey = 'gateway_event_history';
  SmsGatewayService? _gateway;
  bool _busy = false;
  int _backoffSeconds = 0;
  DateTime? _nextTry;
  DateTime? _lastContact;

  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    WidgetsFlutterBinding.ensureInitialized();
    await GetStorage.init();
    _gateway = SmsGatewayService();
    await _tick();
  }

  @override
  void onRepeatEvent(DateTime timestamp) => unawaited(_tick());

  @override
  void onReceiveData(Object data) {
    if (data == 'poll') unawaited(_tick(force: true));
  }

  Future<void> _tick({bool force = false}) async {
    if (_busy || _gateway == null) return;
    _busy = true;
    try {
      final now = DateTime.now();
      if (!force && _nextTry != null && now.isBefore(_nextTry!)) {
        if (_lastContact == null ||
            now.difference(_lastContact!).inSeconds >= 60) {
          await _gateway!.heartbeat();
          _lastContact = DateTime.now();
        }
        return;
      }
      await _gateway!.processJobs((result) async {
        final time = DateTime.now().toLocal().toString().substring(0, 19);
        final eventId =
            '${result.jobId}:${DateTime.now().microsecondsSinceEpoch}';
        final event = <String, String>{
          'eventId': eventId,
          'jobId': result.jobId,
          'status': result.status,
          'time': time,
          'phone': result.phone,
          if (result.otp != null) 'otp': result.otp!,
        };
        final raw = await FlutterForegroundTask.getData<String>(key: eventsKey);
        final saved =
            raw == null ? <dynamic>[] : jsonDecode(raw) as List<dynamic>;
        final events = <Map<String, String>>[
          event,
          for (final entry in saved) Map<String, String>.from(entry as Map),
        ].take(200).toList();
        await FlutterForegroundTask.saveData(
            key: eventsKey, value: jsonEncode(events));
        FlutterForegroundTask.sendDataToMain({
          'type': 'event',
          ...event,
        });
      });
      _lastContact = DateTime.now();
      _backoffSeconds = 0;
      _nextTry = null;
      FlutterForegroundTask.sendDataToMain(
          {'type': 'state', 'value': 'Çevrimiçi — SMS bekleniyor'});
    } on GatewayException catch (error) {
      if (error.tokenRejected) {
        await GetStorage().write(SmsGatewayService.tokenRejectedKey, true);
        FlutterForegroundTask.sendDataToMain({
          'type': 'stopped',
          'value': 'Cihaz tokenı geçersiz veya iptal edilmiş.',
        });
        await FlutterForegroundTask.stopService();
        return;
      }
      if (error.statusCode != null &&
          error.statusCode! >= 400 &&
          error.statusCode! < 500 &&
          error.statusCode != 429) {
        FlutterForegroundTask.sendDataToMain({
          'type': 'stopped',
          'value': 'Gateway API hatası: ${error.message}',
        });
        await FlutterForegroundTask.stopService();
        return;
      }
      if (error.statusCode == null ||
          error.statusCode! >= 500 ||
          error.statusCode == 429) {
        _backoffSeconds =
            _backoffSeconds == 0 ? 2 : (_backoffSeconds * 2).clamp(2, 30);
        _nextTry = DateTime.now().add(Duration(seconds: _backoffSeconds));
      }
      FlutterForegroundTask.sendDataToMain(
          {'type': 'state', 'value': error.message});
    } catch (_) {
      _backoffSeconds =
          _backoffSeconds == 0 ? 2 : (_backoffSeconds * 2).clamp(2, 30);
      _nextTry = DateTime.now().add(Duration(seconds: _backoffSeconds));
      FlutterForegroundTask.sendDataToMain(
          {'type': 'state', 'value': 'Bağlantı hatası'});
    } finally {
      _busy = false;
    }
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {
    _gateway?.dispose();
    _gateway = null;
  }
}
