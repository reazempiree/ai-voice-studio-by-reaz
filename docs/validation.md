# Validation record

This report distinguishes executable code, automated tests, builds, and real
neural inference. Final current-run evidence is updated after all checks finish.

- Flutter interface tests: five tests passed during implementation, including
  Bengali text preservation, explicit ownership/upload permission, navigation,
  and a 320×640 screen. These do not execute an AI model.
- Flutter static analysis: passed with no issues after formatter/lint fixes.
- Backend API/model-manager/security/codec tests: passing; includes actual
  FFmpeg WAV→MP3→PCM decoding and cancellation of a real subprocess, checksum
  verification/retry/corruption/removal tests. Mocked model execution is not
  represented as voice cloning.
- Android build: in progress. Initial Java download failed because Gradle does
  not automatically use HTTP_PROXY; retry uses supported Java proxy properties.
- English F5: official model weights verified; real CPU synthesis in progress.
- Bengali IndicF5: blocked by gated weight access (401 GatedRepo). Language
  support is explicit upstream evidence; actual synthesis is unvalidated here.
- Android device playback/import/native decoder/share/install and real phone
  memory/battery behavior need physical-device testing; no device is attached.

No production-readiness or Bengali cloning-success claim is made from these
partial checks. APK distribution status must be read from a successful GitHub
Actions run, not inferred from workflow YAML existing.
