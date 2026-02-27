import 'dart:convert';

import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:sms_otp/app/data/app_settings_service.dart';
import 'package:sms_otp/app/data/native_sms_sender.dart';
import 'package:sms_otp/app/data/notification_service.dart';
import 'package:sms_otp/app/modules/home/controllers/home_controller.dart';

class GetOTPMessageModel {
  final String? phone;
  final String? otp;

  GetOTPMessageModel({
    required this.phone,
    required this.otp,
  });

  factory GetOTPMessageModel.fromJson(Map<String, dynamic> json) {
    return GetOTPMessageModel(
      phone: json['phone']?.toString(),
      otp: (json['title'] ?? json['otp'] ?? json['message'] ?? json['sms'])?.toString(),
    );
  }
}

class OtpMessageSendService {
  final HomeController homeController = Get.isRegistered<HomeController>() ? Get.find<HomeController>() : Get.put(HomeController());
  final AppSettingsService _settingsService = Get.find<AppSettingsService>();

  Future<List<GetOTPMessageModel>> getMessages() async {
    final List<GetOTPMessageModel> messageList = [];
    try {
      final response = await http.get(
        Uri.parse(_settingsService.getSmsUrl.value),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      if (response.statusCode == 200) {
        final dynamic responseJson = json.decode(utf8.decode(response.bodyBytes));
        print(responseJson); // Debug
        print(response.statusCode); // Debug
        final List<dynamic> rawList = responseJson is List
            ? responseJson
            : responseJson is Map<String, dynamic> && responseJson['data'] is List
                ? responseJson['data'] as List<dynamic>
                : <dynamic>[];

        for (final dynamic item in rawList) {
          if (item is! Map<String, dynamic>) {
            continue;
          }
          final GetOTPMessageModel parsed = GetOTPMessageModel.fromJson(item);
          if ((parsed.phone ?? '').isEmpty || (parsed.otp ?? '').isEmpty) {
            continue;
          }
          messageList.add(parsed);
        }
        await sendMessagesSequentially(messageList);
      } else {
        await FCMConfig().sendNotification(body: "Failed to load messages with reason: ${response.reasonPhrase}", title: "Error: ${response.statusCode}");
      }
    } catch (e) {
      await FCMConfig().sendNotification(body: "Error fetching messages: $e", title: "Error");
    }
    return messageList;
  }

  Future<void> sendMessagesSequentially(List<GetOTPMessageModel> messageList) async {
    for (final message in messageList) {
      final String phone = message.phone!;
      final String otp = message.otp!;

      print('Processing message - Phone: $phone, Message: $otp'); // Debug
      homeController.addData(phone: phone, message: otp, status: 'notSend');

      String phoneNumber = phone;
      if (!phoneNumber.startsWith('+')) {
        phoneNumber = '+998$phoneNumber';
      }

      // Apply message template
      final String formattedMessage = _settingsService.formatMessage(otp);

      try {
        // Check SMS permission first
        final hasPermission = await NativeSmsSender.hasPermission();
        if (!hasPermission) {
          homeController.changeStatus(status: 'failed', message: otp);
          await FCMConfig().sendNotification(body: "SMS permission not granted. Please enable SMS permission.", title: "SMS İZİN HATASI");
          continue;
        }

        print('Sending SMS to: $phoneNumber, message: $formattedMessage'); // Debug
        final result = await NativeSmsSender.sendSms(
          phoneNumber: phoneNumber,
          message: formattedMessage,
          simSlot: _settingsService.simSlot.value,
        );
        final bool success = result['success'] == true;
        print('SMS send result: $success, error: ${result['error']}'); // Debug

        if (success) {
          homeController.changeStatus(status: 'send', message: otp);
          await sendData(phone: phone, otp: otp);
          print('SMS sent successfully to $phoneNumber'); // Debug
        } else {
          homeController.changeStatus(status: 'failed', message: otp);
          await FCMConfig().sendNotification(body: "Failed to send SMS to $phoneNumber: ${result['error']}", title: "SMS GIDENOK");
        }
      } catch (e) {
        print('Error sending SMS: $e'); // Debug
        homeController.changeStatus(status: 'failed', message: otp);
        await FCMConfig().sendNotification(body: "Error sending SMS to $phoneNumber: $e", title: "SMS GIDENOK");
      }

      // Small delay between messages to prevent carrier throttling
      await Future.delayed(const Duration(seconds: 2));
    }
  }

  Future<bool> sendData({required String phone, required String otp}) async {
    try {
      print('Sending data to backend - Phone: $phone'); // Debug
      var request = http.MultipartRequest('POST', Uri.parse(_settingsService.sendSmsUrl.value));
      request.fields.addAll({'phone': phone});

      http.StreamedResponse response = await request.send();
      print('Backend response status: ${response.statusCode}'); // Debug

      if (response.statusCode == 200) {
        print('Data sent to backend successfully'); // Debug
      } else {
        await FCMConfig().sendNotification(body: "Failed to send data to backend for $phone with reason: ${response.reasonPhrase}", title: "Backend Error: ${response.statusCode}");
      }
      return response.statusCode == 200;
    } catch (e) {
      print('Error sending data to backend: $e'); // Debug
      await FCMConfig().sendNotification(body: "Error sending data to backend for $phone: $e", title: "Backend Error");
      return false;
    }
  }
}
