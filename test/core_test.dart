import 'dart:convert';
import 'dart:io';

import 'package:ai_voice_studio/application/app_controller.dart';
import 'package:ai_voice_studio/data/audio_service.dart';
import 'package:ai_voice_studio/data/local_store.dart';
import 'package:ai_voice_studio/domain/models.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

class TestPicker extends FilePicker {
  @override
  Future<bool?> clearTemporaryFiles() async => true;
  File? source;
  Uint8List? exported;
  String? exportedName;
  @override
  Future<FilePickerResult?> pickFiles({
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    String? dialogTitle,
    String? initialDirectory,
    Function(FilePickerStatus)? onFileLoading,
    bool? allowCompression = false,
    bool allowMultiple = false,
    bool? withData = false,
    int compressionQuality = 0,
    bool? withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async {
    if (source == null) {
      return null;
    }
    return FilePickerResult([
      PlatformFile(
        name: source!.uri.pathSegments.last,
        path: source!.path,
        size: await source!.length(),
      ),
    ]);
  }

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    exported = bytes;
    exportedName = fileName;
    return '/chosen/$fileName';
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late LocalStore store;
  late AppController controller;
  late TestPicker picker;
  double duration = 8;
  bool decodingFails = false;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('voice_core_');
    store = LocalStore(root);
    await store.initialize();
    picker = TestPicker();
    FilePicker.platform = picker;
    duration = 8;
    decodingFails = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, (call) async {
          if (decodingFails) {
            throw PlatformException(code: 'DECODE_FAILED');
          }
          return {'durationSeconds': duration};
        });
    FlutterSecureStorage.setMockInitialValues({});
    controller = AppController(store);
    await controller.initialize();
  });
  tearDown(() async {
    await controller.flush();
    controller.dispose();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AudioService.channel, null);
    await root.delete(recursive: true);
  });
  Future<void> selectFile(String extension, {int length = 128}) async {
    picker.source = File('${root.path}/source.$extension');
    await picker.source!.writeAsBytes(List.filled(length, 1));
  }

  Future<void> importVoice() => controller.importProfile(
    name: 'আমার কণ্ঠ',
    referenceText: 'আমি বাংলা বলি।',
    consent: true,
  );

  test(
    'Unicode text and punctuation preserved; blank and oversized text rejected',
    () {
      expect(validateText('  আমার বাংলা। Hello!  '), 'আমার বাংলা। Hello!');
      expect(validateText('😀' * 3000).runes.length, 3000);
      expect(() => validateText('a' * 3001), throwsA(isA<StudioException>()));
      expect(() => validateText(' \n'), throwsA(isA<StudioException>()));
      expect(() => validateName(' ' * 4), throwsA(isA<StudioException>()));
      expect(() => validateName('ক' * 81), throwsA(isA<StudioException>()));
    },
  );
  test(
    'safe generated filenames and extension validation block traversal',
    () async {
      final id = newId();
      expect(id, matches(RegExp(r'^[a-f0-9]{32}$')));
      final path = store.audioPath(id, 'wav');
      expect(store.ownsPath(path), isTrue);
      expect(
        () => store.audioPath('../outside', 'wav'),
        throwsA(isA<StudioException>()),
      );
      expect(() => store.audioPath(id, 'exe'), throwsA(isA<StudioException>()));
      expect(store.ownsPath('${root.path}/audio/../victim.wav'), isFalse);
      expect(
        () => store.deleteAudio('${root.path}/victim.wav'),
        throwsA(isA<StudioException>()),
      );
    },
  );
  test(
    'atomic persistence round trips Unicode and recovers prior valid backup',
    () async {
      await store.write({'profiles': [], 'history': [], 'text': 'প্রথম'});
      await store.write({'profiles': [], 'history': [], 'text': 'দ্বিতীয়'});
      expect((await store.read())['text'], 'দ্বিতীয়');
      await store.index.writeAsString('{damaged');
      expect((await store.read())['text'], 'প্রথম');
    },
  );
  test(
    'corrupt and malicious persisted paths fail without deleting user data',
    () async {
      final external = File('${root.path}/private.wav');
      await external.writeAsString('preserve');
      await store.index.writeAsString(
        jsonEncode({
          'schema': 1,
          'profiles': [
            {'path': external.path},
          ],
        }),
      );
      await expectLater(store.read(), throwsA(isA<StudioException>()));
      expect(await external.readAsString(), 'preserve');
    },
  );
  test('import requires ownership permission before opening picker', () async {
    await selectFile('wav');
    await controller.importProfile(
      name: 'নাম',
      referenceText: 'লেখা',
      consent: false,
    );
    expect(controller.profiles, isEmpty);
    expect(controller.error, contains('অনুমতি'));
  });
  test(
    'valid import copies audio, persists transcript and selects saved voice',
    () async {
      await selectFile('wav');
      await importVoice();
      expect(controller.error, isEmpty);
      expect(controller.profiles, hasLength(1));
      final p = controller.profiles.single;
      expect(p.path, isNot(picker.source!.path));
      expect(
        await File(p.path).readAsBytes(),
        await picker.source!.readAsBytes(),
      );
      expect(p.referenceText, 'আমি বাংলা বলি।');
      expect(controller.selectedProfile!.id, p.id);
      final restored = AppController(store);
      await restored.initialize();
      expect(restored.profiles.single.referenceText, p.referenceText);
      restored.dispose();
    },
  );
  test('picker cancellation has no side effects', () async {
    await importVoice();
    expect(controller.profiles, isEmpty);
    expect(controller.error, isEmpty);
  });
  test(
    'empty and unsupported recordings are rejected before decoding',
    () async {
      await selectFile('wav', length: 0);
      await importVoice();
      expect(controller.profiles, isEmpty);
      expect(controller.error, contains('খালি'));
      await selectFile('txt');
      await importVoice();
      expect(controller.profiles, isEmpty);
      expect(controller.error, contains('WAV'));
    },
  );
  test(
    'decode error removes copied audio and presents Bengali failure',
    () async {
      await selectFile('mp3');
      decodingFails = true;
      await importVoice();
      expect(controller.profiles, isEmpty);
      expect(controller.error, contains('ডিকোড'));
      expect(await Directory('${root.path}/audio').list().length, 0);
    },
  );
  test(
    'out of range reference duration is rejected and copy is removed',
    () async {
      await selectFile('m4a');
      duration = 31;
      await importVoice();
      expect(controller.profiles, isEmpty);
      expect(controller.error, contains('৩০'));
      expect(await Directory('${root.path}/audio').list().length, 0);
    },
  );
  test(
    'rename and replace preserve profile identity and delete old reference',
    () async {
      await selectFile('wav');
      await importVoice();
      final original = controller.profiles.single;
      await controller.renameProfile(original, 'নতুন নাম');
      expect(controller.profiles.single.name, 'নতুন নাম');
      await selectFile('mp3');
      await controller.replaceProfile(
        controller.profiles.single,
        referenceText: 'নতুন কথা',
        consent: true,
      );
      final updated = controller.profiles.single;
      expect(updated.id, original.id);
      expect(updated.referenceText, 'নতুন কথা');
      expect(await File(original.path).exists(), isFalse);
      expect(await File(updated.path).exists(), isTrue);
    },
  );
  test(
    'deleting profile removes reference and its recovery metadata',
    () async {
      await selectFile('wav');
      await importVoice();
      final p = controller.profiles.single;
      await controller.deleteProfile(p);
      expect(controller.profiles, isEmpty);
      expect(await File(p.path).exists(), isFalse);
      expect(
        await store.backup.readAsString(),
        isNot(contains(p.referenceText)),
      );
    },
  );
  test(
    'editor state flush persists Bengali text and selected language',
    () async {
      controller.setText('বাংলা লেখা।');
      controller.setLanguage('en');
      await controller.flush();
      final state = await store.read();
      expect(state['text'], 'বাংলা লেখা।');
      expect(state['language'], 'en');
    },
  );
  test(
    'backend settings reject plaintext Internet and protect token from JSON',
    () async {
      await controller.saveSettings(url: 'http://example.com', token: 'x' * 32);
      expect(controller.error, isNotEmpty);
      expect(controller.backendUrl, isEmpty);
      controller.clearError();
      await controller.saveSettings(
        url: 'https://voice.local:8443',
        token: 'x' * 32,
      );
      expect(controller.error, isEmpty);
      expect(await store.index.readAsString(), isNot(contains('x' * 32)));
      expect(await controller.secure.read(key: 'backend-token'), 'x' * 32);
    },
  );
  test(
    'WAV export preserves bytes through document picker without backend',
    () async {
      final path = store.audioPath(newId(), 'wav');
      final bytes = Uint8List.fromList([82, 73, 70, 70, ...List.filled(80, 0)]);
      await File(path).writeAsBytes(bytes);
      final record = AudioRecord(
        id: newId(),
        name: 'কৃত্রিম',
        wavPath: path,
        profileName: 'নিজের',
        language: 'bn',
        text: 'লেখা',
        createdAt: DateTime.now(),
        durationSeconds: 1,
      );
      await controller.exportRecord(record, format: 'wav');
      expect(controller.error, isEmpty);
      expect(picker.exported, orderedEquals(bytes));
      expect(picker.exportedName, endsWith('.wav'));
    },
  );
}
