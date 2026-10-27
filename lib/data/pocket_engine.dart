import 'dart:async';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';
import 'package:ffi/ffi.dart';
import 'package:sherpa_onnx/sherpa_onnx.dart' as sherpa;
import '../domain/models.dart';

class ReferenceWave {
  const ReferenceWave(this.samples, this.sampleRate);
  final Float32List samples;
  final int sampleRate;
}

/// Native ONNX inference runs in a worker, never on Flutter's UI isolate.
/// Cancellation is cooperative: native callbacks observe a shared byte and the
/// worker frees its native engine before the parent frees that byte.
class PocketEngine {
  Pointer<Uint8>? _cancelFlag;
  bool get running => _cancelFlag != null;
  void cancel() {
    _cancelFlag?.value = 1;
  }

  Future<double> generate({
    required String modelDirectory,
    required ReferenceWave reference,
    required String text,
    required String outputPath,
    void Function(double)? onProgress,
    int seed = 42,
  }) async {
    if (running) {
      throw const StudioException('একটি কাজ চলছে। আগে সেটি শেষ করুন।');
    }
    if (reference.sampleRate < 8000 ||
        reference.sampleRate > 192000 ||
        reference.samples.isEmpty ||
        reference.samples.length > reference.sampleRate * 12) {
      throw const StudioException('কণ্ঠের নমুনা সঠিক নয়।');
    }
    final flag = calloc<Uint8>();
    _cancelFlag = flag;
    final messages = ReceivePort();
    final complete = Completer<double>();
    final subscription = messages.listen((dynamic message) {
      if (message == null && !complete.isCompleted) {
        complete.completeError(
          const StudioException(
            'মডেল প্রক্রিয়া বন্ধ হয়েছে। অন্য অ্যাপ বন্ধ করে আবার চেষ্টা করুন।',
          ),
        );
        return;
      }
      if (message is! Map) {
        return;
      }
      if (message['type'] == 'progress') {
        onProgress?.call((message['progress'] as num).toDouble());
      }
      if (message['type'] == 'done' && !complete.isCompleted) {
        complete.complete((message['duration'] as num).toDouble());
      }
      if (message['type'] == 'error' && !complete.isCompleted) {
        complete.completeError(
          StudioException(
            message['cancelled'] == true
                ? 'কাজ বাতিল হয়েছে।'
                : 'ফোনে মডেল চালানো যায়নি। মডেল পরীক্ষা করুন এবং অন্য অ্যাপ বন্ধ করে আবার চেষ্টা করুন।',
          ),
        );
      }
    });
    Isolate? worker;
    final timeout = Timer(const Duration(minutes: 15), cancel);
    try {
      worker = await Isolate.spawn(
        _pocketWorker,
        <String, Object>{
          'port': messages.sendPort,
          'models': modelDirectory,
          'reference': TransferableTypedData.fromList([
            reference.samples.buffer.asUint8List(
              reference.samples.offsetInBytes,
              reference.samples.lengthInBytes,
            ),
          ]),
          'rate': reference.sampleRate,
          'text': text,
          'output': outputPath,
          'flag': flag.address,
          'seed': seed,
        },
        onExit: messages.sendPort,
        onError: messages.sendPort,
      );
      return await complete.future;
    } finally {
      timeout.cancel();
      // A final result is sent only after native cleanup has finished.
      worker?.kill(priority: Isolate.beforeNextEvent);
      await subscription.cancel();
      messages.close();
      _cancelFlag = null;
      calloc.free(flag);
    }
  }
}

List<String> pocketSegments(String text) {
  final clean = validateText(text);
  if (clean.runes.length > 1500) {
    throw const StudioException(
      'ফোনে একবারে সর্বোচ্চ ১৫০০ অক্ষর ব্যবহার করুন।',
    );
  }
  // This English model must never silently pronounce Bengali as English.
  if (RegExp(r'[\u0980-\u09FF]').hasMatch(clean)) {
    throw const StudioException(
      'ফোনের মডেলটি শুধু ইংরেজি সমর্থন করে। বাংলার জন্য আলাদা সার্ভার প্রয়োজন।',
    );
  }
  final result = <String>[];
  for (var sentence in clean.split(RegExp(r'(?<=[.!?])\s+|\n+'))) {
    while (sentence.length > 220) {
      var end = sentence.lastIndexOf(' ', 220);
      if (end < 1) {
        end = 220;
      }
      result.add(sentence.substring(0, end).trim());
      sentence = sentence.substring(end).trim();
    }
    if (sentence.isNotEmpty) {
      result.add(sentence);
    }
  }
  return result;
}

void _pocketWorker(Map<String, Object> request) {
  final port = request['port'] as SendPort;
  final flag = Pointer<Uint8>.fromAddress(request['flag'] as int);
  sherpa.OfflineTts? tts;
  RandomAccessFile? output;
  var duration = 0.0;
  Object? failure;
  try {
    final chunks = pocketSegments(request['text'] as String);
    sherpa.initBindings();
    final root = request['models'] as String;
    tts = sherpa.OfflineTts(
      sherpa.OfflineTtsConfig(
        model: sherpa.OfflineTtsModelConfig(
          pocket: sherpa.OfflineTtsPocketModelConfig(
            lmFlow: '$root/lm_flow.int8.onnx',
            lmMain: '$root/lm_main.int8.onnx',
            encoder: '$root/encoder.onnx',
            decoder: '$root/decoder.int8.onnx',
            textConditioner: '$root/text_conditioner.onnx',
            vocabJson: '$root/vocab.json',
            tokenScoresJson: '$root/token_scores.json',
            voiceEmbeddingCacheCapacity: 1,
          ),
          numThreads: 2,
          provider: 'cpu',
          debug: false,
        ),
      ),
    );
    final bytes = (request['reference'] as TransferableTypedData).materialize();
    final wave = bytes.asFloat32List();
    output = File(request['output'] as String).openSync(mode: FileMode.write);
    output.writeFromSync(Uint8List(44));
    var total = 0;
    final rate = tts.sampleRate;
    if (rate < 8000 || rate > 48000) {
      throw const FormatException('Invalid model rate');
    }
    for (var i = 0; i < chunks.length; i++) {
      if (flag.value != 0) {
        throw const StudioException('cancelled');
      }
      final audio = tts.generateWithConfig(
        text: chunks[i],
        config: sherpa.OfflineTtsGenerationConfig(
          referenceAudio: wave,
          referenceSampleRate: request['rate'] as int,
          extra: {
            'max_reference_audio_len': 12,
            'seed': request['seed'] as int,
          },
        ),
        onProgress: (samples, p) {
          port.send({
            'type': 'progress',
            'progress': (i + p.clamp(0, 1)) / chunks.length,
          });
          return flag.value == 0 ? 1 : 0;
        },
      );
      if (flag.value != 0) {
        throw const StudioException('cancelled');
      }
      if (audio.samples.isEmpty || audio.sampleRate != rate) {
        throw const FormatException('No generated audio');
      }
      final pcm = ByteData(audio.samples.length * 2);
      for (var j = 0; j < audio.samples.length; j++) {
        final sample = audio.samples[j];
        if (!sample.isFinite) {
          throw const FormatException('Invalid samples');
        }
        pcm.setInt16(
          j * 2,
          (sample.clamp(-1, 1) * 32767).round(),
          Endian.little,
        );
      }
      total += audio.samples.length;
      if (total > rate * 600) {
        throw const FormatException('Output exceeds ten minutes');
      }
      output.writeFromSync(pcm.buffer.asUint8List());
      if (i < chunks.length - 1) {
        final silence = Uint8List((rate * 0.12).round() * 2);
        output.writeFromSync(silence);
        total += silence.length ~/ 2;
      }
    }
    final header = ByteData(44);
    void tag(int start, String value) {
      for (var i = 0; i < value.length; i++) {
        header.setUint8(start + i, value.codeUnitAt(i));
      }
    }

    tag(0, 'RIFF');
    header.setUint32(4, 36 + total * 2, Endian.little);
    tag(8, 'WAVE');
    tag(12, 'fmt ');
    header.setUint32(16, 16, Endian.little);
    header.setUint16(20, 1, Endian.little);
    header.setUint16(22, 1, Endian.little);
    header.setUint32(24, rate, Endian.little);
    header.setUint32(28, rate * 2, Endian.little);
    header.setUint16(32, 2, Endian.little);
    header.setUint16(34, 16, Endian.little);
    tag(36, 'data');
    header.setUint32(40, total * 2, Endian.little);
    output.setPositionSync(0);
    output.writeFromSync(header.buffer.asUint8List());
    output.flushSync();
    duration = total / rate;
  } catch (e) {
    failure = e;
  } finally {
    output?.closeSync();
    tts?.free();
  }
  if (failure != null) {
    final failedFile = File(request['output'] as String);
    if (failedFile.existsSync()) {
      failedFile.deleteSync();
    }
    port.send({'type': 'error', 'cancelled': flag.value != 0});
  } else {
    port.send({'type': 'done', 'duration': duration});
  }
}
