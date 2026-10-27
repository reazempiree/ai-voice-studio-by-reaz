import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../domain/models.dart';

Uri validateBackendUrl(String input) {
  final uri = Uri.tryParse(input.trim());
  if (uri == null ||
      !['http', 'https'].contains(uri.scheme) ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      uri.hasQuery ||
      uri.hasFragment ||
      (uri.path.isNotEmpty && uri.path != '/')) {
    throw const StudioException(
      'সঠিক সার্ভার ঠিকানা দিন, যেমন https://voice.local:8443',
    );
  }
  final ip = InternetAddress.tryParse(uri.host);
  final bytes = ip?.rawAddress;
  final privateV4 =
      bytes != null &&
      bytes.length == 4 &&
      (bytes[0] == 10 ||
          bytes[0] == 127 ||
          (bytes[0] == 192 && bytes[1] == 168) ||
          (bytes[0] == 172 && bytes[1] >= 16 && bytes[1] <= 31));
  if (uri.scheme == 'http' &&
      !(privateV4 || uri.host == 'localhost' || uri.host.endsWith('.local'))) {
    throw const StudioException(
      'ইন্টারনেট সার্ভারের জন্য HTTPS আবশ্যক। স্থানীয় নেটওয়ার্কে HTTP ব্যবহার করা যায়।',
    );
  }
  return uri.replace(path: '');
}

abstract interface class InferenceAdapter {
  Future<BackendCapabilities> capabilities();
  Future<Map<String, dynamic>> createJob({
    required VoiceProfile profile,
    required String text,
    required String language,
  });
  Future<Map<String, dynamic>> job(String id);
  Future<void> cancelJob(String id);
  Future<void> downloadAudio(String id, File target, {String format = 'wav'});
  void close();
}

class NoRedirectClient extends http.BaseClient {
  NoRedirectClient(this.inner);
  final http.Client inner;
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.followRedirects = false;
    return inner.send(request);
  }

  @override
  void close() => inner.close();
}

class InferenceClient implements InferenceAdapter {
  InferenceClient(String url, this.token, {http.Client? client})
    : base = validateBackendUrl(url),
      _client = NoRedirectClient(client ?? http.Client());
  final Uri base;
  final String token;
  final http.Client _client;
  Map<String, String> get headers => {'Authorization': 'Bearer $token'};
  Uri uri(String path, [Map<String, String>? query]) =>
      base.replace(path: '/v1/$path', queryParameters: query);
  String safeId(String id) {
    if (!RegExp(r'^[A-Za-z0-9_-]{1,100}$').hasMatch(id)) {
      throw const StudioException('সার্ভারের পরিচয় সঠিক নয়।');
    }
    return id;
  }

  Map<String, dynamic> decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      if (response.statusCode == 401 || response.statusCode == 403) {
        throw const StudioException(
          'সার্ভারের প্রবেশ সংকেত অথবা অনুমতি পরীক্ষা করুন।',
        );
      }
      if (response.statusCode == 503) {
        throw const StudioException(
          'মডেল প্রস্তুত নেই। সার্ভারের মডেল ব্যবস্থাপনা দেখুন।',
        );
      }
      if (response.statusCode == 413) {
        throw const StudioException('রেকর্ডিং অথবা লেখা অতিরিক্ত বড়।');
      }
      throw StudioException(
        'সার্ভার অনুরোধ ব্যর্থ হয়েছে (${response.statusCode})।',
      );
    }
    final data = jsonDecode(utf8.decode(response.bodyBytes));
    if (data is! Map<String, dynamic>) {
      throw const StudioException('সার্ভারের উত্তর সঠিক নয়।');
    }
    return data;
  }

  Future<Map<String, dynamic>> getJson(String path) async => decode(
    await _client
        .get(uri(path), headers: headers)
        .timeout(const Duration(seconds: 20)),
  );
  Future<Map<String, dynamic>> postBody(
    String path,
    Map<String, dynamic> body,
  ) async => decode(
    await _client
        .post(
          uri(path),
          headers: {...headers, 'Content-Type': 'application/json'},
          body: jsonEncode(body),
        )
        .timeout(const Duration(seconds: 30)),
  );
  Future<Map<String, dynamic>> postJson(String path) async => decode(
    await _client
        .post(uri(path), headers: headers)
        .timeout(const Duration(seconds: 30)),
  );
  Future<Map<String, dynamic>> deleteJson(String path) async => decode(
    await _client
        .delete(uri(path), headers: headers)
        .timeout(const Duration(seconds: 20)),
  );
  @override
  Future<BackendCapabilities> capabilities() async =>
      BackendCapabilities.fromJson(await getJson('capabilities'));
  @override
  Future<Map<String, dynamic>> createJob({
    required VoiceProfile profile,
    required String text,
    required String language,
  }) async {
    final request = http.MultipartRequest('POST', uri('jobs'))
      ..headers.addAll(headers)
      ..fields.addAll({
        'text': text,
        'language': language,
        'reference_text': profile.referenceText,
        'consent': 'true',
      })
      ..files.add(await http.MultipartFile.fromPath('audio', profile.path));
    return decode(
      await http.Response.fromStream(
        await _client.send(request).timeout(const Duration(seconds: 90)),
      ),
    );
  }

  @override
  Future<Map<String, dynamic>> job(String id) => getJson('jobs/${safeId(id)}');
  @override
  Future<void> cancelJob(String id) async {
    final response = await _client
        .delete(uri('jobs/${safeId(id)}'), headers: headers)
        .timeout(const Duration(seconds: 20));
    // Expired and already-cancelled jobs have already been removed server-side.
    if (response.statusCode != 404) {
      decode(response);
    }
  }

  @override
  Future<void> downloadAudio(
    String id,
    File target, {
    String format = 'wav',
  }) async {
    final request = http.Request(
      'GET',
      uri('jobs/${safeId(id)}/audio', {'format': format}),
    )..headers.addAll(headers);
    final response = await _client
        .send(request)
        .timeout(const Duration(seconds: 30));
    if (response.statusCode != 200) {
      throw const StudioException('অডিও নামানো যায়নি।');
    }
    final sink = target.openWrite();
    var size = 0;
    try {
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 60),
      )) {
        size += chunk.length;
        if (size > 100 * 1024 * 1024) {
          throw const StudioException('অডিও ১০০ মেগাবাইটের সীমা ছাড়িয়েছে।');
        }
        sink.add(chunk);
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (size < 44) {
      throw const StudioException('সার্ভার খালি অডিও পাঠিয়েছে।');
    }
  }

  @override
  void close() => _client.close();
}
