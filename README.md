# কণ্ঠশিল্প · AI Voice Studio

A Bengali-first Flutter Android voice library and reference-based speech studio.
No advertising, accounts, tracking, subscriptions, paid AI APIs, or bundled model
weights. **Cloning requires the optional self-hosted inference backend. This is
not standalone offline voice cloning on Android.**

## Current capability boundary

The Android client implements reference import, reusable local voice profiles,
Bengali/English text editing, consent-gated backend generation, cancellation,
playback/seek, local history, WAV export, sharing, and optional backend MP3
encoding. Settings manage the backend, its verified model downloads, and an
opt-in GitHub Release update check. The complete Bengali interface uses bundled
Noto Serif Bengali (SIL OFL).

The real inference adapters are IndicF5 for Bengali and F5-TTS v1 Base plus Vocos
for English. IndicF5 explicitly lists Bengali; F5 base does not. Bengali's gated
weights require free upstream access acceptance and a backend Hugging Face token.
Do not treat the presence of either adapter or passing mocked tests as successful
voice cloning. See [model evidence and validation](docs/models.md).

**If you only own an Android phone and have no suitable separate inference host,
the primary Bengali cloning workflow is blocked.** GitHub Actions can build an
APK but is not permanent free AI hosting. This project does not conceal that gap
with preset voices, recordings, paid APIs, or temporary cloud credits.

## Install from GitHub using your phone

1. Open this repository's **Actions → Android APK** workflow. Run it manually on
   the implementation branch, or use a successful existing run.
2. After the build succeeds, download **AI-Voice-Studio-Android-APK** from that
   run's artifacts. GitHub may require you to sign in. Extract the ZIP and open
   `app-release.apk`; Android will ask you to allow installation from your browser
   or file manager. Verify the adjacent SHA-256 checksum when possible.
3. Tagged `v*` builds also publish an APK and checksum to GitHub Releases after
   both Android and backend checks pass. No APK is available until a build has
   actually succeeded.

These builds currently use Android **test signing**, not a private production
release identity. Ephemeral CI keys may change, so installing a later test build
may require uninstalling the old one (which deletes private app data). Configure
private release signing before trusted public distribution. Never commit a
private release keystore or its password. Optional CI signing reads repository secrets
`ANDROID_KEYSTORE_BASE64`, `ANDROID_STORE_PASSWORD`, `ANDROID_KEY_PASSWORD`, and
`ANDROID_KEY_ALIAS`. They must describe the same safely backed-up private key.
The available GitHub integration cannot manage repository secrets (HTTP 403), so
private production signing has not been configured or tested.

Android requirements: Android 8.0/API 26 or newer, ARM64. There is no measured
phone RAM minimum for AI inference because AI inference is not executed there.
For actual host requirements and model sizes see [backend setup](backend/README.md).
No Android Studio, Termux, or personal computer is needed to **build/install the
APK**. The optional backend still needs separately owned/controlled hardware;
this requirement cannot be removed by the build workflow.

## Use

- In the voice library, select a 3–30 second WAV, MP3, or decodable M4A recording
  (maximum 25 MiB). Give it a name and the accurate transcript of what is spoken.
  Confirm ownership or explicit permission. A quiet single-speaker reference
  works best; the app rejects missing/empty/undecodable or oversized input.
- Set up the optional [private backend](backend/README.md). Enter its address
  and random access token in settings. Tokens use Android secure storage. HTTPS
  is recommended; HTTP is allowed only for private IPv4/localhost/`.local`
  endpoints and does **not** encrypt network traffic.
- Connect, review each model's real size/license and custom-code notice, and
  explicitly install the models on the backend. English needs `f5` and `vocos`;
  Bengali needs `indicf5` plus its compatible upstream runtime and gated access.
  The app downloads no multi-gigabyte models onto your phone.
- Choose a saved voice, select বাংলা or ইংরেজি, enter up to 3,000 characters,
  and separately authorize sending that recording and text to your backend.
  Longer input is segmented by the backend. Generated speech is labeled synthetic.
- Preview the result and save/share WAV. MP3 export explicitly uploads the
  **generated** WAV to your backend for actual FFmpeg encoding. WAV export works
  without the backend. Reference profiles and completed history remain local.

Do not use this app for deceptive impersonation. Use only voices you own or have
explicit permission to clone. Verify pronunciation and output before sharing.

## Privacy and reliability

The app requests Internet access; audio dependencies also declare network-state
access and a signature-only internal receiver permission. File selection/export uses Android's
system picker and no broad storage or microphone permission. Android cloud backup
is disabled. Profiles, transcripts, and history are in private app storage.
Reference metadata/history writes are serialized with atomic replacement and a
recovery copy. Audio paths are generated identifiers and validated on read/delete.
The native audio probe runs off the UI thread and checks a real decoded frame.

Nothing uploads until generation authorization. LAN generation uses a bearer
access token and rejects redirects; use HTTPS on networks you do not fully trust.
The backend runs one generation at a time, isolates/cancels the model subprocess,
verifies model integrity, and removes request/reference data after completion or
cancellation. Outputs expire after 30 minutes and are removed on server restart.
The app requests immediate server cleanup after downloading. If cleanup fails,
a visible error explains that retry/network access is needed; backend expiry
still applies. Shared/exported files leave private app storage and are managed
by the recipient or chosen destination.

Generation is not a foreground Android service: keep the app open during a job.
Android termination can lose an unfinished generation; saved profiles, draft text
and completed history survive. Remote work expires on the backend. No exact RAM,
quality, or battery guarantee is made. Deleting a voice removes its reference;
completed synthetic audio remains until separately deleted from history.
The system file picker's temporary import cache is cleared after copying.

## Development and verification

Pinned Flutter **3.35.7** / Dart **3.9.2**, Java **17**, AGP **8.9.1**, Kotlin
**2.1.0**, Gradle **8.12**, compile SDK **36**, minimum SDK **26**. Direct Dart
dependencies are pinned and the resolved lockfile is committed.

```sh
flutter pub get --enforce-lockfile
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
flutter build apk --release --target-platform android-arm64
# API/codec/security tests; no GPU/model download needed:
python -m venv .venv-backend
.venv-backend/bin/pip install -r backend/requirements.lock.txt
.venv-backend/bin/python -m pytest backend/tests -q
```

`lib/domain` holds validation/entities; `lib/data` holds private storage, native
audio access, and the replaceable inference adapter; `lib/application` coordinates
jobs/library/privacy; `lib/presentation` provides the Bengali UI. Kotlin handles
Android audio inspection. The independent FastAPI backend owns model installation,
real inference, bounded uploads, and real audio transcoding.

Flutter tests use mocked native channels/inference where required. Backend tests
include real FFmpeg and process cancellation, with neural inference reported
separately. See [validation report](docs/validation.md) for executed results and
remaining limits. The workflow also audits Python dependencies. Review upstream
advisories and license changes when updating dependencies.

## Licenses

New application/backend code: MIT ([LICENSE](LICENSE)). Noto Serif Bengali: SIL
OFL ([font license](assets/fonts/OFL.txt)), bundled in Android's license page.
Flutter-generated Android scaffolding follows Flutter's BSD-3-Clause terms.
Model licenses remain separate: IndicF5 model metadata declares MIT; F5 model
weights are CC-BY-NC-4.0 (personal/noncommercial use), Vocos MIT. Models are not
redistributed here. DIGI LABS is source-available and its code/assets were not
copied. See [evaluation](docs/models.md) and the app's dependency license screen.
