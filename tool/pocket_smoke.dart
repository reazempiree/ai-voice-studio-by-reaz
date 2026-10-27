import 'dart:io';
import 'dart:convert';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import 'package:ai_voice_studio/data/pocket_engine.dart';
import 'package:ai_voice_studio/domain/models.dart';

Future<void> main(List<String> args) async {
  if (args.length < 3 || args.length > 4) {
    throw ArgumentError('models reference.wav output.wav');
  }
  sherpa.initBindings();
  final wave = sherpa.readWave(args[1]);
  final limit = wave.sampleRate * 12;
  final reference = ReferenceWave(
    wave.samples.sublist(
      0,
      wave.samples.length > limit ? limit : wave.samples.length,
    ),
    wave.sampleRate,
  );
  final timer = Stopwatch()..start();
  final engine = PocketEngine();
  if (args.length == 4 && args[3] == 'cancel') {
    var cancelled = false;
    try {
      await engine.generate(
        modelDirectory: args[0],
        reference: reference,
        text: 'This generation must be cancelled.',
        outputPath: args[2],
        onProgress: (_) => engine.cancel(),
      );
    } on StudioException {
      cancelled = true;
    }
    if (!cancelled || engine.running || await File(args[2]).exists()) {
      throw StateError('Cancellation failed');
    }
    stdout.writeln(
      jsonEncode({
        'real_native_cancellation': true,
        'wallSeconds': timer.elapsedMilliseconds / 1000,
      }),
    );
    return;
  }
  final duration = await engine.generate(
    modelDirectory: args[0],
    reference: reference,
    text: 'This is real offline speech using the reference voice.',
    outputPath: args[2],
  );
  stdout.writeln(
    jsonEncode({
      'engine': 'Pocket int8 via exact Dart app worker',
      'duration': duration,
      'wallSeconds': timer.elapsedMilliseconds / 1000,
      'bytes': await File(args[2]).length(),
      'peakRssBytes': ProcessInfo.maxRss,
      'reference': args[1],
    }),
  );
}
