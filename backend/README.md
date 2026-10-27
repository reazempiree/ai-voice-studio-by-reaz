# Optional private-network inference service

This is a **real model adapter**, not an Android model runtime. It costs no API
fees, but needs a separate machine you already own or control. It is **not a
solution to the phone-only requirement** if you have no such machine. GitHub
Actions builds APKs; it is not permanent inference hosting. No public inference
service or free cloud trial is used.

The Android app never sends recordings until the user authorizes the selected
backend. Keep the service on a trusted private network, do not port-forward it,
and prefer an HTTPS reverse proxy with a valid certificate. A bearer token
authenticates requests; plain HTTP LAN mode is not encryption.

## API server

From the repository root on a Linux host with Python 3.12 and FFmpeg/ffprobe:

```sh
python3 -m venv .venv-backend
.venv-backend/bin/pip install -r backend/requirements.lock.txt
# Generate/store a random token privately; never commit it or put it in chat.
export VOICE_BACKEND_TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
export VOICE_DATA_DIR="$PWD/.voice-data"
# Default loopback is intentionally private. Set your trusted LAN interface only
# when needed. Configure firewall access from your phone only.
export VOICE_BIND_HOST=127.0.0.1
.venv-backend/bin/python -m backend.app
```

For a LAN host, set `VOICE_BIND_HOST` to its private interface address, enter that
address and the same token in Android settings, and explicitly accept sending
audio. Do not use a public endpoint or disable TLS certificate checks. Protect
the host's disk and operating-system account; this service does not implement
at-rest encryption or multiuser isolation.

## Inference environments

F5-TTS and IndicF5 both use the Python module name `f5_tts`; use **separate virtual
environments**. The lightweight API installation does not install or silently
download either model. CPU compatibility must be validated on your actual host.

English adapter installation:

```sh
python3 -m venv .venv-f5
.venv-f5/bin/pip install torch==2.8.0+cpu torchaudio==2.8.0+cpu \
  --index-url https://download.pytorch.org/whl/cpu
.venv-f5/bin/python -m pip install --upgrade pip==26.2.2 setuptools==84.1.0
.venv-f5/bin/python -m pip install -r backend/requirements-f5.lock.txt
export F5_PYTHON="$PWD/.venv-f5/bin/python"
export VOICE_DEVICE=cpu
```

The Linux/Python 3.12 CPU inference lock records the tested environment. Its
upstream Gradio dependency restricts Pillow below 13, while the current security
advisories require Pillow 13.0.0. **The model runtime therefore still has known
Pillow advisories and is not security-clean for production deployment.** The
service accepts audio only and does not launch Gradio, but that does not remove
the installed dependency finding. Keep it private and review upstream fixes;
do not loosen a version constraint or disable verification to hide the finding.
API-server dependencies are separately audited and clean at the recorded date.

These commands target the documented API. See `docs/models.md` for actual test
results and limitations; installation alone is not a quality or performance
claim. A CUDA installation requires matching PyTorch/device packages instead.

IndicF5's upstream setup uses Python 3.10 and its fork. Install it only after
reviewing and accepting its upstream terms; no IndicF5 source/weights are
redistributed in this repository:

```sh
python3.10 -m venv .venv-indicf5
.venv-indicf5/bin/pip install \
  git+https://github.com/ai4bharat/IndicF5.git@13f7c4d627cc10111aea8fe9c0039462cacacdc7
export INDICF5_PYTHON="$PWD/.venv-indicf5/bin/python"
```

The Bengali model is gated at Hugging Face. Request its free access using your
own account at <https://huggingface.co/ai4bharat/IndicF5>, accept its terms, then
configure `HF_TOKEN` securely on the **backend host**. Never send it to the Android
app. Token presence does not prove gated access. Custom model Python code is
executed only after an explicit additional acceptance during installation.
IndicF5 initialization remains unverified until gated weights can be tested.
Its upstream may need additional local vocoder cache assets; initialization fails
visibly in offline mode rather than fetching them silently.

## Model manager and API

All endpoints require `Authorization: Bearer <VOICE_BACKEND_TOKEN>`.

1. `GET /v1/capabilities`: installed engine availability by language; actual
   inference validation is a separate fact (`inference_validated`).
2. `GET /v1/models`: model installation/download states and byte counts.
3. `POST /v1/models/{id}/plan`: fetch official Hugging Face metadata, immutable
   revision, exact selected-file sizes, Git blob/LFS checksums, and declared
   license. Model IDs are `indicf5`, `f5`, `vocos`; English requires both `f5`
   and `vocos`. Size zero before planning means **unknown**, not a free/empty model.
4. `POST /v1/models/{id}/install` with JSON
   `{"accept_license":true,"accept_remote_code":true}` explicitly starts download.
   IndicF5 requires both flags; unknown licenses block installation. Every file
   is downloaded from the pinned revision and verified before atomic installation.
   Retry reuses fully verified files; interrupted individual files restart.
5. `DELETE /v1/models/{id}` cancels an active download; after it stops, repeat
   deletion to remove downloaded files. Model removal is blocked during synthesis.
6. `POST /v1/jobs`: multipart `audio`, `text`, `language` (`bn` or `en`),
   `reference_text` (the accurate transcript of the reference), `consent=true`.
   Maximum 25 MiB / 30-second reference, 3,000 text characters. Accepted input
   containers are WAV, MP3 and M4A/MP4 when the installed FFmpeg decodes them.
7. `GET /v1/jobs/{id}` polls state and per-segment progress. This is not a
   fabricated estimate of neural inference percentage.
8. `GET /v1/jobs/{id}/audio?format=wav|mp3`: download actual PCM WAV or FFmpeg
   `libmp3lame`-encoded MP3. No extension renaming is used.
9. `DELETE /v1/jobs/{id}` terminates inference and deletes temporary audio.
10. `POST /v1/convert`: explicitly authorized multipart `audio` PCM WAV upload
    for later MP3 export, maximum 100 MiB / 20 minutes. It returns `audio/mpeg`
    and deletes temporary conversion files after the response.

The worker uses actual `transformers.AutoModel` IndicF5 or `f5_tts.api.F5TTS`,
with recorded reference transcript and reference WAV. No prerecorded speech
stands in for synthesis. Long text is segmented at punctuation/word boundaries,
rendered serially, and stitched as 24 kHz mono PCM with 120 ms intersegment pauses.
Voice identity can vary across chunks; no untested quality guarantee is made.

Inference runs one job at a time in an isolated subprocess, with a 30-minute
ceiling. Cancellation terminates the subprocess; reference audio/request text
are deleted at completion or cancellation. Outputs and private diagnostic logs
expire after 30 minutes; all job folders are removed on restart. Do not restart
while another process uses the same data directory. Logs can contain upstream
model diagnostics; do not publish them without reviewing for private content.
Model weights remain until explicitly removed. The backend does not save voice
profiles; Android's private local library owns those.

## Tests

```sh
.venv-backend/bin/python -m pytest backend/tests -q
```

These API/storage/security tests include real FFmpeg encoding and real process
cancellation, **not neural voice-cloning quality tests**. Real inference status
is documented separately in `docs/models.md`.
