import 'dart:async';
import 'dart:convert';

import 'package:background_sms/background_sms.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;

class SmsGatewayJob {
  const SmsGatewayJob(
      {required this.id, required this.recipientPhone, required this.smsText});
  final String id;
  final String recipientPhone;
  final String smsText;
  factory SmsGatewayJob.fromJson(Map<String, dynamic> json) => SmsGatewayJob(
        id: json['id'] as String,
        recipientPhone: json['recipientPhone'] as String,
        smsText: json['smsText'] as String,
      );
}

class GatewaySendEvent {
  const GatewaySendEvent({
    required this.jobId,
    required this.status,
    required this.phone,
    required this.otp,
  });

  final String jobId;
  final String status;
  final String phone;
  final String? otp;
}

class PendingGatewayResult {
  const PendingGatewayResult(
      {required this.jobId,
      required this.leaseId,
      required this.status,
      this.errorCode});
  final String jobId;
  final String leaseId;
  final String status;
  final String? errorCode;
  Map<String, dynamic> toJson() => {
        'jobId': jobId,
        'leaseId': leaseId,
        'status': status,
        if (errorCode != null) 'errorCode': errorCode,
      };
  factory PendingGatewayResult.fromJson(Map<String, dynamic> json) =>
      PendingGatewayResult(
        jobId: json['jobId'] as String,
        leaseId: json['leaseId'] as String,
        status: json['status'] as String,
        errorCode: json['errorCode'] as String?,
      );
}

/// The token and an unacknowledged result stay out of ordinary preferences.
class GatewaySecretStore {
  const GatewaySecretStore();
  static const _storage = FlutterSecureStorage();
  static const tokenKey = 'aykitap_gateway_token';
  static const pendingResultKey = 'aykitap_pending_result';
  Future<String?> readToken() => _storage.read(key: tokenKey);
  Future<void> writeToken(String token) =>
      _storage.write(key: tokenKey, value: token);
  Future<PendingGatewayResult?> readPendingResult() async {
    final raw = await _storage.read(key: pendingResultKey);
    return raw == null
        ? null
        : PendingGatewayResult.fromJson(
            jsonDecode(raw) as Map<String, dynamic>);
  }

  Future<void> writePendingResult(PendingGatewayResult result) =>
      _storage.write(key: pendingResultKey, value: jsonEncode(result.toJson()));
  Future<void> clearPendingResult() => _storage.delete(key: pendingResultKey);
}

class GatewayException implements Exception {
  const GatewayException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  bool get tokenRejected => statusCode == 401;
  @override
  String toString() => message;
}

/// Aykitap internal OTP SMS API. Never logs a token or message body.
class SmsGatewayService {
  SmsGatewayService(
      {http.Client? client,
      GatewaySecretStore? secrets,
      String? baseUrl,
      String? testToken})
      : _client = client ?? http.Client(),
        _secrets = secrets ?? const GatewaySecretStore(),
        _baseUrlOverride = baseUrl,
        _testToken = testToken;

  static const apiBaseUrlKey = 'apiBaseUrl';
  static const tokenConfiguredKey = 'gatewayTokenConfigured';
  static const tokenRejectedKey = 'gatewayTokenRejected';
  static const subscriptionIdKey = 'gatewaySubscriptionId';
  static const defaultApiBaseUrl =
      'https://aykitap.com.tm/api/v1/internal/otp-sms';

  static String effectiveApiBaseUrl(String? savedUrl) {
    final url = (savedUrl ?? '').trim().replaceAll(RegExp(r'/+$'), '');
    if (url.isEmpty ||
        url.contains('/internal/sms-gateway') ||
        url.contains('a7-tagam.com.tm')) {
      return defaultApiBaseUrl;
    }
    return url;
  }

  final http.Client _client;
  final GatewaySecretStore _secrets;
  final String? _baseUrlOverride;
  final String? _testToken;
  final GetStorage _settings = GetStorage();
  String get apiBaseUrl =>
      _baseUrlOverride ??
      effectiveApiBaseUrl(_settings.read<String>(apiBaseUrlKey));
  bool get isConfigured => _settings.read<bool>(tokenConfiguredKey) == true;
  int? get subscriptionId => _settings.read<int>(subscriptionIdKey);

  Future<Map<String, String>> _headers() async {
    final token = _testToken ?? await _secrets.readToken();
    if (token == null || token.trim().isEmpty) {
      throw const GatewayException('Cihaz tokenı ayarlanmamış.',
          statusCode: 401);
    }
    return {'Accept': 'application/json', 'Authorization': 'Bearer $token'};
  }

  Future<http.Response> _request(String method, String path,
      {Map<String, dynamic>? body}) async {
    final uri = Uri.parse('$apiBaseUrl$path');
    if (uri.scheme != 'https') {
      throw const GatewayException('Gateway için HTTPS adresi gerekli.');
    }
    final headers = await _headers();
    final response = await (method == 'GET'
            ? _client.get(uri, headers: headers)
            : _client.post(uri,
                headers: {
                  ...headers,
                  if (body != null) 'Content-Type': 'application/json'
                },
                body: body == null ? null : jsonEncode(body)))
        .timeout(const Duration(seconds: 12));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw GatewayException(_error(response), statusCode: response.statusCode);
    }
    return response;
  }

  dynamic _data(http.Response response) {
    final payload = jsonDecode(utf8.decode(response.bodyBytes));
    if (payload is! Map || !payload.containsKey('data')) {
      throw const GatewayException('Sunucu yanıtında data alanı yok.');
    }
    return payload['data'];
  }

  String _error(http.Response response) {
    try {
      final payload = jsonDecode(utf8.decode(response.bodyBytes));
      final message = payload is Map ? payload['message'] : null;
      if (message is List) return message.join(', ');
      if (message is String) return message;
    } catch (_) {}
    return 'HTTP ${response.statusCode}';
  }

  Future<List<SmsGatewayJob>> jobs() async {
    final data = _data(await _request('GET', '/jobs')) as List;
    return data
        .map((item) => SmsGatewayJob.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<String> claim(String jobId) async {
    final data = _data(
            await _request('POST', '/jobs/${Uri.encodeComponent(jobId)}/claim'))
        as Map<String, dynamic>;
    return data['leaseId'] as String;
  }

  Future<void> report(PendingGatewayResult result) async {
    _data(await _request(
        'POST', '/jobs/${Uri.encodeComponent(result.jobId)}/result',
        body: {
          'leaseId': result.leaseId,
          'status': result.status,
          if (result.errorCode != null) 'errorCode': result.errorCode,
        }));
  }

  Future<void> heartbeat() async =>
      _data(await _request('POST', '/gateway/heartbeat'));

  /// Retry only the report after a lost response. The SMS is never resent.
  Future<void> flushPendingResult() async {
    final pending = await _secrets.readPendingResult();
    if (pending == null) return;
    try {
      await report(pending);
    } on GatewayException catch (error) {
      if (error.statusCode != 409 && error.statusCode != 404) rethrow;
    }
    await _secrets.clearPendingResult();
  }

  /// Claim, send, report: strictly one job at a time.
  Future<void> processJobs(
      FutureOr<void> Function(GatewaySendEvent event) onResult) async {
    await flushPendingResult();
    for (final job in await jobs()) {
      String leaseId;
      try {
        leaseId = await claim(job.id);
      } on GatewayException catch (error) {
        if ({404, 409, 410}.contains(error.statusCode)) continue;
        rethrow;
      }
      SmsSendResult sent;
      try {
        final subId = subscriptionId;
        sent = subId == null
            ? const SmsSendResult.failed('NO_SIM')
            : await BackgroundSms.sendMessageDetailed(
                phoneNumber: job.recipientPhone,
                message: job.smsText,
                subscriptionId: subId);
      } catch (_) {
        sent = const SmsSendResult.failed('SEND_FAILED');
      }
      final pending = PendingGatewayResult(
        jobId: job.id,
        leaseId: leaseId,
        status: sent.accepted ? 'submitted' : 'failed',
        errorCode: sent.accepted ? null : sent.errorCode,
      );
      await _secrets.writePendingResult(pending);
      await onResult(GatewaySendEvent(
        jobId: job.id,
        status: sent.accepted ? 'sent' : 'failed',
        phone: job.recipientPhone,
        otp: RegExp(r'^CODE:([0-9]+)$').firstMatch(job.smsText)?.group(1),
      ));
      await flushPendingResult();
    }
  }

  void dispose() => _client.close();
}
