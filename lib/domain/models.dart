import 'dart:convert';

class StudioException implements Exception {
  const StudioException(this.message);
  final String message;
  @override
  String toString() => message;
}

class VoiceProfile {
  const VoiceProfile({
    required this.id,
    required this.name,
    required this.path,
    required this.referenceText,
    required this.createdAt,
    required this.durationSeconds,
  });
  final String id, name, path, referenceText;
  final DateTime createdAt;
  final double durationSeconds;
  VoiceProfile copyWith({
    String? name,
    String? path,
    String? referenceText,
    double? durationSeconds,
  }) => VoiceProfile(
    id: id,
    name: name ?? this.name,
    path: path ?? this.path,
    referenceText: referenceText ?? this.referenceText,
    createdAt: createdAt,
    durationSeconds: durationSeconds ?? this.durationSeconds,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'path': path,
    'referenceText': referenceText,
    'createdAt': createdAt.toIso8601String(),
    'durationSeconds': durationSeconds,
  };
  factory VoiceProfile.fromJson(Map<String, dynamic> j) => VoiceProfile(
    id: j['id'] as String,
    name: j['name'] as String,
    path: j['path'] as String,
    referenceText: j['referenceText'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    durationSeconds: (j['durationSeconds'] as num).toDouble(),
  );
}

class AudioRecord {
  const AudioRecord({
    required this.id,
    required this.name,
    required this.wavPath,
    required this.profileName,
    required this.language,
    required this.text,
    required this.createdAt,
    required this.durationSeconds,
  });
  final String id, name, wavPath, profileName, language, text;
  final DateTime createdAt;
  final double durationSeconds;
  AudioRecord copyWith({String? name}) => AudioRecord(
    id: id,
    name: name ?? this.name,
    wavPath: wavPath,
    profileName: profileName,
    language: language,
    text: text,
    createdAt: createdAt,
    durationSeconds: durationSeconds,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'wavPath': wavPath,
    'profileName': profileName,
    'language': language,
    'text': text,
    'createdAt': createdAt.toIso8601String(),
    'durationSeconds': durationSeconds,
  };
  factory AudioRecord.fromJson(Map<String, dynamic> j) => AudioRecord(
    id: j['id'] as String,
    name: j['name'] as String,
    wavPath: j['wavPath'] as String,
    profileName: j['profileName'] as String,
    language: j['language'] as String,
    text: j['text'] as String,
    createdAt: DateTime.parse(j['createdAt'] as String),
    durationSeconds: (j['durationSeconds'] as num).toDouble(),
  );
}

class BackendCapabilities {
  const BackendCapabilities({
    required this.available,
    required this.languages,
    required this.reason,
    required this.raw,
  });
  final bool available;
  final List<String> languages;
  final String reason;
  final Map<String, dynamic> raw;
  factory BackendCapabilities.fromJson(Map<String, dynamic> j) =>
      BackendCapabilities(
        available: j['available'] == true,
        languages: (j['languages'] as List? ?? []).cast<String>(),
        reason: j['reason']?.toString() ?? '',
        raw: j,
      );
}

String validateName(String value) {
  final name = value.trim();
  if (name.isEmpty || name.length > 80) {
    throw const StudioException('নাম ১ থেকে ৮০ অক্ষরের মধ্যে লিখুন।');
  }
  return name;
}

String validateText(String value) {
  final text = value.trim();
  if (text.isEmpty) {
    throw const StudioException('আগে কিছু লেখা লিখুন।');
  }
  if (text.runes.length > 3000) {
    throw const StudioException('একবারে সর্বোচ্চ ৩০০০ অক্ষর ব্যবহার করুন।');
  }
  return text;
}

String encodeState(Map<String, dynamic> state) =>
    jsonEncode({'schema': 1, ...state});
