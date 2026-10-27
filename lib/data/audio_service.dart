import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';
import '../domain/models.dart';
import 'local_store.dart';

class ImportedAudio {
  const ImportedAudio(this.path, this.durationSeconds);
  final String path;
  final double durationSeconds;
}

class AudioService {
  AudioService(this.store);
  final LocalStore store;
  static const channel = MethodChannel('studio.reaz/audio');
  Future<ImportedAudio?> import() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['wav', 'mp3', 'm4a'],
      withData: false,
    );
    if (result == null) {
      return null;
    }
    final source = result.files.single.path;
    if (source == null) {
      throw const StudioException('রেকর্ডিংটি খোলা যাচ্ছে না।');
    }
    final ext = source.split('.').last.toLowerCase();
    if (!['wav', 'mp3', 'm4a'].contains(ext)) {
      throw const StudioException('শুধু WAV, MP3 অথবা M4A নির্বাচন করুন।');
    }
    final file = File(source);
    final size = await file.length();
    if (size == 0 || size > 25 * 1024 * 1024) {
      throw const StudioException('রেকর্ডিংটি খালি অথবা ২৫ মেগাবাইটের বেশি।');
    }
    final path = store.audioPath(newId(), ext);
    await file.copy(path);
    try {
      final cleared = await FilePicker.platform.clearTemporaryFiles();
      if (cleared == false) {
        throw const StudioException(
          'ফাইল বাছাইয়ের অস্থায়ী তথ্য মুছতে অ্যাপ আবার খুলুন।',
        );
      }
    } catch (_) {
      await store.deleteAudio(path);
      rethrow;
    }
    try {
      final duration = await inspect(path);
      if (duration < 3 || duration > 30) {
        throw const StudioException(
          '৩ থেকে ৩০ সেকেন্ডের পরিষ্কার রেকর্ডিং দিন।',
        );
      }
      return ImportedAudio(path, duration);
    } catch (_) {
      await store.deleteAudio(path);
      rethrow;
    }
  }

  Future<double> inspect(String path) async {
    try {
      final result = await channel.invokeMapMethod<String, dynamic>('inspect', {
        'path': path,
      });
      final seconds = (result?['durationSeconds'] as num?)?.toDouble() ?? 0;
      if (seconds <= 0) {
        throw const StudioException('রেকর্ডিংটি খালি অথবা নষ্ট।');
      }
      return seconds;
    } on PlatformException {
      throw const StudioException('অডিও ডিকোড করা যায়নি। অন্য রেকর্ডিং দিন।');
    }
  }
}
