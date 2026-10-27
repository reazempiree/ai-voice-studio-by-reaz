# কণ্ঠশিল্প · AI Voice Studio

Bengali-first Flutter Android voice studio. **Version0.2 adds real on-device
English reference-audio cloning with Pocket TTS/sherpa-onnx.** After the explicit
one-time model download, English generation needs no server URL, access token,
account, paid API, or Internet. **Bengali cloning is not supported by the local
model.** The optional Python backend remains separate.

## Generate on your phone — no server settings

1. Choose **ফোনে · ইংরেজি** in the generation screen, then choose **ইংরেজি**.
2. Open Settings → phone model. Review the size/license and explicitly download
   Pocket's model:98,336,520bytes (about98MB), about198MB installed. Keep at least
   600MB free during installation. SHA-256 and individual files are verified;
   downloads can resume/retry and be cancelled. There are no model weights in
   the APK and no silent model download.
3. Import a clear3–30second WAV/MP3/M4A recording of a voice you own or have
   explicit permission to use. The first12seconds condition the local model.
   A transcript is optional for Pocket; existing server models require it.
4. Select that profile, enter English text (up to1,500characters locally), and
   generate. Your recording and text stay on the phone. Keep the app open.
5. Play, seek, share or save WAV. History and profiles are stored privately.

If Bengali is selected locally, the app explains the missing Bengali engine and
provides an English-mode action. It does **not** ask for imaginary server details
or pronounce Bengali using an English engine. To try Bengali, you still need a
separate compatible inference host and gated IndicF5 access; Bengali synthesis
has not been validated here. If you only own this Android phone, Bengali cloning
remains blocked. GitHub Actions is a build service, not permanent inference hosting.

| Feature | Phone/offline after model installation | Separate backend |
|---|---|---|
| English reference cloning | Pocket native ONNX engine | Optional F5 adapter |
| Bengali reference cloning | **Unavailable** | IndicF5 candidate; gated/unvalidated |
| Profiles, history, playback, WAV sharing/export | Yes | No |
| MP3 encoding | Not implemented locally | Optional explicit synthetic-WAV upload |
| Model installation / opt-in update check | Internet needed for these actions | No paid service |

## Download and preserve your old installation

Open **Actions → Android APK** and download a successful run's artifact.

- **AI-Voice-Studio-Offline-Safe-Install-APK** contains
  `app-offline-safe-install.apk`. This installs as **কণ্ঠশিল্প অফলাইন** with a
  separate application ID, so the old app and its private profiles/history stay
  untouched. Existing private data cannot automatically cross Android's app
  sandbox; reimport original recordings to try the new app, and keep the old app
  for its existing history. Do not uninstall it to force an update.
- **AI-Voice-Studio-Android-APK** contains the normal-ID update APK. An in-place
  update preserves the existing schema1 library **only if it is signed with the
  same key as the installed app**. Earlier CI test builds used ephemeral signing
  keys, which cannot be recovered from their APKs. A signature mismatch is not
  fixed by increasing the version number. Do not uninstall and lose data.

Both variants are currently personal test builds unless private signing secrets
are configured. GitHub may require sign-in to download artifact ZIPs. Extract the
APK, verify the adjacent SHA-256 when possible, and authorize installation from
that browser/file manager. No Termux, Android Studio or personal computer is
needed to build or install either APK. Artifacts expire after30days; tagged builds
can publish the normal APK through GitHub Releases. Downloadability is claimed
only for successful actual workflow runs.

Optional private signing reads repository secrets `ANDROID_KEYSTORE_BASE64`,
`ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, `ANDROID_KEY_ALIAS`. The available
GitHub integration cannot manage these secrets. Never commit a private keystore.

## What is genuinely tested

See [Android investigation and real evidence](docs/android-inference.md).
The exact Dart worker used by Flutter has generated new English speech using
two different real reference recordings and the public, checksum-verified Pocket
weights on Linux CPU, without the Python backend. Deterministic runs with the
same text/seed changed output when reference audio changed. Actual native
cancellation and model installation/recovery are checked separately. These are
not mocks or prerecorded substitute outputs.

The Android ARM64 runtime is packaged through sherpa-onnx2.0.1, and Android builds
compile the real native decoding/FFI route. **No physical Android inference device
is attached to this cloud environment.** Linux timing/RAM measurements do not prove
phone performance, and no minimum phone RAM or subjective speaker-similarity
score is invented. Android8/API26+, ARM64 is the packaging target. Phone decoding,
model loading, synthesis and battery behavior still need device validation.

## Architecture, privacy and optional backend

The Bengali UI, saved profile/history schema, text editor, audio playback,
consent controls and export are preserved. `lib/data/pocket_engine.dart` runs real
ONNX inference in a worker isolate; reference decoding uses Android MediaCodec.
Native PCM processing is bounded to12seconds, downmixes stereo, and frees codecs.
The model worker checks cancellation during native callbacks and frees its native
engine before completing. Long English text is segmented and written as real
PCM16 WAV. Local models and partial downloads can be removed in Settings.

The server adapter remains behind an explicit **নিজস্ব সার্ভার** mode and its
separate upload consent. See [backend setup](backend/README.md). Local English
never requests or uses those server credentials. MP3 export still asks permission
before sending **generated** WAV to that backend for actual encoding; no extension
renaming is used. The phone route does not load Python/Gradio/Pillow dependencies;
the old optional backend's unresolved dependency advisories remain documented.

No ads, analytics, hidden telemetry, registration or paid hosting are introduced.
Android broad storage/microphone permissions are not requested; system file
pickers handle import/export. Android backup is disabled. Private library writes
are atomic with a recovery copy, and managed paths are validated. Synthetic speech
is labeled. Exported/shared copies are managed by their destination. An interrupted
inference may need retry, while saved profiles/history and draft text persist.

## Build and checks

Pinned Flutter3.35.7/Dart3.9.2, Java17, AGP8.9.1, Kotlin2.1.0, Gradle8.12,
compile SDK36. Direct dependencies and the resolved lockfile are pinned.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test tool
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
# Real model inference, not a mock (models and reference supplied explicitly):
dart run tool/pocket_smoke.dart /path/to/pocket-model /path/to/reference.wav /path/to/new-synthetic.wav
# Optional API/codec/security tests:
python -m venv .venv-backend
.venv-backend/bin/python -m pip install -r backend/requirements.lock.txt
.venv-backend/bin/python -m pytest backend/tests -q
```

GitHub Actions runs formatting, analysis, unit/widget tests, **real Pocket
reference-audio synthesis and cancellation**, then builds and uploads both Android
variants. It separately tests/audits the optional API. Neither a successful Linux
inference nor an APK build is described as a physical-phone benchmark.

## Licenses

New application code: MIT. Noto Serif Bengali: SIL OFL (bundled license page).
sherpa-onnx: Apache2.0; Pocket code: MIT. The chosen downloaded Pocket export
contains CC-BY4.0 licensing and a personal/noncommercial instruction in its README;
both are retained and shown before download. Attribution: Kyutai Pocket TTS,
KevinAHM's ONNX export, k2-fsa sherpa-onnx. The requested personal use is treated
conservatively as noncommercial. See [license evidence](docs/android-inference.md).
F5 optional backend weights remain CC-BY-NC4.0, Vocos MIT, IndicF5 metadata MIT.
No model weights or DIGI LABS code are bundled in the repository/APK.
