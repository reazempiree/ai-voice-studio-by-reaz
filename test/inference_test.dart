// Client protocol and controller tests use explicit fakes, not real AI inference.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_voice_studio/application/app_controller.dart';
import 'package:ai_voice_studio/data/audio_service.dart';
import 'package:ai_voice_studio/data/inference_client.dart';
import 'package:ai_voice_studio/data/local_store.dart';
import 'package:ai_voice_studio/domain/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Uint8List fixtureWav() {
  final bytes = ByteData(48);
  void tag(int start, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes.setUint8(start + i, value.codeUnitAt(i));
    }
  }

  tag(0, 'RIFF');
  bytes.setUint32(4, 40, Endian.little);
  tag(8, 'WAVE');
  tag(12, 'fmt ');
  bytes.setUint32(16, 16, Endian.little);
  bytes.setUint16(20, 1, Endian.little);
  bytes.setUint16(22, 1, Endian.little);
  bytes.setUint32(24, 24000, Endian.little);
  bytes.setUint32(28, 48000, Endian.little);
  bytes.setUint16(32, 2, Endian.little);
  bytes.setUint16(34, 16, Endian.little);
  tag(36, 'data');
  bytes.setUint32(40, 4, Endian.little);
  return bytes.buffer.asUint8List();
}

class FakeInference extends InferenceClient {
  FakeInference() : super('http://127.0.0.1:8000', 'test-token');
  int created = 0, cancelled = 0, downloads = 0;
  bool closed = false, available = true;
  String state = 'completed';
  String? receivedText, receivedLanguage, receivedProfile;
  Completer<void>? capabilitiesGate, jobGate;
  Completer<void> polled = Completer<void>();
  bool failDownload = false;
  @override
  Future<BackendCapabilities> capabilities() async {
    if (capabilitiesGate != null) {
      await capabilitiesGate!.future;
    }
    return BackendCapabilities(
      available: available,
      languages: ['bn', 'en'],
      reason: 'fake test only',
      raw: {},
    );
  }

  @override
  Future<Map<String, dynamic>> createJob({
    required VoiceProfile profile,
    required String text,
    required String language,
  }) async {
    created++;
    receivedText = text;
    receivedLanguage = language;
    receivedProfile = profile.id;
    return {'id': 'job-test', 'status': 'queued'};
  }

  @override
  Future<Map<String, dynamic>> job(String id) async {
    if (!polled.isCompleted) {
      polled.complete();
    }
    if (jobGate != null) {
      await jobGate!.future;
    }
    return {
      'id': id,
      'status': state,
      'progress': state == 'completed' ? 1 : 0.5,
    };
  }

  @override
  Future<void> downloadAudio(
    String id,
    File target, {
    String format = 'wav',
  }) async {
    downloads++;
    await target.writeAsBytes(fixtureWav());
    if (failDownload) {
      throw const StudioException('নামানো ব্যর্থ');
    }
  }

  @override
  Future<void> cancelJob(String id) async {
    cancelled++;
  }

  @override
  void close() {
    closed = true;
    super.close();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStore store;
  late AppController controller;
  late FakeInference fake;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice_inference_');
    store = LocalStore(root);
    FlutterSecureStorage.setMockInitialValues({});
    fake = FakeInference();
    controller = AppController(store, clientFactory: (_, _) => fake);
    await controller.initialize();
    controller.inferenceMode = 'server';
    controller.backendUrl = 'http://127.0.0.1:8000';
    controller.token = 'x' * 32;
    final profile = VoiceProfile(
      id: newId(),
      name: 'নিজের কণ্ঠ',
      path: store.audioPath(newId(), 'wav'),
      referenceText: 'আমার নমুনা কথা।',
      createdAt: DateTime(2026),
      durationSeconds: 8,
    );
    await File(profile.path).writeAsBytes(fixtureWav());
    controller.profiles = [profile];
    controller.selectedProfileId = profile.id;
    controller.text = 'আমার লেখা।';
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          AudioService.channel,
          (call) async => {'durationSeconds': 3.5},
        );
  });
  tearDown(() async {
    await controller.flush();
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, null);
    await root.delete(recursive: true);
  });
  test(
    'HTTP transport sends authorization and correctly parses capabilities',
    () async {
      final c = InferenceClient(
        'https://voice.local',
        'private-test',
        client: MockClient((request) async {
          expect(request.headers['Authorization'], 'Bearer private-test');
          expect(request.url.path, '/v1/capabilities');
          return http.Response(
            jsonEncode({
              'available': true,
              'languages': ['bn'],
              'reason': 'local host',
            }),
            200,
          );
        }),
      );
      final caps = await c.capabilities();
      expect(caps.available, isTrue);
      expect(caps.languages, ['bn']);
      c.close();
    },
  );
  test(
    'remote response errors are mapped to Bengali without exposing body',
    () async {
      for (final code in [401, 403, 413, 503, 500]) {
        final c = InferenceClient(
          'https://voice.local',
          'test',
          client: MockClient(
            (_) async => http.Response('secret-server-details', code),
          ),
        );
        await expectLater(
          c.capabilities(),
          throwsA(
            isA<StudioException>().having(
              (e) => e.message,
              'safe Bengali message',
              isNot(contains('secret-server-details')),
            ),
          ),
        );
        c.close();
      }
    },
  );
  test(
    'malformed response and server job traversal identifiers are rejected',
    () async {
      final c = InferenceClient(
        'https://voice.local',
        'test',
        client: MockClient((_) async => http.Response('[]', 200)),
      );
      await expectLater(c.capabilities(), throwsA(isA<StudioException>()));
      expect(() => c.safeId('../private'), throwsA(isA<StudioException>()));
      c.close();
    },
  );
  test(
    'backend URL validation enforces secure remote connections and no embedded credentials',
    () {
      for (final value in [
        'http://example.com',
        'https://user:pass@voice.local',
        'https://voice.local/path',
        'https://voice.local?key=secret',
        'file:///tmp/model',
      ]) {
        expect(
          () => validateBackendUrl(value),
          throwsA(isA<StudioException>()),
        );
      }
      for (final value in [
        'http://192.168.1.20:8000',
        'http://10.0.0.2:8000',
        'https://example.com',
        'http://localhost:8000',
      ]) {
        expect(validateBackendUrl(value).host, isNotEmpty);
      }
    },
  );
  test(
    'generation without upload consent never invokes the inference adapter',
    () async {
      await controller.generate(uploadConsent: false);
      expect(fake.created, 0);
      expect(fake.downloads, 0);
      expect(controller.busy, isFalse);
      expect(controller.error, contains('অনুমতি'));
    },
  );
  test(
    'missing profile and unavailable model fail without creating history',
    () async {
      controller.selectedProfileId = null;
      await controller.generate(uploadConsent: true);
      expect(controller.error, contains('কণ্ঠ নির্বাচন'));
      expect(fake.created, 0);
      controller.selectedProfileId = controller.profiles.single.id;
      fake.available = false;
      await controller.generate(uploadConsent: true);
      expect(controller.error, contains('প্রস্তুত নেই'));
      expect(controller.history, isEmpty);
    },
  );
  test(
    'mocked generation pipeline saves WAV metadata and cleans backend temporary job',
    () async {
      await controller.generate(uploadConsent: true);
      expect(controller.error, isEmpty);
      expect(controller.busy, isFalse);
      expect(fake.created, 1);
      expect(fake.downloads, 1);
      expect(fake.cancelled, 1);
      expect(fake.closed, isTrue);
      expect(fake.receivedText, 'আমার লেখা।');
      expect(fake.receivedLanguage, 'bn');
      expect(fake.receivedProfile, controller.profiles.single.id);
      final record = controller.history.single;
      expect(record.text, 'আমার লেখা।');
      expect(record.durationSeconds, 3.5);
      expect(await File(record.wavPath).readAsBytes(), fixtureWav());
      final restored = AppController(store);
      await restored.initialize();
      expect(restored.history.single.id, record.id);
      restored.dispose();
    },
  );
  test(
    'duplicate generation is prevented while an existing request waits',
    () async {
      fake.capabilitiesGate = Completer<void>();
      final first = controller.generate(uploadConsent: true);
      await Future<void>.delayed(Duration.zero);
      expect(controller.busy, isTrue);
      await controller.generate(uploadConsent: true);
      fake.capabilitiesGate!.complete();
      await first;
      expect(fake.created, 1);
      expect(controller.history, hasLength(1));
    },
  );
  test(
    'cancellation during model readiness prevents any reference upload',
    () async {
      fake.capabilitiesGate = Completer<void>();
      final request = controller.generate(uploadConsent: true);
      await Future<void>.delayed(Duration.zero);
      await controller.cancel();
      fake.capabilitiesGate!.complete();
      await request;
      expect(fake.created, 0);
      expect(controller.history, isEmpty);
      expect(controller.status, contains('বাতিল'));
      expect(controller.busy, isFalse);
    },
  );
  test(
    'cancellation of an active job cleans server and does not save output',
    () async {
      fake.jobGate = Completer<void>();
      final request = controller.generate(uploadConsent: true);
      await fake.polled.future;
      await controller.cancel();
      fake.jobGate!.complete();
      await request;
      expect(fake.cancelled, greaterThanOrEqualTo(1));
      expect(fake.downloads, 0);
      expect(controller.history, isEmpty);
      expect(controller.busy, isFalse);
    },
  );
  test(
    'model failure leaves no generated file and exposes a useful error',
    () async {
      fake.state = 'failed';
      await controller.generate(uploadConsent: true);
      expect(controller.error, contains('তৈরি হয়নি'));
      expect(controller.history, isEmpty);
      expect(fake.cancelled, 1);
      expect(controller.busy, isFalse);
      expect(await Directory('${root.path}/audio').list().length, 1);
    },
  );
  test(
    'interrupted output download deletes partial file and preserves library',
    () async {
      fake.failDownload = true;
      await controller.generate(uploadConsent: true);
      expect(controller.error, contains('ব্যর্থ'));
      expect(controller.history, isEmpty);
      expect(await Directory('${root.path}/audio').list().length, 1);
    },
  );
  test(
    'history rename updates active card; deletion removes audio and backup metadata',
    () async {
      await controller.generate(uploadConsent: true);
      final record = controller.history.single;
      await controller.renameRecord(record, 'নতুন শিরোনাম');
      expect(controller.latest!.name, 'নতুন শিরোনাম');
      await controller.deleteRecord(controller.history.single);
      expect(controller.history, isEmpty);
      expect(controller.latest, isNull);
      expect(await File(record.wavPath).exists(), isFalse);
      expect(await store.backup.readAsString(), isNot(contains(record.id)));
    },
  );
}
