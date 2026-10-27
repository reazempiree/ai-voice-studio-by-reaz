package studio.reaz.ai_voice_studio

import android.media.AudioFormat
import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.InterruptedIOException
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()
    private val decodeCancelled = AtomicBoolean(false)

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "studio.reaz/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "version") {
                    result.success(packageManager.getPackageInfo(packageName, 0).versionName ?: "0.1.0")
                    return@setMethodCallHandler
                }
                if (call.method == "cancelDecode") {
                    decodeCancelled.set(true)
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method != "inspect" && call.method != "decodeReference") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val decoding = call.method == "decodeReference"
                if (decoding) decodeCancelled.set(false)
                val path = call.argument<String>("path")
                executor.execute {
                    try {
                        val file = managedAudioFile(path)
                        val response = if (decoding) {
                            decodeReference(file)
                        } else {
                            mapOf("durationSeconds" to inspect(file))
                        }
                        runOnUiThread { result.success(response) }
                    } catch (_: InterruptedIOException) {
                        runOnUiThread { result.error("CANCELLED_AUDIO", "কাজ বাতিল হয়েছে।", null) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("INVALID_AUDIO", "অডিও পড়া যাচ্ছে না। WAV, MP3 অথবা M4A রেকর্ডিং দিন।", null) }
                    }
                }
            }
    }

    private fun managedAudioFile(path: String?): File {
        val file = File(path ?: throw IllegalArgumentException()).canonicalFile
        require(file.path.startsWith(File(filesDir, "audio").canonicalPath + File.separator))
        require(file.isFile && file.length() in 1..104857600L)
        return file
    }

    private fun audioTrack(extractor: MediaExtractor): Int =
        (0 until extractor.trackCount).firstOrNull {
            extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
        } ?: throw IllegalArgumentException("No audio track")

    private fun validateFormat(format: MediaFormat) {
        require(format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) in 1..2)
        require(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) in 8000..192000)
    }

    private fun inspect(file: File): Double {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = audioTrack(extractor)
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: throw IllegalArgumentException()
            val duration = format.getLong(MediaFormat.KEY_DURATION) / 1000000.0
            require(duration.isFinite() && duration > 0 && duration <= 1200)
            validateFormat(format)
            extractor.selectTrack(track)
            if (mime == "audio/raw") {
                val sample = ByteBuffer.allocate(16384)
                require(extractor.readSampleData(sample, 0) > 0)
                return duration
            }
            val codec = MediaCodec.createDecoderByType(mime)
            decoder = codec
            codec.configure(format, null, null, 0)
            codec.start()
            val info = MediaCodec.BufferInfo()
            var inputEnded = false
            val deadline = System.nanoTime() + 8_000_000_000L
            while (System.nanoTime() < deadline && !Thread.currentThread().isInterrupted) {
                if (!inputEnded) {
                    val index = codec.dequeueInputBuffer(10000)
                    if (index >= 0) {
                        val buffer = codec.getInputBuffer(index) ?: throw IllegalStateException()
                        val count = extractor.readSampleData(buffer, 0)
                        if (count < 0) {
                            codec.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputEnded = true
                        } else {
                            codec.queueInputBuffer(index, 0, count, extractor.sampleTime.coerceAtLeast(0), 0)
                            extractor.advance()
                        }
                    }
                }
                val output = codec.dequeueOutputBuffer(info, 10000)
                if (output >= 0) {
                    val valid = info.size > 0
                    codec.releaseOutputBuffer(output, false)
                    if (valid) return duration
                    if (info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
                }
            }
            throw IllegalArgumentException("No decoded audio")
        } finally {
            try { decoder?.stop() } catch (_: Exception) { /* Uninitialized codec */ }
            decoder?.release()
            extractor.release()
        }
    }

    /** Decodes at most the first 12 seconds; Pocket's conditioning limit is explicit in the UI. */
    private fun decodeReference(file: File): Map<String, Any> {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = audioTrack(extractor)
            var format = extractor.getTrackFormat(track)
            validateFormat(format)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: throw IllegalArgumentException()
            extractor.selectTrack(track)
            var samples = MonoPcm(format)
            val deadline = System.nanoTime() + 30_000_000_000L
            fun checkActive() {
                if (decodeCancelled.get() || Thread.currentThread().isInterrupted) {
                    throw InterruptedIOException("Audio decoding cancelled")
                }
                require(System.nanoTime() < deadline) { "Audio decoding timed out" }
            }
            if (mime == "audio/raw") {
                // A bounded packet buffer avoids retaining the full source recording.
                val buffer = ByteBuffer.allocate(1024 * 1024)
                while (!samples.full) {
                    checkActive()
                    buffer.clear()
                    val count = extractor.readSampleData(buffer, 0)
                    if (count < 0) break
                    require(count <= buffer.capacity())
                    buffer.position(0)
                    buffer.limit(count)
                    samples.append(buffer)
                    if (!extractor.advance()) break
                }
            } else {
                val codec = MediaCodec.createDecoderByType(mime)
                decoder = codec
                codec.configure(format, null, null, 0)
                codec.start()
                val info = MediaCodec.BufferInfo()
                var inputEnded = false
                var outputEnded = false
                while (!samples.full && !outputEnded) {
                    checkActive()
                    if (!inputEnded) {
                        val input = codec.dequeueInputBuffer(10000)
                        if (input >= 0) {
                            val buffer = codec.getInputBuffer(input) ?: throw IllegalStateException()
                            buffer.clear()
                            val count = extractor.readSampleData(buffer, 0)
                            if (count < 0) {
                                codec.queueInputBuffer(input, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                                inputEnded = true
                            } else {
                                require(count <= buffer.capacity())
                                codec.queueInputBuffer(input, 0, count, extractor.sampleTime.coerceAtLeast(0), 0)
                                extractor.advance()
                            }
                        }
                    }
                    val output = codec.dequeueOutputBuffer(info, 10000)
                    if (output == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                        format = codec.outputFormat
                        validateFormat(format)
                        // Decoders may announce PCM details after initialization.
                        require(samples.count == 0 || samples.sameFormat(format))
                        if (samples.count == 0) samples = MonoPcm(format)
                    } else if (output >= 0) {
                        try {
                            if (info.size > 0) {
                                val buffer = codec.getOutputBuffer(output) ?: throw IllegalStateException()
                                require(info.offset >= 0 && info.size <= buffer.capacity() - info.offset)
                                buffer.position(info.offset)
                                buffer.limit(info.offset + info.size)
                                samples.append(buffer)
                            }
                            outputEnded = info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0
                        } finally {
                            codec.releaseOutputBuffer(output, false)
                        }
                    }
                }
            }
            checkActive()
            require(samples.count > 0) { "Empty decoded audio" }
            return mapOf("samples" to samples.result(), "sampleRate" to samples.sampleRate)
        } finally {
            try { decoder?.stop() } catch (_: Exception) { /* Uninitialized codec */ }
            decoder?.release()
            extractor.release()
        }
    }

    /** Fixed-size primitive storage: max 12 * 192000 floats, never boxed sample lists. */
    private class MonoPcm(format: MediaFormat) {
        val sampleRate = format.getInteger(MediaFormat.KEY_SAMPLE_RATE)
        private val channels = format.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
        private val encoding = if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
            format.getInteger(MediaFormat.KEY_PCM_ENCODING)
        } else AudioFormat.ENCODING_PCM_16BIT
        private val bytesPerSample = when (encoding) {
            AudioFormat.ENCODING_PCM_16BIT -> 2
            AudioFormat.ENCODING_PCM_FLOAT -> 4
            AudioFormat.ENCODING_PCM_8BIT -> 1
            else -> throw IllegalArgumentException("Unsupported decoded PCM format")
        }
        private val data = FloatArray(sampleRate * 12)
        var count = 0
            private set
        val full: Boolean get() = count == data.size

        fun sameFormat(format: MediaFormat): Boolean =
            sampleRate == format.getInteger(MediaFormat.KEY_SAMPLE_RATE) &&
                channels == format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) &&
                encoding == (if (format.containsKey(MediaFormat.KEY_PCM_ENCODING)) {
                    format.getInteger(MediaFormat.KEY_PCM_ENCODING)
                } else AudioFormat.ENCODING_PCM_16BIT)

        fun append(buffer: ByteBuffer) {
            buffer.order(ByteOrder.LITTLE_ENDIAN)
            val frameBytes = bytesPerSample * channels
            require(buffer.remaining() % frameBytes == 0) { "Incomplete PCM frame" }
            while (buffer.remaining() >= frameBytes && !full) {
                var mono = 0f
                repeat(channels) {
                    val value = when (encoding) {
                        AudioFormat.ENCODING_PCM_FLOAT -> buffer.float
                        AudioFormat.ENCODING_PCM_8BIT -> ((buffer.get().toInt() and 255) - 128) / 128f
                        else -> buffer.short / 32768f
                    }
                    require(value.isFinite()) { "Invalid PCM sample" }
                    mono += value
                }
                data[count++] = (mono / channels).coerceIn(-1f, 1f)
            }
        }

        fun result(): FloatArray = data.copyOf(count)
    }

    override fun onDestroy() {
        decodeCancelled.set(true)
        executor.shutdownNow()
        super.onDestroy()
    }
}
