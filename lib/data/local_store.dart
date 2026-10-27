import 'dart:convert';
import 'dart:io';
import 'dart:math';
import '../domain/models.dart';

String newId() => List.generate(
  16,
  (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
).join();

class LocalStore {
  LocalStore(this.root);
  final Directory root;
  File get index => File('${root.path}/library.json');
  File get backup => File('${root.path}/library.backup.json');
  Future<void> initialize() async {
    await root.create(recursive: true);
    await Directory('${root.path}/audio').create(recursive: true);
  }

  String audioPath(String id, String extension) {
    if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(id) ||
        !['mp3', 'wav', 'm4a'].contains(extension)) {
      throw const StudioException('ফাইলের ঠিকানা সঠিক নয়।');
    }
    return '${root.path}/audio/$id.$extension';
  }

  bool ownsPath(String path) => RegExp(
    '^${RegExp.escape(root.path)}'
    r'/audio/[a-f0-9]{32}\.(wav|mp3|m4a)$',
  ).hasMatch(path);
  Future<Map<String, dynamic>> read() async {
    if (!await index.exists() && !await backup.exists()) {
      return {};
    }
    for (final file in [index, backup]) {
      try {
        final data =
            jsonDecode(await file.readAsString()) as Map<String, dynamic>;
        if (data['schema'] != 1) {
          continue;
        }
        // Only locally managed paths may be opened or removed from persisted data.
        for (final p in data['profiles'] as List? ?? []) {
          if (!ownsPath(p['path'] as String)) {
            throw const FormatException();
          }
        }
        for (final p in data['history'] as List? ?? []) {
          if (!ownsPath(p['wavPath'] as String)) {
            throw const FormatException();
          }
        }
        return data;
      } on FileSystemException {
        continue;
      } on FormatException {
        continue;
      } on TypeError {
        continue;
      }
    }
    throw const StudioException(
      'স্থানীয় তথ্য পড়া যাচ্ছে না। তথ্য মুছে ফেলা হয়নি; সংরক্ষণাগার পরীক্ষা করুন।',
    );
  }

  Future<void> write(Map<String, dynamic> state) async {
    final temporary = File('${root.path}/library.next.json');
    await temporary.writeAsString(encodeState(state), flush: true);
    if (await index.exists()) {
      await index.copy(backup.path);
    }
    await temporary.rename(index.path);
  }

  Future<void> deleteAudio(String path) async {
    if (!ownsPath(path)) {
      throw const StudioException('অনিরাপদ ফাইলের ঠিকানা।');
    }
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
  }
}
