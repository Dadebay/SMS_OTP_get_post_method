import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:background_sms/background_sms.dart';
import 'package:flutter/foundation.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';

class SmsGatewayJob {
  const SmsGatewayJob({
    required this.id,
    required this.phone,
    required this.message,
    required this.expiresAt,
    required this.receipt,
  });

  final String id;
  final String phone;
  final String message;
  final DateTime expiresAt;
  final String receipt;

  factory SmsGatewayJob.fromJson(Map<String, dynamic> json) => SmsGatewayJob(
        id: json['id'] as String,
        phone: json['phone'] as String,
        message: json['message'] as String,
        expiresAt: DateTime.parse(json['expiresAt'] as String).toLocal(),
        receipt: json['receipt'] as String,
      );
}

class SmsGatewayService {
  SmsGatewayService({http.Client? client}) : _client = client ?? _createClient();

  static const apiBaseUrlKey = 'apiBaseUrl';
  static const defaultApiBaseUrl = 'https://a7-tagam.com.tm/api/v1';

  static const _domainHost = 'a7-tagam.com.tm';

  /// The address [_domainHost] lives at. Devices here regularly fail to
  /// resolve the name at all (`SocketException: Failed host lookup`), which
  /// takes the gateway offline for as long as it lasts.
  static const _fallbackIp = '216.250.12.132';

  /// A client that dials [_fallbackIp] whenever the name cannot be resolved —
  /// or resolves to something that refuses the connection.
  ///
  /// The TLS handshake is still completed against [_domainHost], so the
  /// certificate is verified in full: connecting by address skips DNS, not
  /// authentication. That distinction matters here, because this traffic
  /// carries phone numbers and OTP codes and a machine that merely answers on
  /// that address must not be able to pose as the gateway.
  ///
  /// Verification cannot be waived for the address instead: the certificate
  /// is issued for the domain only (`SAN: a7-tagam.com.tm,
  /// www.a7-tagam.com.tm`), and Dart hands `badCertificateCallback` the CA
  /// rather than the server certificate, so there is nothing there to pin a
  /// name against. Plain `http://216.250.12.132` is no good either — it
  /// answers 308 to the https domain, which this client does not follow.
  static http.Client _createClient() {
    final httpClient = HttpClient()
      ..connectionFactory = (uri, proxyHost, proxyPort) async {
        final isHttps = uri.scheme == 'https';
        try {
          return isHttps
              ? await SecureSocket.startConnect(uri.host, uri.port)
              : await Socket.startConnect(uri.host, uri.port);
        } on SocketException {
          if (!isHttps || uri.host != _domainHost) rethrow;
          final secured = Socket.connect(
            _fallbackIp,
            uri.port,
            timeout: const Duration(seconds: 10),
          ).then((socket) => SecureSocket.secure(socket, host: _domainHost));
          return ConnectionTask.fromSocket(secured, () {});
        }
      };
    return IOClient(httpClient);
  }

  static String effectiveApiBaseUrl(String? savedUrl) {
    final normalized = (savedUrl ?? '').replaceAll(RegExp(r'/+$'), '');
    // Bare-IP and plain-http addresses used before the domain was wired up —
    // the IP gets 308-redirected to the https domain and this http client
    // doesn't follow that, so any device still holding one of these gets
    // upgraded to the real domain automatically.
    const legacyLocalUrls = {
      'http://172.16.14.15:4000/api/v1',
      'http://10.0.2.2:4000/api/v1',
      'http://127.0.0.1:4000/api/v1',
      'http://localhost:4000/api/v1',
      'http://216.250.12.132/api/v1',
      'http://a7-tagam.com.tm/api/v1',
    };
    return normalized.isEmpty || legacyLocalUrls.contains(normalized)
        ? defaultApiBaseUrl
        : normalized;
  }

  final http.Client _client;
  final _storage = GetStorage();

  String get apiBaseUrl => effectiveApiBaseUrl(
        _storage.read<String>(apiBaseUrlKey),
      );
  bool get isConfigured => apiBaseUrl.isNotEmpty;

  Map<String, String> get _headers => {
        'Accept': 'application/json',
      };

  Future<String> heartbeat() async {
    _requireConfiguration();
    final response = await _requestWithFallback(
      (baseUrl) => _client.post(
        Uri.parse('$baseUrl/internal/sms-gateway/heartbeat'),
        headers: _headers,
      ),
    );
    if (response.statusCode != 200) throw GatewayException(_error(response));
    return 'Çevrimiçi';
  }

  /// Returns null when the queue is empty (204).
  Future<SmsGatewayJob?> pull() async {
    _requireConfiguration();
    final response = await _requestWithFallback(
      (baseUrl) => _client.get(
        Uri.parse('$baseUrl/internal/sms-gateway/pull'),
        headers: _headers,
      ),
    );
    if (response.statusCode == 204) return null;
    if (response.statusCode != 200) throw GatewayException(_error(response));
    return SmsGatewayJob.fromJson(
        jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>);
  }

  Future<void> processOne(
      {required void Function(String phone, String otp, String status)
          onResult}) async {
    final job = await pull();
    if (job == null) {
      if (kDebugMode) debugPrint('[SMS GATEWAY] Queue is empty.');
      return;
    }
    if (kDebugMode) {
      debugPrint('[SMS GATEWAY] Job received for ${job.phone}; sending SMS.');
    }
    // The API only returns jobs that are still valid according to the server.
    // Do not reject them based on the device clock: a phone with a different
    // date/time would otherwise discard every job before SmsManager is called.
    if (job.expiresAt.isBefore(DateTime.now()) && kDebugMode) {
      debugPrint(
        '[SMS GATEWAY] Device clock says this job expired '
        '(expiresAt: ${job.expiresAt.toIso8601String()}, '
        'deviceNow: ${DateTime.now().toIso8601String()}); '
        'sending because the server released the job.',
      );
    }

    final result = await BackgroundSms.sendMessage(
        phoneNumber: job.phone, message: job.message);
    if (result == SmsStatus.sent) {
      await report(job, status: 'SENT');
      if (kDebugMode) debugPrint('[SMS GATEWAY] SMS sent to ${job.phone}.');
      onResult(job.phone, _extractOtp(job.message), 'sent');
    } else {
      await report(job, status: 'FAILED', errorCode: _smsErrorCode(result));
      if (kDebugMode) {
        debugPrint('[SMS GATEWAY] SMS failed for ${job.phone}: $result');
      }
      onResult(job.phone, _extractOtp(job.message), 'failed');
    }
  }

  String _extractOtp(String message) =>
      RegExp(r'\d{4,8}').firstMatch(message)?.group(0) ?? '';

  Future<void> report(SmsGatewayJob job,
      {required String status, String? errorCode}) async {
    final response = await _requestWithFallback(
      (baseUrl) => _client.post(
        Uri.parse('$baseUrl/internal/sms-gateway/jobs/${job.id}/status'),
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode({
          'receipt': job.receipt,
          'status': status,
          if (errorCode != null) 'errorCode': errorCode,
        }),
      ),
    );
    if (response.statusCode != 200) throw GatewayException(_error(response));
  }

  void _requireConfiguration() {
    if (!isConfigured) {
      throw GatewayException('Ayarlar ekranından API adresini girin.');
    }
  }

  /// Runs [request] against the configured address under a timeout, and
  /// rethrows with the original stack trace once it has failed.
  ///
  /// Reaching the server when DNS is down is handled a layer lower, by the
  /// client from [_createClient]: the address fallback happens while the
  /// socket is opened, so it applies to every endpoint here and keeps the URL
  /// — and with it the certificate check — on the real domain.
  Future<http.Response> _requestWithFallback(
    Future<http.Response> Function(String baseUrl) request,
  ) async {
    final urls = <String>{apiBaseUrl};
    Object? lastError;
    StackTrace? lastStackTrace;
    for (final baseUrl in urls) {
      try {
        if (kDebugMode) debugPrint('[SMS GATEWAY] Request → $baseUrl');
        final response = await request(baseUrl).timeout(
          const Duration(seconds: 12),
        );
        if (kDebugMode) {
          debugPrint('[SMS GATEWAY] Response ← HTTP ${response.statusCode}');
        }
        return response;
      } catch (error, stackTrace) {
        if (kDebugMode) {
          debugPrint('[SMS GATEWAY] $baseUrl failed: $error');
        }
        lastError = error;
        lastStackTrace = stackTrace;
      }
    }
    Error.throwWithStackTrace(lastError!, lastStackTrace!);
  }

  String _error(http.Response response) {
    try {
      final value = jsonDecode(utf8.decode(response.bodyBytes));
      return value is Map && value['message'] != null
          ? value['message'].toString()
          : 'HTTP ${response.statusCode}';
    } catch (_) {
      return 'HTTP ${response.statusCode}';
    }
  }

  String _smsErrorCode(SmsStatus status) =>
      status.toString().split('.').last.toUpperCase();

  /// Servis ömrü bittiğinde açık kalan soketleri kapatır.
  void dispose() => _client.close();
}

class GatewayException implements Exception {
  GatewayException(this.message);
  final String message;
  @override
  String toString() => message;
}
