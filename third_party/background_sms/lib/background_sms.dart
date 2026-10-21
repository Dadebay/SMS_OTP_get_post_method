import 'dart:async';

import 'package:flutter/services.dart';

enum SmsStatus { sent, failed }

class SmsSendResult {
  const SmsSendResult.accepted()
      : accepted = true,
        errorCode = null;
  const SmsSendResult.failed(this.errorCode) : accepted = false;
  final bool accepted;
  final String? errorCode;
}

class SmsSubscription {
  const SmsSubscription(this.id, this.slot, this.name);
  final int id;
  final int slot;
  final String name;
}

class BackgroundSms {
  static const MethodChannel _channel = MethodChannel('background_sms');

  static Future<SmsStatus> sendMessage({required String phoneNumber, required String message, int? simSlot}) async {
    try {
      String? result = await _channel.invokeMethod('sendSms', <String, dynamic>{"phone": phoneNumber, "msg": message, "simSlot": simSlot});
      return result == "Sent" ? SmsStatus.sent : SmsStatus.failed;
    } on PlatformException {
      return SmsStatus.failed;
    }
  }

  static Future<List<SmsSubscription>> getSubscriptions() async {
    final raw = await _channel.invokeListMethod<Map<dynamic, dynamic>>('getSubscriptions');
    return [
      for (final item in raw ?? const <Map<dynamic, dynamic>>[]) SmsSubscription(item['id'] as int, item['slot'] as int, item['name'] as String),
    ];
  }

  static Future<SmsSendResult> sendMessageDetailed({required String phoneNumber, required String message, required int subscriptionId}) async {
    try {
      await _channel.invokeMethod<void>('sendSmsDetailed', {
        'phone': phoneNumber,
        'msg': message,
        'subscriptionId': subscriptionId,
      });
      return const SmsSendResult.accepted();
    } on PlatformException catch (error) {
      return SmsSendResult.failed(error.code);
    }
  }

  static Future<bool?> get isSupportCustomSim async {
    try {
      return await _channel.invokeMethod('isSupportMultiSim');
    } on PlatformException {
      return true;
    }
  }
}
