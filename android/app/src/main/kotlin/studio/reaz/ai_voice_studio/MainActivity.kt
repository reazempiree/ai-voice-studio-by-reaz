package studio.reaz.ai_voice_studio

import android.media.MediaCodec
import android.media.MediaExtractor
import android.media.MediaFormat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.util.concurrent.Executors

class MainActivity : FlutterActivity() {
    private val executor = Executors.newSingleThreadExecutor()

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "studio.reaz/audio")
            .setMethodCallHandler { call, result ->
                if (call.method == "version") {
                    result.success(packageManager.getPackageInfo(packageName, 0).versionName ?: "0.1.0")
                    return@setMethodCallHandler
                }
                if (call.method != "inspect") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val path = call.argument<String>("path")
                executor.execute {
                    try {
                        val file = File(path ?: throw IllegalArgumentException()).canonicalFile
                        require(file.path.startsWith(File(filesDir, "audio").canonicalPath + File.separator))
                        require(file.isFile && file.length() in 1..104857600L)
                        val duration = inspect(file)
                        runOnUiThread { result.success(mapOf("durationSeconds" to duration)) }
                    } catch (_: Exception) {
                        runOnUiThread { result.error("INVALID_AUDIO", "অডিও পড়া যাচ্ছে না।", null) }
                    }
                }
            }
    }

    private fun inspect(file: File): Double {
        val extractor = MediaExtractor()
        var decoder: MediaCodec? = null
        try {
            extractor.setDataSource(file.path)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: throw IllegalArgumentException("No audio track")
            val format = extractor.getTrackFormat(track)
            val mime = format.getString(MediaFormat.KEY_MIME) ?: throw IllegalArgumentException()
            val duration = format.getLong(MediaFormat.KEY_DURATION) / 1000000.0
            require(duration.isFinite() && duration > 0 && duration <= 1200)
            require(format.getInteger(MediaFormat.KEY_CHANNEL_COUNT) in 1..2)
            require(format.getInteger(MediaFormat.KEY_SAMPLE_RATE) in 8000..192000)
            extractor.selectTrack(track)
            // PCM WAV has no compressed decoder on some Android devices. Verify data directly.
            if (mime == "audio/raw") {
                val sample = java.nio.ByteBuffer.allocate(16384)
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
            while (System.nanoTime() < deadline) {
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

    override fun onDestroy() {
        executor.shutdownNow()
        super.onDestroy()
    }
}
