import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/widgets.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import '../domain/models.dart';
import '../data/audio_service.dart';
import '../data/inference_client.dart';
import '../data/local_store.dart';

class AppController extends ChangeNotifier with WidgetsBindingObserver {
  AppController(
    this.store, {
    FlutterSecureStorage? secureStorage,
    this.clientFactory,
  }) : secure = secureStorage ?? const FlutterSecureStorage(),
       audio = AudioService(store);
  final LocalStore store;
  final InferenceClient Function(String, String)? clientFactory;
  Timer? _textSaveTimer;
  final FlutterSecureStorage secure;
  final AudioService audio;
  List<VoiceProfile> profiles = [];
  List<AudioRecord> history = [];
  List<Map<String, dynamic>> models = [];
  String? selectedProfileId, updateUrl;
  String text = '',
      language = 'bn',
      backendUrl = '',
      token = '',
      status = '',
      error = '';
  bool busy = false, connecting = false;
  double progress = 0;
  BackendCapabilities? capabilities;
  AudioRecord? latest;
  InferenceClient? _active;
  String? _jobId;
  bool _cancelled = false;
  bool _disposed = false;
  bool _loaded = false;
  Future<void> _writes = Future.value();
  VoiceProfile? get selectedProfile {
    for (final p in profiles) {
      if (p.id == selectedProfileId) {
        return p;
      }
    }
    return null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) {
      super.notifyListeners();
    }
  }

  Future<void> initialize() async {
    WidgetsBinding.instance.addObserver(this);
    await _guard(() async {
      await store.initialize();
      final data = await store.read();
      profiles = (data['profiles'] as List? ?? [])
          .map(
            (j) => VoiceProfile.fromJson(Map<String, dynamic>.from(j as Map)),
          )
          .toList();
      history = (data['history'] as List? ?? [])
          .map((j) => AudioRecord.fromJson(Map<String, dynamic>.from(j as Map)))
          .toList();
      text = data['text'] as String? ?? '';
      language = data['language'] as String? ?? 'bn';
      backendUrl = data['backendUrl'] as String? ?? '';
      selectedProfileId = data['selectedProfileId'] as String?;
      token = await secure.read(key: 'backend-token') ?? '';
      _loaded = true;
    });
  }

  Future<void> _guard(Future<void> Function() action) async {
    try {
      await action();
    } on StudioException catch (e) {
      error = e.message;
    } on FileSystemException catch (e) {
      error = e.osError?.errorCode == 28
          ? 'জায়গা নেই। কিছু ফাইল মুছে আবার চেষ্টা করুন।'
          : 'ফাইল পড়া বা সংরক্ষণ করা যায়নি।';
    } on TimeoutException {
      error = 'সময় শেষ হয়েছে। সার্ভার ও নেটওয়ার্ক পরীক্ষা করুন।';
    } catch (_) {
      error =
          'কাজটি শেষ করা যায়নি। সংযোগ, ফাইল এবং সার্ভারের অবস্থা পরীক্ষা করুন।';
    }
    notifyListeners();
  }

  Future<void> _save() {
    if (!_loaded) {
      throw const StudioException('তথ্য লোড হয়নি। অ্যাপ আবার খুলুন।');
    }
    final state = {
      'profiles': profiles.map((p) => p.toJson()).toList(),
      'history': history.map((r) => r.toJson()).toList(),
      'text': text,
      'language': language,
      'backendUrl': backendUrl,
      'selectedProfileId': selectedProfileId,
    };
    final write = _writes.then((_) => store.write(state));
    _writes = write.catchError((Object _) {});
    return write;
  }

  void clearError() {
    error = '';
    notifyListeners();
  }

  void setText(String value) {
    text = value;
    notifyListeners();
    _textSaveTimer?.cancel();
    _textSaveTimer = Timer(
      const Duration(milliseconds: 400),
      () => unawaited(_guard(_save)),
    );
  }

  void setLanguage(String value) {
    if (!['bn', 'en'].contains(value)) {
      return;
    }
    language = value;
    notifyListeners();
    unawaited(_guard(_save));
  }

  void selectProfile(String? id) {
    selectedProfileId = id;
    notifyListeners();
    unawaited(_guard(_save));
  }

  Future<void> importProfile({
    required String name,
    required String referenceText,
    required bool consent,
  }) => _guard(() async {
    if (!consent) {
      throw const StudioException('কণ্ঠ ব্যবহারের অনুমতি নিশ্চিত করুন।');
    }
    final label = validateName(name), transcript = validateText(referenceText);
    if (transcript.length > 1000) {
      throw const StudioException(
        'রেফারেন্সের প্রতিলিপি ১০০০ অক্ষরের মধ্যে লিখুন।',
      );
    }
    final imported = await audio.import();
    if (imported == null) {
      return;
    }
    final profile = VoiceProfile(
      id: newId(),
      name: label,
      path: imported.path,
      referenceText: transcript,
      createdAt: DateTime.now(),
      durationSeconds: imported.durationSeconds,
    );
    profiles = [...profiles, profile];
    selectedProfileId = profile.id;
    try {
      await _save();
    } catch (_) {
      profiles.removeWhere((p) => p.id == profile.id);
      await store.deleteAudio(profile.path);
      rethrow;
    }
  });
  Future<void> renameProfile(VoiceProfile p, String name) => _guard(() async {
    final replacement = p.copyWith(name: validateName(name));
    final old = profiles;
    profiles = [
      for (final item in profiles)
        if (item.id == p.id) replacement else item,
    ];
    try {
      await _save();
    } catch (_) {
      profiles = old;
      rethrow;
    }
  });
  Future<void> deleteProfile(VoiceProfile p) => _guard(() async {
    final old = profiles;
    profiles = profiles.where((x) => x.id != p.id).toList();
    try {
      await _save();
    } catch (_) {
      profiles = old;
      rethrow;
    }
    await store.deleteAudio(p.path);
    // Remove the recovery copy too: deletion must not retain private references.
    await store.write(_snapshot());
  });
  Map<String, dynamic> _snapshot() => {
    'profiles': profiles.map((p) => p.toJson()).toList(),
    'history': history.map((p) => p.toJson()).toList(),
    'text': text,
    'language': language,
    'backendUrl': backendUrl,
    'selectedProfileId': selectedProfileId,
  };
  Future<void> replaceProfile(
    VoiceProfile p, {
    required String referenceText,
    required bool consent,
  }) => _guard(() async {
    if (!consent) {
      throw const StudioException('কণ্ঠ ব্যবহারের অনুমতি নিশ্চিত করুন।');
    }
    final transcript = validateText(referenceText);
    if (transcript.length > 1000) {
      throw const StudioException(
        'রেফারেন্সের প্রতিলিপি ১০০০ অক্ষরের মধ্যে লিখুন।',
      );
    }
    final imported = await audio.import();
    if (imported == null) {
      return;
    }
    final old = profiles;
    profiles = [
      for (final item in profiles)
        if (item.id == p.id)
          p.copyWith(
            path: imported.path,
            referenceText: transcript,
            durationSeconds: imported.durationSeconds,
          )
        else
          item,
    ];
    try {
      await _save();
    } catch (_) {
      profiles = old;
      await store.deleteAudio(imported.path);
      rethrow;
    }
    await store.deleteAudio(p.path);
    await store.write(_snapshot());
  });
  InferenceClient _client() {
    if (backendUrl.isEmpty || token.isEmpty) {
      throw const StudioException(
        'সেটিংসে স্থানীয় সার্ভার ও প্রবেশ সংকেত দিন।',
      );
    }
    return (clientFactory ?? InferenceClient.new)(backendUrl, token);
  }

  Future<void> saveSettings({required String url, required String token}) =>
      _guard(() async {
        if (busy) {
          throw const StudioException('চলমান কাজ শেষ অথবা বাতিল করুন।');
        }
        validateBackendUrl(url);
        if (token.trim().length < 24) {
          throw const StudioException(
            'সার্ভারের অন্তত ২৪ অক্ষরের প্রবেশ সংকেত দিন।',
          );
        }
        await secure.write(key: 'backend-token', value: token.trim());
        backendUrl = url.trim();
        this.token = token.trim();
        capabilities = null;
        models = [];
        await _save();
        status = 'সার্ভারের তথ্য সংরক্ষিত হয়েছে।';
      });
  Future<void> connect() async {
    if (connecting) {
      return;
    }
    connecting = true;
    notifyListeners();
    await _guard(() async {
      final client = _client();
      try {
        capabilities = await client.capabilities();
        status = capabilities!.available
            ? 'সার্ভার প্রস্তুত।'
            : 'সার্ভার যুক্ত; মডেল প্রস্তুত নয়।';
      } finally {
        client.close();
      }
    });
    connecting = false;
    notifyListeners();
    await refreshModels();
  }

  Future<void> generate({required bool uploadConsent}) async {
    if (busy) {
      return;
    }
    busy = true;
    _cancelled = false;
    progress = 0;
    error = '';
    status = 'প্রস্তুত করা হচ্ছে…';
    notifyListeners();
    File? pending;
    await _guard(() async {
      if (!uploadConsent) {
        throw const StudioException(
          'রেকর্ডিং ও লেখা সার্ভারে পাঠানোর অনুমতি দিন।',
        );
      }
      final profile = selectedProfile;
      if (profile == null) {
        throw const StudioException('আগে একটি কণ্ঠ নির্বাচন করুন।');
      }
      final content = validateText(text), lang = language;
      final client = _client();
      _active = client;
      final caps = await client.capabilities();
      capabilities = caps;
      if (!caps.available || !caps.languages.contains(lang)) {
        throw const StudioException(
          'নির্বাচিত ভাষার মডেল সার্ভারে প্রস্তুত নেই।',
        );
      }
      if (_cancelled) {
        return;
      }
      status = 'অনুমোদিত সার্ভারে রেকর্ডিং পাঠানো হচ্ছে…';
      notifyListeners();
      final created = await client.createJob(
        profile: profile,
        text: content,
        language: lang,
      );
      final id = created['id'] as String;
      _jobId = id;
      final deadline = DateTime.now().add(const Duration(minutes: 30));
      Map<String, dynamic> job = created;
      while (!_cancelled) {
        if (DateTime.now().isAfter(deadline)) {
          throw const StudioException(
            'তৈরির সময়সীমা শেষ। ছোট লেখা দিয়ে আবার চেষ্টা করুন।',
          );
        }
        job = await client.job(id);
        final state = job['status'];
        progress = ((job['progress'] as num?)?.toDouble() ?? 0).clamp(0, 1);
        status = 'কৃত্রিম কণ্ঠ তৈরি হচ্ছে…';
        notifyListeners();
        if (state == 'completed') {
          break;
        }
        if (state == 'failed') {
          throw const StudioException(
            'সার্ভারে কণ্ঠ তৈরি হয়নি। মডেল, স্মৃতি ও রেকর্ডিং পরীক্ষা করুন।',
          );
        }
        if (state == 'cancelled') {
          _cancelled = true;
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 700));
      }
      if (_cancelled) {
        return;
      }
      final recordId = newId();
      pending = File(store.audioPath(recordId, 'wav'));
      await client.downloadAudio(id, pending!);
      if (_cancelled) {
        return;
      }
      final duration = await audio.inspect(pending!.path);
      final record = AudioRecord(
        id: recordId,
        name: 'কৃত্রিম কণ্ঠ ${history.length + 1}',
        wavPath: pending!.path,
        profileName: profile.name,
        language: lang,
        text: content,
        createdAt: DateTime.now(),
        durationSeconds: duration,
      );
      history = [record, ...history];
      try {
        await _save();
      } catch (_) {
        history.removeWhere((r) => r.id == recordId);
        rethrow;
      }
      latest = record;
      pending = null;
      progress = 1;
      status = 'কৃত্রিম কণ্ঠ তৈরি ও সংরক্ষণ হয়েছে।';
    });
    if (pending != null) {
      await _guard(() => store.deleteAudio(pending!.path));
    }
    if (_cancelled) {
      error = '';
    }
    final client = _active, id = _jobId;
    if (client != null && id != null) {
      try {
        await client.cancelJob(id);
      } catch (_) {
        error =
            'ফোনে কাজ শেষ; সার্ভারের অস্থায়ী তথ্য মুছতে সংযোগ পরীক্ষা করুন।';
      }
    }
    client?.close();
    _active = null;
    _jobId = null;
    if (_cancelled) {
      status = 'কাজ বাতিল হয়েছে।';
    }
    busy = false;
    notifyListeners();
  }

  Future<void> cancel() async {
    _cancelled = true;
    status = 'বাতিল করা হচ্ছে…';
    notifyListeners();
    final id = _jobId, client = _active;
    if (id != null && client != null) {
      await _guard(() => client.cancelJob(id));
    }
  }

  Future<void> renameRecord(AudioRecord r, String name) => _guard(() async {
    final old = history;
    history = [
      for (final x in history)
        if (x.id == r.id) x.copyWith(name: validateName(name)) else x,
    ];
    try {
      await _save();
    } catch (_) {
      history = old;
      rethrow;
    }
    if (latest?.id == r.id) {
      latest = history.firstWhere((x) => x.id == r.id);
    }
  });
  Future<void> deleteRecord(AudioRecord r) => _guard(() async {
    final old = history;
    history = history.where((x) => x.id != r.id).toList();
    try {
      await _save();
    } catch (_) {
      history = old;
      rethrow;
    }
    await store.deleteAudio(r.wavPath);
    await store.write(_snapshot());
    if (latest?.id == r.id) {
      latest = null;
    }
  });
  Future<void> shareRecord(AudioRecord r) => _guard(() async {
    await SharePlus.instance.share(
      ShareParams(
        files: [XFile(r.wavPath, mimeType: 'audio/wav')],
        text: 'কৃত্রিমভাবে তৈরি কণ্ঠ — ${r.name}',
      ),
    );
  });
  Future<void> exportRecord(
    AudioRecord r, {
    required String format,
  }) => _guard(() async {
    if (!['wav', 'mp3'].contains(format)) {
      throw const StudioException('এই রপ্তানি ধরন সমর্থিত নয়।');
    }
    File? converted;
    final transport = NoRedirectClient(http.Client());
    try {
      var source = File(r.wavPath);
      if (format == 'mp3') {
        final client = _client();
        converted = File(store.audioPath(newId(), 'mp3'));
        try {
          final request = http.MultipartRequest('POST', client.uri('convert'))
            ..headers.addAll(client.headers)
            ..files.add(await http.MultipartFile.fromPath('audio', r.wavPath));
          // Conversion sends generated synthetic audio only; UI asks authorization.
          final response = await transport
              .send(request)
              .timeout(const Duration(seconds: 120));
          if (response.statusCode != 200) {
            throw const StudioException(
              'সার্ভারে MP3 রূপান্তর হয়নি। WAV রপ্তানি করতে পারেন।',
            );
          }
          var size = 0;
          final sink = converted.openWrite();
          try {
            await for (final chunk in response.stream.timeout(
              const Duration(seconds: 60),
            )) {
              size += chunk.length;
              if (size > 100 * 1024 * 1024) {
                throw const StudioException('রপ্তানি ফাইল অতিরিক্ত বড়।');
              }
              sink.add(chunk);
            }
          } finally {
            await sink.close();
          }
          source = converted;
        } finally {
          client.close();
        }
      }
      if (await source.length() > 100 * 1024 * 1024) {
        throw const StudioException('রপ্তানি ফাইল অতিরিক্ত বড়।');
      }
      final destination = await FilePicker.platform.saveFile(
        dialogTitle: 'অডিও সংরক্ষণ',
        fileName: 'synthetic-${r.id}.$format',
        type: FileType.custom,
        allowedExtensions: [format],
        bytes: await source.readAsBytes(),
      );
      if (destination != null) {
        status = 'অডিও রপ্তানি হয়েছে।';
      }
    } finally {
      transport.close();
      if (converted != null) {
        await store.deleteAudio(converted.path);
      }
    }
  });
  Future<void> refreshModels() => _guard(() async {
    final client = _client();
    try {
      final data = await client.getJson('models');
      models = (data['models'] as List? ?? [])
          .map((j) => Map<String, dynamic>.from(j as Map))
          .toList();
    } finally {
      client.close();
    }
  });
  Future<Map<String, dynamic>?> planModel(String id) async {
    Map<String, dynamic>? plan;
    await _guard(() async {
      final c = _client();
      try {
        plan = await c.postJson('models/${c.safeId(id)}/plan');
      } finally {
        c.close();
      }
    });
    return plan;
  }

  Future<void> downloadModel(String id) => _guard(() async {
    final c = _client();
    try {
      await c.postBody('models/${c.safeId(id)}/install', {
        'accept_license': true,
        'accept_remote_code': true,
      });
      status = 'সার্ভারে মডেল নামানো শুরু হয়েছে।';
    } finally {
      c.close();
    }
    await refreshModels();
  });
  Future<void> removeModel(String id) => _guard(() async {
    final c = _client();
    try {
      await c.deleteJson('models/${c.safeId(id)}');
    } finally {
      c.close();
    }
    await refreshModels();
  });
  Future<void> cancelModel(String id) => removeModel(id);
  Future<void> checkForUpdate() => _guard(() async {
    final response = await http
        .get(
          Uri.https(
            'api.github.com',
            '/repos/reazempiree/ai-voice-studio-by-reaz/releases/latest',
          ),
          headers: {'Accept': 'application/vnd.github+json'},
        )
        .timeout(const Duration(seconds: 15));
    if (response.statusCode == 404) {
      status = 'এখনও প্রকাশিত সংস্করণ নেই।';
      return;
    }
    if (response.statusCode != 200) {
      throw const StudioException('নতুন সংস্করণ পরীক্ষা করা যায়নি।');
    }
    final j = jsonDecode(response.body) as Map<String, dynamic>;
    final tag = j['tag_name'] as String;
    final installed =
        await AudioService.channel.invokeMethod<String>('version') ?? '0.1.0';
    final newer = isNewerVersion(tag, installed);
    if (newer) {
      updateUrl =
          'https://github.com/reazempiree/ai-voice-studio-by-reaz/releases/latest';
      status = 'নতুন সংস্করণ পাওয়া গেছে।';
    } else {
      updateUrl = null;
      status = 'আপনি বর্তমান সংস্করণ ব্যবহার করছেন।';
    }
  });
  Future<void> openUpdate() => _guard(() async {
    if (updateUrl != null &&
        !await launchUrl(
          Uri.parse(updateUrl!),
          mode: LaunchMode.externalApplication,
        )) {
      throw const StudioException('ডাউনলোড পাতা খোলা যায়নি।');
    }
  });
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && _loaded) {
      _textSaveTimer?.cancel();
      unawaited(_guard(_save));
    }
  }

  Future<void> flush() async {
    _textSaveTimer?.cancel();
    await _guard(_save);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _textSaveTimer?.cancel();
    _disposed = true;
    _cancelled = true;
    _active?.close();
    super.dispose();
  }
}
