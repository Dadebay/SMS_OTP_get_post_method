import 'dart:async';

import 'package:background_sms/background_sms.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:sms_otp/app/constants/constants.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';
import 'package:sms_otp/app/data/notification_service.dart';
import 'package:sms_otp/app/modules/home/controllers/home_controller.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  String? errorTitle;
  final HomeController homeController = Get.put(HomeController());
  Timer? _timer;
  int _interval = 60;

  @override
  void initState() {
    super.initState();
    WakelockPlus.enable();
    getPermission();
    fetchMessagesPeriodically();
  }

  void fetchMessagesPeriodically() {
    _timer?.cancel();
    _timer = Timer.periodic(Duration(seconds: _interval), (timer) async {
      print("_____________________________________________________________________________________________");
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
    super.dispose();
  }

  Future<void> getPermission() async {
    try {
      await [Permission.sms].request();
    } catch (e) {
      await FCMConfig().sendNotification(body: "Error requesting SMS permission: $e", title: "Permission Error");
    }
  }

  Future<bool> _isPermissionGranted() async {
    try {
      return await Permission.sms.status.isGranted;
    } catch (e) {
      await FCMConfig().sendNotification(body: "Error checking SMS permission status: $e", title: "Permission Status Error");
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
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
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: _interval,
              items: <int>[30, 60, 120].map((int value) {
                return DropdownMenuItem<int>(
                  value: value,
                  child: Text(
                    '$value seconds',
                    style: TextStyle(color: value == _interval ? Colors.white : Colors.black, fontFamily: gilroyBold),
                  ),
                );
              }).toList(),
              onChanged: (newValue) {
                setState(() {
                  _interval = newValue!;
                  fetchMessagesPeriodically();
                });
              },
            ),
          ),
        ],
      ),
      body: Obx(() {
        return ListView.separated(
          itemCount: homeController.data.length,
          itemBuilder: (BuildContext context, int index) {
            final message = homeController.data[index];
            return GestureDetector(
              onTap: () async {
                String phoneNumber = message['phone'];
                if (!phoneNumber.startsWith('+')) {
                  phoneNumber = '+993$phoneNumber';
                }

                try {
                  SmsStatus result = await BackgroundSms.sendMessage(phoneNumber: phoneNumber, message: message['message']);
                  if (result == SmsStatus.sent) {
                    await OtpMessageSendService().sendData(phone: message['phone'], otp: message['message']);
                  } else {
                    homeController.changeStatus(status: 'failed', message: message['message']);
                    await FCMConfig().sendNotification(body: "Failed to send SMS to $phoneNumber with result: $result", title: "SMS GIDENOK");
                  }
                } catch (e) {
                  homeController.changeStatus(status: 'failed', message: message['message']);
                  await FCMConfig().sendNotification(body: "Error sending SMS to $phoneNumber: $e", title: "SMS GIDENOK");
                }
              },
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
                    Text(
                      "OTP: ${message['message']}",
                      style: const TextStyle(color: Colors.white, fontFamily: 'GilroyMedium', fontSize: 14),
                    ),
                    Text(
                      "Date: ${message['date'].toString().substring(0, 19)}", // Date yerine uygun bir alan ekleyin
                      style: const TextStyle(color: Colors.grey, fontFamily: 'GilroyRegular', fontSize: 14),
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
