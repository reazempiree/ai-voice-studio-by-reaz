// Controller/native-channel fakes below are not proof of neural inference.
// Real Pocket execution is validated separately by tool/pocket_smoke.dart.
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:ai_voice_studio/application/app_controller.dart';
import 'package:ai_voice_studio/data/audio_service.dart';
import 'package:ai_voice_studio/data/local_store.dart';
import 'package:ai_voice_studio/data/pocket_engine.dart';
import 'package:ai_voice_studio/data/pocket_model_store.dart';
import 'package:ai_voice_studio/domain/models.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class FixturePocketStore extends PocketModelStore {
  FixturePocketStore(super.root);
  bool installed = true;
  int inspections = 0;
  @override
  Future<void> inspect() async {
    inspections++;
    ready = installed;
  }
}

class FixturePocketEngine extends PocketEngine {
  int calls = 0, cancellations = 0;
  Completer<void>? gate;
  final started = Completer<void>();
  bool fail = false;
  @override
  void cancel() {
    cancellations++;
  }

  @override
  Future<double> generate({
    required String modelDirectory,
    required ReferenceWave reference,
    required String text,
    required String outputPath,
    void Function(double)? onProgress,
    int seed = 42,
  }) async {
    calls++;
    if (!started.isCompleted) started.complete();
    if (gate != null) await gate!.future;
    await File(outputPath).writeAsBytes(List<int>.filled(48, 0));
    if (fail) throw const StudioException('পরীক্ষার ব্যর্থতা');
    onProgress?.call(1);
    return 3.5;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStore store;
  late FixturePocketStore models;
  late FixturePocketEngine engine;
  late AppController controller;
  final extraControllers = <AppController>[];
  var serverCalls = 0;
  var decodeCalls = 0;
  var failDecode = false;

  setUp(() async {
    FlutterSecureStorage.setMockInitialValues({});
    root = await Directory.systemTemp.createTemp('voice_pocket_test_');
    store = LocalStore(root);
    models = FixturePocketStore(Directory('${root.path}/models'));
    engine = FixturePocketEngine();
    serverCalls = 0;
    decodeCalls = 0;
    failDecode = false;
    controller = AppController(
      store,
      pocketStore: models,
      pocketEngine: engine,
      clientFactory: (_, _) {
        serverCalls++;
        throw StateError('Offline requests must not use a server');
      },
      referenceDecoder: (_) async {
        decodeCalls++;
        if (failDecode) throw const StudioException('নমুনা নষ্ট');
        return ReferenceWave(Float32List.fromList([0.1, -0.1]), 24000);
      },
    );
    await controller.initialize();
    controller.language = 'en';
    controller.text = 'New speech from my reference.';
    final path = store.audioPath(newId(), 'wav');
    await File(path).writeAsBytes([1, 2, 3]);
    final profile = VoiceProfile(
      id: newId(),
      name: 'নিজের কণ্ঠ',
      path: path,
      referenceText: 'The sample reference transcript.',
      createdAt: DateTime(2026),
      durationSeconds: 8,
    );
    controller.profiles = [profile];
    controller.selectedProfileId = profile.id;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, (_) async => null);
  });
  tearDown(() async {
    for (final item in extraControllers) {
      item.dispose();
    }
    extraControllers.clear();
    await controller.flush();
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, null);
    await root.delete(recursive: true);
  });

  test(
    'local English needs no URL, token, upload or network adapter',
    () async {
      expect(controller.backendUrl, isEmpty);
      expect(controller.token, isEmpty);
      expect(controller.generationBlockReason, isEmpty);
      await controller.generate(uploadConsent: false);
      expect(controller.error, isEmpty);
      expect(serverCalls, 0);
      expect(decodeCalls, 1);
      expect(engine.calls, 1);
      expect(controller.history, hasLength(1));
      expect(controller.history.single.language, 'en');
      expect(await File(controller.history.single.wavPath).exists(), isTrue);
      expect(controller.latest?.durationSeconds, 3.5);
      final saved = await store.read();
      expect(saved['history'], hasLength(1));
      expect(saved['profiles'], hasLength(1));
    },
  );

  test(
    'Bengali local request is blocked before decoder, model or network',
    () async {
      controller.language = 'bn';
      await controller.generate(uploadConsent: false);
      expect(controller.error, contains('বাংলার জন্য পরীক্ষিত ফোনের মডেল নেই'));
      expect(engine.calls, 0);
      expect(decodeCalls, 0);
      expect(serverCalls, 0);
      expect(controller.history, isEmpty);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'missing model gives install action feedback instead of server error',
    () async {
      models.ready = false;
      models.installed = false;
      await controller.generate(uploadConsent: false);
      expect(controller.error, contains('Pocket'));
      expect(controller.error, isNot(contains('প্রবেশ সংকেত দিন')));
      expect(engine.calls, 0);
      expect(serverCalls, 0);
    },
  );

  test('corrupted model discovered by recheck prevents inference', () async {
    models.ready = true;
    models.installed = false;
    await controller.generate(uploadConsent: false);
    expect(models.inspections, 2);
    expect(controller.error, contains('নষ্ট বা অনুপস্থিত'));
    expect(engine.calls, 0);
    expect(decodeCalls, 0);
    expect(controller.history, isEmpty);
  });

  test('native decode failure creates no job or orphan output', () async {
    failDecode = true;
    await controller.generate(uploadConsent: false);
    expect(controller.error, 'নমুনা নষ্ট');
    expect(engine.calls, 0);
    expect(controller.history, isEmpty);
    final audio = await Directory('${root.path}/audio').list().toList();
    expect(audio, hasLength(1)); // Only the original reference survives.
  });

  test(
    'inference error removes incomplete file and preserves reference',
    () async {
      engine.fail = true;
      final reference = controller.selectedProfile!.path;
      await controller.generate(uploadConsent: false);
      expect(controller.error, 'পরীক্ষার ব্যর্থতা');
      expect(controller.history, isEmpty);
      expect(await File(reference).exists(), isTrue);
      expect(await Directory('${root.path}/audio').list().length, 1);
    },
  );

  test('duplicate requests do not start duplicate local models', () async {
    engine.gate = Completer<void>();
    final first = controller.generate(uploadConsent: false);
    await engine.started.future;
    expect(controller.busy, isTrue);
    await controller.generate(uploadConsent: false);
    expect(engine.calls, 1);
    engine.gate!.complete();
    await first;
    expect(controller.history, hasLength(1));
    expect(controller.busy, isFalse);
  });

  test(
    'cancellation waits for worker and does not save cancelled output',
    () async {
      engine.gate = Completer<void>();
      final generation = controller.generate(uploadConsent: false);
      await engine.started.future;
      await controller.cancel();
      expect(engine.cancellations, 1);
      expect(controller.busy, isTrue);
      engine.gate!.complete();
      await generation;
      expect(controller.history, isEmpty);
      expect(controller.error, isEmpty);
      expect(controller.status, contains('বাতিল'));
      expect(await Directory('${root.path}/audio').list().length, 1);
      expect(controller.busy, isFalse);
    },
  );

  test(
    'mode survives reopen without changing old profiles/history schema',
    () async {
      await controller.generate(uploadConsent: false);
      controller.setInferenceMode('server');
      await controller.flush();
      final restored = AppController(store, pocketStore: models);
      extraControllers.add(restored);
      await restored.initialize();
      expect(restored.inferenceMode, 'server');
      expect(restored.profiles.single.path, controller.profiles.single.path);
      expect(
        restored.history.single.wavPath,
        controller.history.single.wavPath,
      );
      expect(restored.history.single.text, controller.history.single.text);
      expect((await store.read())['schema'], 1);
    },
  );

  test(
    'old schema with server binding keeps server mode and user data',
    () async {
      await controller.flush();
      final old = await store.read();
      old.remove('inferenceMode');
      old['backendUrl'] = 'http://192.168.1.10:8765';
      await store.write(old);
      final restored = AppController(store, pocketStore: models);
      extraControllers.add(restored);
      await restored.initialize();
      expect(restored.inferenceMode, 'server');
      expect(restored.profiles.single.id, controller.profiles.single.id);
      expect(restored.text, 'New speech from my reference.');
    },
  );

  test(
    'native channel accepts real typed PCM and rejects malformed payload',
    () async {
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        AudioService.channel,
        (call) async => {
          'samples': Float32List.fromList([0.25, -0.25]),
          'sampleRate': 48000,
        },
      );
      final wave = await controller.audio.decodeReference(
        controller.selectedProfile!.path,
      );
      expect(wave.samples, [0.25, -0.25]);
      expect(wave.sampleRate, 48000);
      messenger.setMockMethodCallHandler(
        AudioService.channel,
        (_) async => {
          'samples': [1, 2],
          'sampleRate': 48000,
        },
      );
      await expectLater(
        controller.audio.decodeReference(controller.selectedProfile!.path),
        throwsA(isA<StudioException>()),
      );
    },
  );

  test('segmentation preserves words and sentence punctuation', () {
    final text = List.filled(80, 'reference').join(' ');
    final segments = pocketSegments('$text. Next sentence!');
    expect(segments.every((part) => part.length <= 220), isTrue);
    expect(segments.join(' '), '$text. Next sentence!');
  });

  test('local text boundary rejects Bengali and over 1500 characters', () {
    expect(
      () => pocketSegments('আমি বাংলা বলি।'),
      throwsA(isA<StudioException>()),
    );
    expect(() => pocketSegments('a' * 1501), throwsA(isA<StudioException>()));
    expect(() => pocketSegments('  '), throwsA(isA<StudioException>()));
    expect(pocketSegments('Hello. New speech!'), ['Hello.', 'New speech!']);
  });
}
