import 'dart:convert';

import 'package:background_sms/background_sms.dart';
import 'package:get/get.dart';
import 'package:http/http.dart' as http;
import 'package:sms_otp/app/constants/constants.dart';
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
    return GetOTPMessageModel(phone: json['phone'], otp: json['otp']);
  }
}

class OtpMessageSendService {
  HomeController homeController = Get.put(HomeController());

  Future<List<GetOTPMessageModel>> getMessages() async {
    final List<GetOTPMessageModel> messageList = [];
    try {
      final response = await http.get(
        Uri.parse('$serverURL/mobile/sms/'),
        headers: <String, String>{
          'Content-Type': 'application/json; charset=UTF-8',
        },
      );
      if (response.statusCode == 200) {
        final responseJson = json.decode(utf8.decode(response.bodyBytes));
        for (final Map<String, dynamic> product in responseJson) {
          messageList.add(GetOTPMessageModel.fromJson(product));
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
      homeController.addData(phone: message.phone!, message: message.otp!, status: 'notSend');
      String phoneNumber = message.phone!;
      if (!phoneNumber.startsWith('+')) {
        phoneNumber = '+993$phoneNumber';
      }

      try {
        SmsStatus result = await BackgroundSms.sendMessage(phoneNumber: phoneNumber, message: "${message.otp!} - Atelýam OTP koduňyz");
        if (result == SmsStatus.sent) {
          await sendData(phone: message.phone!, otp: message.otp!);
        } else {
          homeController.changeStatus(status: 'failed', message: message.otp!);
          await FCMConfig().sendNotification(body: "Failed to send SMS to $phoneNumber with result: $result", title: "SMS GIDENOK");
        }
      } catch (e) {
        homeController.changeStatus(status: 'failed', message: message.otp!);
        await FCMConfig().sendNotification(body: "Error sending SMS to $phoneNumber: $e", title: "SMS GIDENOK");
      }
    }
  }

  Future<bool> sendData({required String phone, required String otp}) async {
    try {
      var request = http.MultipartRequest('POST', Uri.parse('$serverURL/mobile/sms/'));
      request.fields.addAll({'phone': phone});

      http.StreamedResponse response = await request.send();
      if (response.statusCode == 200) {
        homeController.changeStatus(status: 'send', message: otp);
      } else {
        await FCMConfig().sendNotification(body: "Failed to send data to $phone with reason: ${response.reasonPhrase}", title: "Error: ${response.statusCode}");
      }
      return response.statusCode == 200;
    } catch (e) {
      await FCMConfig().sendNotification(body: "Error sending data to $phone: $e", title: "Error");
      return false;
    }
  }
}
