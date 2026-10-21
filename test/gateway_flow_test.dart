import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_storage/get_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:sms_otp/app/data/get_otp_model.dart';

class MemorySecrets extends GatewaySecretStore {
  PendingGatewayResult? pending;
  @override
  Future<PendingGatewayResult?> readPendingResult() async => pending;
  @override
  Future<void> writePendingResult(PendingGatewayResult result) async =>
      pending = result;
  @override
  Future<void> clearPendingResult() async => pending = null;
}

http.Response ok(Object data) => http.Response(
    jsonEncode({'statusCode': 200, 'message': 'success', 'data': data}), 200,
    headers: {'content-type': 'application/json'});

final job = {
  'id': 'ef8224d8-72ca-4bb3-bab2-0246f8a0f8f3',
  'recipientPhone': '+99365123456',
  'smsText': 'CODE:5359'
};
const lease = '99be9420-4263-4fb6-be39-827b34532793';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('background_sms');

  setUpAll(() async {
    final directory = Directory.systemTemp.createTempSync('gateway_test_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => directory.path,
    );
    await GetStorage.init();
  });

  setUp(() async {
    await GetStorage().erase();
    await GetStorage().write(SmsGatewayService.subscriptionIdKey, 7);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  test('unwraps jobs and never sends when claim loses the race', () async {
    final calls = <String>[];
    var sends = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      sends++;
      return null;
    });
    final gateway = SmsGatewayService(
        baseUrl: SmsGatewayService.defaultApiBaseUrl,
        testToken: 'device-secret',
        secrets: MemorySecrets(),
        client: MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          expect(request.headers['authorization'], 'Bearer device-secret');
          if (request.method == 'GET') return ok([job]);
          return http.Response('{"message":"already claimed"}', 409);
        }));
    await gateway.processJobs((_) => fail('No result expected'));
    expect(sends, 0);
    expect(calls, [
      'GET /api/v1/internal/otp-sms/jobs',
      'POST /api/v1/internal/otp-sms/jobs/${job['id']}/claim',
    ]);
    gateway.dispose();
  });

  test('claims before SMS and reports accepted send with its lease', () async {
    final steps = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'sendSmsDetailed');
      expect(call.arguments['phone'], job['recipientPhone']);
      expect(call.arguments['msg'], job['smsText']);
      expect(call.arguments['subscriptionId'], 7);
      steps.add('sms');
      return null;
    });
    final secrets = MemorySecrets();
    final gateway = SmsGatewayService(
        baseUrl: SmsGatewayService.defaultApiBaseUrl,
        testToken: 'device-secret',
        secrets: secrets,
        client: MockClient((request) async {
          if (request.method == 'GET') return ok([job]);
          if (request.url.path.endsWith('/claim')) {
            steps.add('claim');
            return ok({'leaseId': lease});
          }
          steps.add('result');
          expect(jsonDecode(request.body),
              {'leaseId': lease, 'status': 'submitted'});
          return ok({'status': 'sent', 'retryable': false});
        }));
    await gateway.processJobs((event) {
      expect(event.jobId, job['id']);
      expect(event.status, 'sent');
      expect(event.phone, job['recipientPhone']);
      expect(event.otp, '5359');
    });
    expect(steps, ['claim', 'sms', 'result']);
    expect(secrets.pending, isNull);
    gateway.dispose();
  });

  test('lost result response is retried without sending another SMS', () async {
    var sends = 0;
    var reports = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (_) async {
      sends++;
      return null;
    });
    final secrets = MemorySecrets();
    final gateway = SmsGatewayService(
        baseUrl: SmsGatewayService.defaultApiBaseUrl,
        testToken: 'device-secret',
        secrets: secrets,
        client: MockClient((request) async {
          if (request.method == 'GET') return ok([job]);
          if (request.url.path.endsWith('/claim')) {
            return ok({'leaseId': lease});
          }
          reports++;
          if (reports == 1) throw const SocketException('lost response');
          return ok({'status': 'sent', 'retryable': false});
        }));
    await expectLater(
        gateway.processJobs((_) {}), throwsA(isA<SocketException>()));
    expect(secrets.pending?.leaseId, lease);
    await gateway.flushPendingResult();
    expect(reports, 2);
    expect(sends, 1);
    expect(secrets.pending, isNull);
    gateway.dispose();
  });
}
