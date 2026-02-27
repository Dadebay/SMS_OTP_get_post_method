import 'package:flutter/services.dart';

/// Native SMS sender using Android's SmsManager via platform channel.
/// Supports dual SIM and provides detailed error reporting.
class NativeSmsSender {
  static const MethodChannel _channel = MethodChannel('com.example.sms_otp/sms');

  /// Send SMS using native Android SmsManager.
  /// [simSlot] - 0 for SIM 1, 1 for SIM 2. Defaults to 0.
  /// Returns a map with 'success' (bool) and 'error' (String) keys.
  static Future<Map<String, dynamic>> sendSms({
    required String phoneNumber,
    required String message,
    int simSlot = 0,
  }) async {
    try {
      final result = await _channel.invokeMethod('sendSms', {
        'phone': phoneNumber,
        'message': message,
        'simSlot': simSlot,
      });
      return {'success': result == 'sent', 'error': ''};
    } on PlatformException catch (e) {
      print('NativeSmsSender Error: ${e.code} - ${e.message}');
      return {'success': false, 'error': '${e.code}: ${e.message}'};
    } catch (e) {
      print('NativeSmsSender Unknown Error: $e');
      return {'success': false, 'error': e.toString()};
    }
  }

  /// Check if SMS permission is granted
  static Future<bool> hasPermission() async {
    try {
      final result = await _channel.invokeMethod('checkSmsPermission');
      return result == true;
    } catch (e) {
      print('NativeSmsSender Permission Check Error: $e');
      return false;
    }
  }

  /// Get available SIM cards info
  static Future<List<Map<String, dynamic>>> getSimCards() async {
    try {
      final result = await _channel.invokeMethod('getSimCards');
      if (result is List) {
        return result.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
      return [];
    } catch (e) {
      print('NativeSmsSender getSimCards Error: $e');
      return [];
    }
  }
}
