import 'dart:async';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

import '../domain/models.dart';

/// Versioned, user-initiated model installation. No download occurs at startup.
class PocketModelStore {
  PocketModelStore(this.root);

  final Directory root;
  static const label = 'Pocket TTS · ইংরেজি · ফোনে প্রক্রিয়াকরণ';
  static const license =
      'Pocket কোড MIT; sherpa-onnx Apache-2.0; ওজনের সঙ্গে CC-BY-4.0 লাইসেন্স এবং ব্যক্তিগত/অবাণিজ্যিক ব্যবহারের নির্দেশনা রয়েছে।';
  static const modelVersion = 'sherpa-onnx-pocket-tts-int8-2026-01-26';
  static const totalDownloadBytes = 98336520;
  static const installedModelBytes = 198310873;
  static const archiveSha256 =
      '2f3b88823cbbb9bf0b2477ec8ae7b3fec417b3a87b6bb5f256dba66f2ad967cb';
  static const downloadUrl =
      'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/$modelVersion.tar.bz2';
  static const attributionUrl = 'https://github.com/kyutai-labs/pocket-tts';

  bool ready = false;
  bool busy = false;
  double progress = 0;
  String status = '', error = '';
  void Function()? onChanged;
  bool _cancelled = false;
  http.Client? _client;
  Isolate? _extractor;
  Completer<void>? _completion;

  String get modelDirectory => '${root.path}/$modelVersion';
  File get _archive => File('${root.path}/$modelVersion.tar.bz2');
  File get _partial => File('${root.path}/$modelVersion.tar.bz2.partial');
  Directory get _staging => Directory('${root.path}/$modelVersion.installing');

  void _notify() => onChanged?.call();

  /// Streamed hashes detect missing, truncated and modified installed models.
  Future<void> inspect() async {
    if (busy) return;
    ready = await _verifyPocketFiles(modelDirectory);
    status = ready
        ? 'ফোনের ইংরেজি মডেল প্রস্তুত।'
        : 'ফোনের ইংরেজি মডেল নামানো প্রয়োজন।';
    _notify();
  }

  /// Call only after the UI presents size/license and obtains explicit consent.
  Future<void> download() async {
    if (busy) return;
    busy = true;
    ready = false;
    progress = 0;
    error = '';
    _cancelled = false;
    final completion = Completer<void>();
    _completion = completion;
    _notify();
    try {
      await root.create(recursive: true);
      if (!await _validArchive()) {
        _checkCancelled();
        await _downloadArchive();
      }
      _checkCancelled();
      status = 'ডাউনলোড যাচাই হয়েছে। ফোনে মডেল স্থাপন করা হচ্ছে…';
      progress = 1;
      _notify();
      if (await _staging.exists()) await _staging.delete(recursive: true);
      await _staging.create();
      await _extract();
      _checkCancelled();
      final target = Directory(modelDirectory);
      if (await target.exists()) await target.delete(recursive: true);
      await _staging.rename(target.path);
      ready = await _verifyPocketFiles(target.path);
      if (!ready) {
        throw const StudioException('মডেলের যাচাই মেলেনি। আবার নামান।');
      }
      // Installed models retain their source README and license. The large
      // archive is no longer needed; a failed extraction can reuse it on retry.
      if (await _archive.exists()) await _archive.delete();
      status =
          'ফোনের ইংরেজি মডেল প্রস্তুত। এখন ইন্টারনেট ছাড়াই তৈরি করতে পারবেন।';
    } on FileSystemException catch (e) {
      error = e.osError?.errorCode == 28
          ? 'মডেল স্থাপনের জায়গা নেই। অন্তত ৬০০ মেগাবাইট খালি করে আবার চেষ্টা করুন।'
          : 'মডেল ফাইল সংরক্ষণ করা যায়নি। জায়গা এবং ফাইলের অনুমতি পরীক্ষা করুন।';
    } on StudioException catch (e) {
      if (!_cancelled) error = e.message;
    } on TimeoutException {
      error = 'মডেল নামানোর সময় শেষ। সংযোগ ঠিক করে আবার চেষ্টা করুন।';
    } catch (_) {
      if (!_cancelled) {
        error =
            'মডেল নামানো বা স্থাপন করা যায়নি। সংযোগ ঠিক করে আবার চেষ্টা করুন।';
      }
    } finally {
      _client?.close();
      _client = null;
      _extractor?.kill(priority: Isolate.immediate);
      _extractor = null;
      try {
        if (await _staging.exists()) await _staging.delete(recursive: true);
        final tar = File('${root.path}/$modelVersion.tar');
        if (await tar.exists()) await tar.delete();
      } on FileSystemException {
        error = 'অস্থায়ী মডেল ফাইল মুছতে অ্যাপ আবার খুলুন।';
      } finally {
        if (_cancelled) status = 'মডেল নামানো বা স্থাপন বাতিল হয়েছে।';
        busy = false;
        completion.complete();
        _completion = null;
        _notify();
      }
    }
  }

  Future<bool> _validArchive() async {
    if (!await _archive.exists()) return false;
    if (await _archive.length() != totalDownloadBytes) {
      await _archive.delete();
      return false;
    }
    final digest = await sha256.bind(_archive.openRead()).first;
    if (digest.toString() == archiveSha256) return true;
    await _archive.delete();
    return false;
  }

  Future<void> _downloadArchive() async {
    var offset = await _partial.exists() ? await _partial.length() : 0;
    if (offset >= totalDownloadBytes) {
      await _partial.delete();
      offset = 0;
    }
    status = 'ইংরেজির মডেল নামানো হচ্ছে…';
    _notify();
    _checkCancelled();
    final client = http.Client();
    _client = client;
    final request = http.Request('GET', Uri.parse(downloadUrl));
    if (offset > 0) request.headers['Range'] = 'bytes=$offset-';
    final response = await client
        .send(request)
        .timeout(const Duration(seconds: 30));
    _checkCancelled();
    if (response.statusCode == 206) {
      if (!(response.headers['content-range'] ?? '').startsWith(
            'bytes $offset-',
          ) ||
          !(response.headers['content-range'] ?? '').endsWith(
            '/$totalDownloadBytes',
          )) {
        throw const StudioException(
          'ডাউনলোডের খণ্ড সঠিক নয়। আবার চেষ্টা করুন।',
        );
      }
    } else if (response.statusCode == 200) {
      offset = 0;
    } else {
      throw StudioException(
        'মডেল নামানো যায়নি (${response.statusCode})। পরে আবার চেষ্টা করুন।',
      );
    }
    final sink = _partial.openWrite(
      mode: offset > 0 ? FileMode.append : FileMode.write,
    );
    var received = offset;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        _checkCancelled();
        received += chunk.length;
        if (received > totalDownloadBytes) {
          throw const StudioException('মডেল ডাউনলোডের আকার সঠিক নয়।');
        }
        sink.add(chunk);
        progress = received / totalDownloadBytes;
        _notify();
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    _checkCancelled();
    if (received != totalDownloadBytes) {
      throw const StudioException(
        'ডাউনলোড অসম্পূর্ণ। আবার চেষ্টা করলে বাকি অংশ নামবে।',
      );
    }
    status = 'মডেলের SHA-256 যাচাই করা হচ্ছে…';
    _notify();
    final digest = await sha256.bind(_partial.openRead()).first;
    _checkCancelled();
    if (digest.toString() != archiveSha256) {
      await _partial.delete();
      throw const StudioException('মডেলের নিরাপত্তা যাচাই মেলেনি। আবার নামান।');
    }
    await _partial.rename(_archive.path);
  }

  Future<void> _extract() async {
    _checkCancelled();
    final port = ReceivePort();
    try {
      _extractor = await Isolate.spawn(
        _extractPocketArchive,
        [
          port.sendPort,
          _archive.path,
          _staging.path,
          '${root.path}/$modelVersion.tar',
        ],
        onExit: port.sendPort,
        onError: port.sendPort,
      );
      _checkCancelled();
      final result = await port.first;
      if (result != 'ready') {
        _checkCancelled();
        throw const StudioException(
          'মডেল খোলা বা যাচাই করা যায়নি। আবার নামান।',
        );
      }
    } finally {
      port.close();
      _extractor?.kill(priority: Isolate.immediate);
      _extractor = null;
    }
  }

  void _checkCancelled() {
    if (_cancelled) throw const StudioException('মডেল স্থাপন বাতিল হয়েছে।');
  }

  Future<void> cancel() async {
    if (!busy) return;
    _cancelled = true;
    _client?.close();
    _extractor?.kill(priority: Isolate.immediate);
    await _completion?.future;
  }

  Future<void> remove() async {
    if (busy) await cancel();
    for (final path in [modelDirectory, _staging.path]) {
      final directory = Directory(path);
      if (await directory.exists()) await directory.delete(recursive: true);
    }
    for (final file in [
      _archive,
      _partial,
      File('${root.path}/$modelVersion.tar'),
    ]) {
      if (await file.exists()) await file.delete();
    }
    ready = false;
    progress = 0;
    error = '';
    status = 'ফোনের ইংরেজি মডেল মুছে ফেলা হয়েছে।';
    _notify();
  }
}

// Derived from the verified, immutable release archive above. None are guesses.
const _pocketFiles = <String, (int, String)>{
  'lm_main.int8.onnx': (
    76341079,
    'bfc0c7e7e3d72864fa3bb2ee499f62f21ddc1474b885f5f3ca570f8be73e787e',
  ),
  'lm_flow.int8.onnx': (
    9962530,
    '8d627d235c44a597da908e1085ebe241cbbe358964c502c5a5063d18851a5529',
  ),
  'encoder.onnx': (
    72713165,
    'e8f2f6d301ffb96e398b138a7dc6d3038622d236044636b73d920bab85890260',
  ),
  'decoder.int8.onnx': (
    22693618,
    '12b0857402d31aead94df19d6783b4350d1f740e811f3a3202c70ad89ae11eea',
  ),
  'text_conditioner.onnx': (
    16388343,
    '0b84e837d7bfaf2c896627b03e3f080320309f37f4fc7df7698c644f7ba5e6b1',
  ),
  'vocab.json': (
    69478,
    '6fb646346cf931016f70c4921aab0900ce7a304b893cb02135c74e294abfea01',
  ),
  'token_scores.json': (
    123616,
    '5be2f278caf9b9800741f0fd82bff677f4943ec764c356f907213434b622d958',
  ),
  'LICENSE': (
    18655,
    'fe7b4ce83b8381cc5b216bbb4af73c570688d1b819c73bbaed8ca401f4677cd6',
  ),
  'README.md': (
    389,
    '2d05e627fe4fa3c625e822efcd20ad2ca62eb3b4fc1d67ae2625cb106b4f689c',
  ),
};

Future<bool> _verifyPocketFiles(String directory) async {
  try {
    for (final entry in _pocketFiles.entries) {
      final file = File('$directory/${entry.key}');
      if (await FileSystemEntity.type(file.path, followLinks: false) !=
              FileSystemEntityType.file ||
          await file.length() != entry.value.$1) {
        return false;
      }
      if ((await sha256.bind(file.openRead()).first).toString() !=
          entry.value.$2) {
        return false;
      }
    }
    return true;
  } on FileSystemException {
    return false;
  }
}

void _extractPocketArchive(List<Object> arguments) async {
  final port = arguments[0] as SendPort;
  final archivePath = arguments[1] as String;
  final destination = arguments[2] as String;
  final tarPath = arguments[3] as String;
  try {
    final source = InputFileStream(archivePath);
    final output = _LimitedOutput(tarPath, 256 * 1024 * 1024);
    try {
      if (!BZip2Decoder().decodeStream(source, output, verify: true)) {
        throw const FormatException('Invalid bzip2 checksum');
      }
    } finally {
      source.closeSync();
      output.closeSync();
    }
    final input = InputFileStream(tarPath);
    try {
      final archive = TarDecoder().decodeStream(input);
      var total = 0;
      final seen = <String>{};
      for (final entry in archive) {
        final parts = entry.name.split('/');
        if (parts.first != PocketModelStore.modelVersion ||
            parts.contains('..') ||
            entry.name.contains('\\') ||
            entry.isSymbolicLink) {
          throw const FormatException('Unsafe model entry');
        }
        total += entry.size;
        if (total > 256 * 1024 * 1024) {
          throw const FormatException('Archive too large');
        }
        if (!entry.isFile || parts.length != 2) continue;
        final name = parts.last;
        final expected = _pocketFiles[name];
        if (expected == null) continue;
        if (entry.size != expected.$1 || !seen.add(name)) {
          throw const FormatException('Unexpected model entry size');
        }
        final file = OutputFileStream('$destination/$name');
        try {
          entry.writeContent(file);
        } finally {
          file.closeSync();
        }
      }
    } finally {
      input.closeSync();
    }
    if (!await _verifyPocketFiles(destination)) {
      throw const FormatException('Invalid installed model');
    }
    port.send('ready');
  } catch (_) {
    port.send('failed');
  }
}

class _LimitedOutput extends OutputStream {
  _LimitedOutput(String path, this.limit)
    : inner = OutputFileStream(path),
      super(byteOrder: ByteOrder.littleEndian);
  final OutputFileStream inner;
  final int limit;
  int count = 0;
  @override
  int get length => count;
  @override
  void writeByte(int value) {
    if (++count > limit) {
      throw const FormatException('Archive expansion limit exceeded');
    }
    inner.writeByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    count += length ?? bytes.length;
    if (count > limit) {
      throw const FormatException('Archive expansion limit exceeded');
    }
    inner.writeBytes(bytes, length: length);
  }

  @override
  void writeStream(InputStream stream) {
    while (!stream.isEOS) {
      final size = stream.length > 65536 ? 65536 : stream.length;
      writeBytes(stream.readBytes(size).toUint8List());
    }
  }

  @override
  void flush() => inner.flush();
  @override
  void closeSync() => inner.closeSync();
  @override
  Future<void> close() => inner.close();
  @override
  void clear() => throw UnsupportedError('Cannot clear extraction output');
  @override
  Uint8List subset(int start, [int? end]) =>
      throw UnsupportedError('File-backed output');
}
