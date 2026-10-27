# Version0.2 native English inference validation

The original server-credential error was caused by routing all synthesis through
an HTTP adapter. Version0.2 adds Pocket TTS/sherpa-onnx native inference for
English. Bengali remains unavailable locally. The exact runtime/ABI limitation,
licenses and evidence are in [android-inference.md](android-inference.md).

- Executable source: `9eca5a451f3fc0386c0ca2a5ba7370a9ab11e82c`.
- Format and Flutter analysis passed; **53 Flutter tests passed**. These include
  no-server local routing, Bengali refusal, model/cancellation/error handling,
  schema1 preservation, optional transcript, and a320×640license dialog.
- Optional backend regression tests: **36 passed** (two upstream deprecation
  warnings). It is not needed for local English or WAV export.
- The exact app Dart/FFI worker performed real int8 model inference using two
  distinct reference samples with fixed text/seed. New24kHz PCM16 WAV outputs
  were2.96sec and3.28sec, with nonzero RMS and distinct waveform hashes. Actual
  native callback cancellation passed in1.225sec with no partial output retained.
- A final real run produced2.96sec audio in1.995sec on this Linux CPU;
  process peak RSS806,346,752bytes includes the Dart process. This is not an
  Android latency/RAM benchmark or a minimum phone memory specification.
- Real model installation checks covered official98,336,520-byte download,
  Range recovery, published SHA256, exact installed files, corruption, removal
  and extraction cancellation. Model files are not bundled in the APK.
- Local safe-install APK compiled as `studio.reaz.ai_voice_studio.offline`,
  version0.2.0+2,51,138,395bytes. Signature verification, onlyARM64 libraries,
  16KB APK alignment and both ONNX/CAPI ELF LOAD alignment checks passed.
- `adb devices -l` listed **no attached Android device**. Native Android
  decoding/model execution with the user's voice still requires physical-phone
  validation. No subjective speaker-similarity score or Bengali success is claimed.
- Current GitHub Actions run:
  https://github.com/reazempiree/ai-voice-studio-by-reaz/actions/runs/40513732949
  **Succeeded**: all53 Flutter tests, analysis/format, actual Pocket reference
  inference/cancellation, both ARM64 builds/uploads, all36 backend tests and API audit.
  The normal-ID artifact is12738726622; safe-install artifact is12739775364:
  https://github.com/reazempiree/ai-voice-studio-by-reaz/actions/runs/40513732949/artifacts/12739775364
  Both were confirmed uploaded and unexpired. No tagged release was published.

The safe-install package coexists with the old test-signed app and leaves its
private profiles/history there. It cannot automatically read another Android
app's sandbox. A same-ID update requires the original private signing key, which
was not retained by earlier ephemeral CI builds. Do not uninstall the old app to
force a mismatched-key update.

**Open requirements:** Bengali phone-only reference cloning, physical-phone
inference validation, a local MP3 encoder, and stable private production signing.
English generation and WAV use no backend after model installation; Bengali and
MP3 retain the optional separate backend, whose own security limitations remain
below. This task is not declared a fully solved Bengali/offline product.

---

## Historical0.1 backend validation (preserved evidence)

# Validation record — 2026-10-27

## Automated checks and APK

- `dart format --output=none --set-exit-if-changed lib test`: passed.
- `flutter analyze`: passed, no issues.
- `flutter test`: **35 passed**. Native audio/file-picker and inference pipeline
  portions use explicit mocks/fakes; these are not neural cloning tests.
- Fresh locked API environment: **36 backend tests passed**, with two upstream
  test-client deprecation warnings. Real FFmpeg encoding/decoding and subprocess
  cancellation ran; fixture model-manager transports test checksums and retries.
- Final local ARM64 release-mode APK: **19,386,241 bytes**, Android API26+, only
  `arm64-v8a` native libraries. Android apksigner verification passed; currently
  **test-signed**. SHA256:
  `bf1f8c60250073e7f4bef18623689cc5cc20cb1fa25c90954222964656122e3c`.
  Local and CI APK hashes can differ because their test signing keys differ.
- Final executable source commit: `18d08ae324308766c08909a13281f5aeeeb9fac9`.
- **GitHub Actions succeeded** for that commit: analysis, all35 Flutter tests,
  ARM64 APK build, artifact upload, all36 backend tests and API dependency audit.
  Run: https://github.com/reazempiree/ai-voice-studio-by-reaz/actions/runs/40476814276
- Uploaded artifact **AI-Voice-Studio-Android-APK**, ID12721413100, confirmed
  unexpired at validation time:
  https://github.com/reazempiree/ai-voice-studio-by-reaz/actions/runs/40476814276/artifacts/12721413100
  Artifacts expire after30days. Tagged versions can publish GitHub Releases;
  no tag/release was published in this task.

## Actual model execution

Actual F5-TTS v1 Base plus Vocos CPU worker synthesis succeeded using the upstream
English reference sample and a new sentence:5.23sec WAV,232.39sec wall,
peak~3.22GiB RSS. A full authenticated API test also passed upload, real model
execution, WAV retrieval, actual MP3 conversion and job deletion:4.5653sec speech,
178.92sec wall,93,164-byte MP3,404 after deletion. These are real model outputs,
not recordings substituted for synthesis. No subjective voice-similarity or
English/Bengali pronunciation assessment is claimed. See docs/models.md.

Bengali IndicF5 explicitly lists Bengali upstream but gated weight access returned
401 GatedRepo. Real Bengali inference is **unvalidated**. There is no on-device
model runtime in this APK and no physical Android device was attached; native
import/playback/share/install, actual device memory and battery behavior need
phone testing. Phone-only Bengali cloning remains blocked.

## Security and environment

API dependency audit:0 known advisories at the recorded date. The separate
inference audit is **not clean**: compatible Pillow12.3.0 has37 advisory records,
while upstream Gradio restricts it below the fixed13.0.0. Other affected support
packages were repaired; `pip check` passes. See the model report for details.
This optional inference environment is not claimed production-secure.

Private production signing is supported in Gradle/CI but is not configured:
GitHub repository-secrets access returned403 Resource not accessible by integration.
Current APKs use Android test signing and must not be presented as trusted
production releases.

The reusable cloud setup script executed successfully in a fresh API venv;
install/start instructions and optional gated-model HF_TOKEN requirement were
saved to the environment draft. Saving does not publish the environment or prove
restoration in a fresh task. Live inference servers are not assumed to survive.

Final compatible inference-lock revalidation also passed the complete real
English HTTP flow in160.98seconds, including MP3 conversion and deletion.
The source checkout is clean after committed delivery; pull request:
https://github.com/reazempiree/ai-voice-studio-by-reaz/pull/1
