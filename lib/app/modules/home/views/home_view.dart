import 'dart:async';

import 'package:background_sms/background_sms.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/data/app_settings_service.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';
import 'package:sms_otp/app/data/notification_service.dart';
import 'package:sms_otp/app/modules/home/controllers/home_controller.dart';
import 'package:sms_otp/app/modules/settings/views/settings_view.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String? errorTitle;
  final HomeController homeController = Get.isRegistered<HomeController>() ? Get.find<HomeController>() : Get.put(HomeController());
  late final AppSettingsService settingsService;
  Timer? _timer;
  int _interval = AppSettingsService.defaultFetchIntervalSeconds;
  Worker? _intervalWorker;

  @override
  void initState() {
    super.initState();
    settingsService = Get.find<AppSettingsService>();
    _interval = settingsService.fetchIntervalSeconds.value;
    WakelockPlus.enable();
    getPermission();
    fetchMessagesPeriodically();

    _intervalWorker = ever<int>(settingsService.fetchIntervalSeconds, (int newValue) {
      if (!mounted) {
        return;
      }
      setState(() {
        _interval = newValue;
      });
      fetchMessagesPeriodically();
    });
  }

  void fetchMessagesPeriodically() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _interval), (timer) async {
      try {
        await OtpMessageSendService().getMessages();
      } catch (e) {
        await FCMConfig().sendNotification(body: "Error fetching messages periodically: $e", title: "Periodic Fetch Error");
      }
    });
  }

  @override
  void dispose() {
    WakelockPlus.disable();
    _timer?.cancel();
    _intervalWorker?.dispose();
    super.dispose();
  }

  Future<void> getPermission() async {
    try {
      await [Permission.sms].request();
    } catch (e) {
      await FCMConfig().sendNotification(body: "Error requesting SMS permission: $e", title: "Permission Error");
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isDarkMode = Theme.of(context).brightness == Brightness.dark;
    final Color timerDropdownBackground = isDarkMode ? Colors.grey.shade900 : Colors.white;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text(
          "SMS sending app",
          style: TextStyle(color: Colors.white, fontFamily: 'GilroySemiBold', fontSize: 20),
        ),
        elevation: 1,
        actions: [
          IconButton(
            onPressed: () async {
              try {
                await OtpMessageSendService().getMessages();
              } catch (e) {
                await FCMConfig().sendNotification(body: "Error fetching messages: $e", title: "Fetch Error");
              }
            },
            icon: const Icon(
              Icons.refresh,
              color: Colors.white,
            ),
          ),
          IconButton(
            onPressed: () async {
              await Get.to(() => const SettingsView());
            },
            icon: const Icon(
              Icons.settings,
              color: Colors.white,
            ),
          ),
          Theme(
            data: Theme.of(context).copyWith(
              canvasColor: timerDropdownBackground,
              highlightColor: Colors.transparent,
              splashColor: Colors.transparent,
              hoverColor: Colors.transparent,
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _interval,
                dropdownColor: Colors.black,
                iconDisabledColor: Colors.brown,
                focusColor: Colors.transparent,
                // iconEnabledColor: Colors.red,
                style: TextStyle(color: Colors.white, fontFamily: gilroyBold),
                items: <int>[15, 30, 45, 60, 120].map((int value) {
                  return DropdownMenuItem<int>(
                    value: value,
                    child: Text(
                      '$value sec',
                      style: TextStyle(color: Colors.white, fontFamily: gilroyBold),
                    ),
                  );
                }).toList(),
                onChanged: (newValue) async {
                  if (newValue == null) {
                    return;
                  }
                  await settingsService.updateFetchInterval(newValue);
                },
              ),
            ),
          ),
        ],
      ),
      body: Obx(() {
        return ListView.separated(
          itemCount: homeController.data.length,
          itemBuilder: (BuildContext context, int index) {
            final message = homeController.data[index];

            // SMS gönderme fonksiyonu
            Future<void> sendSmsToContact() async {
              String phoneNumber = message['phone'];
              if (!phoneNumber.startsWith('+')) {
                phoneNumber = '+993$phoneNumber';
              }

              try {
                print('Sending SMS to: $phoneNumber, message: ${message['message']}'); // Debug
                SmsStatus result = await BackgroundSms.sendMessage(phoneNumber: phoneNumber, message: message['message']);
                print('SMS send result: $result'); // Debug

                if (result == SmsStatus.sent) {
                  homeController.changeStatus(status: 'send', message: message['message']);
                  await OtpMessageSendService().sendData(phone: message['phone'], otp: message['message']);
                  print('SMS sent successfully to $phoneNumber'); // Debug
                } else {
                  homeController.changeStatus(status: 'failed', message: message['message']);
                  await FCMConfig().sendNotification(body: "Failed to send SMS to $phoneNumber with result: $result", title: "SMS GIDENOK");
                }
              } catch (e) {
                homeController.changeStatus(status: 'failed', message: message['message']);
                await FCMConfig().sendNotification(body: "Error sending SMS to $phoneNumber: $e", title: "SMS GIDENOK");
              }
            }

            return GestureDetector(
              onTap: sendSmsToContact,
              child: Container(
                color: Colors.black,
                padding: const EdgeInsets.all(8.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          "Phone: ${message['phone']}",
                          style: const TextStyle(color: Colors.white, fontFamily: 'GilroySemiBold', fontSize: 16),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            color: message['status'] == 'send'
                                ? Colors.green
                                : message['status'] == 'failed'
                                    ? Colors.red
                                    : Colors.grey,
                          ),
                          child: Text(
                            "Status: ${message['status']}",
                            style: const TextStyle(color: Colors.white, fontFamily: gilroyBold, fontSize: 14),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Message: ${message['message']}",
                      style: const TextStyle(color: Colors.white, fontFamily: 'GilroyMedium', fontSize: 14),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Date: ${message['date'].toString().substring(0, 19)}",
                      style: const TextStyle(color: Colors.grey, fontFamily: 'GilroyRegular', fontSize: 12),
                    ),
                    if (message['status'] == 'failed')
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: ElevatedButton.icon(
                          onPressed: sendSmsToContact,
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Retry', style: TextStyle(fontFamily: gilroyBold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.orange,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            minimumSize: const Size(80, 32),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            );
          },
          separatorBuilder: (BuildContext context, int index) {
            return Divider(
              thickness: 1,
              color: Colors.grey.shade200,
            );
          },
        );
      }),
    );
  }
}
