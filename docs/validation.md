# Validation record

This report distinguishes executable code, automated tests, builds, and real
neural inference. Final current-run evidence is updated after all checks finish.

- Flutter interface tests: 35 tests passed, including five interface tests, including
  Bengali text preservation, explicit ownership/upload permission, navigation,
  and a 320×640 screen. These do not execute an AI model.
- Flutter static analysis: passed with no issues after formatter/lint fixes.
- Backend API/model-manager/security/codec tests: passing; includes actual
  FFmpeg WAV→MP3→PCM decoding and cancellation of a real subprocess, checksum
  verification/retry/corruption/removal tests. Mocked model execution is not
  represented as voice cloning.
- Android ARM64 release-mode APK builds locally (19.4 MB, test-signed); only
  ARM64 native libraries are packaged. JDK 17 and the environment Java truststore
  plus proxy properties fixed local compiler/TLS setup failures.
- GitHub Actions run 40475653624 succeeded, including analysis, 33 tests at that
  earlier commit, the ARM64 APK build, artifact upload, 36 backend tests and audit.
  Latest source adds two version-comparison tests and additional hardening;
  its final CI run is tracked separately below.
- English F5: real CPU synthesis succeeded (232.39 sec, peak3.22GiB RSS,5.23sec PCM WAV); actual MP3 encoding verified. Subjective similarity is unassessed.
- Bengali IndicF5: blocked by gated weight access (401 GatedRepo). Language
  support is explicit upstream evidence; actual synthesis is unvalidated here.
- Android device playback/import/native decoder/share/install and real phone
  memory/battery behavior need physical-device testing; no device is attached.

No production-readiness or Bengali cloning-success claim is made from these
partial checks. APK distribution status must be read from a successful GitHub
Actions run, not inferred from workflow YAML existing.

Private production signing cannot be configured via the available GitHub
integration (repository secrets API returns 403 Resource not accessible by
integration). Optional private-signing support is implemented; current successful
APKs use Android test signing. Do not distribute them as trusted production updates.
