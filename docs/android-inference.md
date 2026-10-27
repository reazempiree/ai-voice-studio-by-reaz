# Android inference investigation and generation routing

Evidence inspected on 2026-10-27. A model's upstream language list, an available
Android binary, a real inference run, and a physical-phone benchmark are separate
claims.

## Why the installed APK asked for a server

The previous client only implemented the HTTP `InferenceClient`. Its generation
path called `_client()`, which rejected an empty backend URL/token before any
synthesis could occur. The APK contained neither F5/IndicF5 inference code nor
weights. Entering an invented server address would not fix that missing runtime.

## Existing F5 and IndicF5 adapters

Those adapters call Python/PyTorch code in separate environments on Linux.
Linux x86-64 Python/PyTorch packages are not Android ARM64 binaries: Android uses
Bionic and a distinct app/NDK runtime. A `.safetensors` file is model data, not an
executable Android inference engine. The existing code cannot simply download
that file and synthesize on Android.

The recorded F5 CPU test peaked near 3.22 GiB RSS and took minutes for a short
sentence on the cloud host. These measurements do **not** prove that every phone
has too little memory or that an Android port is theoretically impossible. No
phone model, available memory, or physical Android inference device was supplied.
The precise blocker is the absence of a verified compatible Android F5/IndicF5
runtime/model export in this implementation, not a fabricated device RAM limit.
IndicF5's gated weights and Bengali validation remain separate prerequisites.

## Supported native alternative: Pocket TTS ONNX

The public sherpa-onnx package **2.0.1** explicitly contains Pocket TTS APIs and
has a matching `sherpa_onnx_android_arm64` native dependency. This is an Android
NDK/FFI runtime, not a Python subprocess, Termux installation, or remote service.
Its public API accepts reference PCM audio and its sample rate in
`OfflineTtsGenerationConfig`, then invokes `generateWithConfig`. No server URL,
access token, or reference transcript is required by Pocket's conditioning API.

The selected dated model is the English quantized Pocket export. **It does not
establish Bengali support.** Current upstream Pocket language documentation lists
English, French, German, Portuguese, Italian, Spanish, and Dutch; Bengali is not
listed. Neither a Bengali interface nor a multilingual marketing label changes
that boundary. Bengali reference cloning must remain explicitly unavailable
locally; the optional existing backend is separate and still needs compatible
IndicF5 model access and real Bengali validation.

Sources inspected:

- https://pub.dev/packages/sherpa_onnx/versions/2.0.1
- https://github.com/k2-fsa/sherpa-onnx/blob/master/dart-api-examples/tts/bin/pocket-en.dart
- https://github.com/k2-fsa/sherpa-onnx/blob/master/python-api-examples/pocket-tts.py
- https://github.com/k2-fsa/sherpa-onnx/tree/master/flutter/sherpa_onnx_android_arm64
- https://github.com/kyutai-labs/pocket-tts
- https://github.com/k2-fsa/sherpa-onnx/releases/tag/tts-models

## Exact installed-model metadata

The authoritative GitHub release API exposes asset ID **353678269**:

- Filename: `sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2`.
- Download URL:
  https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/sherpa-onnx-pocket-tts-int8-2026-01-26.tar.bz2
- Compressed bytes: **98,336,520**.
- Published SHA-256:
  `2f3b88823cbbb9bf0b2477ec8ae7b3fec417b3a87b6bb5f256dba66f2ad967cb`.
- Seven required inference/tokenizer files plus README/LICENSE: **198,310,873**
  uncompressed bytes. Keep at least 600 MB free during installation for the
  archive, bounded temporary tar, and staged files. This is installation storage,
  not a claim about minimum inference RAM.

The implementation downloads only after size/license confirmation, supports
HTTP Range retry/recovery where the source honors it, verifies the published
archive checksum, expands bzip2 off the UI isolate with a 256 MiB hard output
limit and CRC verification, and extracts only exact whitelisted model filenames.
It rejects links/unsafe paths and checks each required file's size and SHA-256
against the verified archive before atomic installation. Model removal deletes
installed and partial files. Inspection detects missing/corrupted files. Both
download and extraction can be cancelled. No model weights are bundled in the
APK or silently downloaded at app startup.

After installation, local English inference needs no network or account.
Existing profile audio must be decoded into PCM on the phone before native
conditioning. WAV export is local. MP3 conversion may still use the separately
configured backend unless a local encoder is separately provided; the UI must
not imply that backend MP3 conversion is offline.

## Licensing and attribution

- sherpa-onnx code and native bindings: Apache-2.0.
- Pocket TTS upstream application code: MIT.
- The selected downloaded archive includes a **CC-BY-4.0** LICENSE file. Its README
  also says “It is for non-commercial” and links the ONNX exporter's license.
  Both source documents are retained with the installation; the app describes
  conservative **personal/noncommercial** use rather than silently resolving
  that discrepancy into an unrestricted-use promise.
- Model source: Kyutai Pocket TTS; ONNX conversion is credited by the archive to
  https://github.com/KevinAHM/pocket-tts-onnx-export.
- The checksum was obtained from release metadata and independently verified,
  not invented or weakened to accommodate a failed download.

Successful desktop CPU inference with these exact models validates real neural
reference conditioning on that tested runtime. Packaging the matching ARM64
library establishes a buildable Android integration, not a measured phone
speed/RAM/quality result. Physical-device generation must be tested separately.
Bengali phone-only cloning is not claimed solved by this English alternative.

## Model installer checks executed

Using the real published release archive (not fixture model bytes), a standalone
Dart check completed installation, all checksums, installed-model inspection,
intentional corruption detection, removal, and actual extraction-isolate
cancellation in 24.87 seconds on this cloud CPU. A separate real HTTP test started
with a 1 MiB partial file and completed Range/retry recovery, full SHA-256
verification, and installation in 22.14 seconds. These installer checks validate
model handling, not neural synthesis or Android-phone performance.

## Real exact-app-worker inference evidence

The app's `PocketEngine` was executed by the Dart CLI against the published
int8 models, with the same FFI calls and worker-isolate implementation as Flutter.
Text: “This is real offline speech using the reference voice.”, seed42.

- Reference `test_wavs/bria.wav`:2.96seconds,142,124-byte mono24kHz PCM16 WAV,
  2.426seconds wall on cloud Linux; RMS0.0867; SHA256
  `fb5a7013cf530a7aa4b58c65e8dc50576e1f36d8d3aff07cbe4e7b4ee9138649`.
- Different upstream reference (F5's basic English nature sample), same text/seed:
  3.28seconds,157,484-byte WAV,1.918seconds wall; RMS0.1558; SHA256
  `ef7060acf998b46aab91d16ce3136bed60e0f9cee3224226635cdc72b9addcc1`.

Both are actual newly synthesized waveforms, not copied prompt recordings.
The reference is passed to Pocket's conditioning encoder, and changing it changes
output under otherwise deterministic settings. This verifies real reference-based
neural synthesis on the tested Linux runtime; it does not measure perceptual
identity, Bengali quality, or Android-phone execution. `tool/pocket_smoke.dart`
reproduces the worker check; an additional `cancel` argument tests cancellation
inside a real native callback with no saved partial output. CI runs both.

## Existing installed data and signing

Profile/history schema1 is retained with an additive inferenceMode preference;
existing file paths/IDs are not rewritten or deleted. However, the old CI APK's
private signing key was ephemeral. Without that exact key a new normal-ID build
cannot replace the installed APK, and uninstalling would delete its private data.
CI therefore also builds a separate `studio.reaz.ai_voice_studio.offline` package
labeled “কণ্ঠশিল্প অফলাইন”. This safe-install APK coexists with the original and
preserves its private library there. It cannot silently read or migrate the other
app's sandbox; original recordings must be reimported for the separate trial.
Private stable signing is required for reliable future in-place production updates.
