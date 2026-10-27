# Model and reference-project evaluation

Evidence checked against upstream sources on 2026-10-27. Published model support,
an implemented API call, and a tested synthesis run are different claims.

## Reference project: DIGI LABS

Reviewed upstream README, LICENSE, `package.json`, `server/index.js` and
`server/engines/gemini-tts.js`:

- <https://github.com/digiformationltd-creator/digi-labs>
- <https://github.com/digiformationltd-creator/digi-labs/blob/main/LICENSE>

It is a Windows Electron/Node application, not an Android cloning engine. Its
production synthesis calls Gemini `gemini-2.5-flash-preview-tts` with a
`prebuiltVoiceConfig` selected from preset voice names. This does **not** establish
arbitrary reference-audio voice cloning. It transcodes 24 kHz PCM with FFmpeg and
segments long text. Free API-key access depends on Google's current quotas and
terms; it does not meet a guaranteed indefinitely free/offline engine requirement.

The DSAPL v1.0 is **source available**, with redistribution-for-financial-gain,
commercial white-label, and paid SaaS restrictions. No code, artwork, audio,
branding or documentation from DIGI LABS was copied into this project. Similar
general functions (segmentation, history, FFmpeg transcoding) were implemented
independently.

## Engine comparison

| Model | Bengali evidence | English | Reference cloning | License evidence | Android/CPU conclusion |
|---|---|---|---|---|---|
| Chatterbox / Multilingual | Official language list does not include Bengali | Yes | Yes, audio prompt | Upstream MIT | Python/PyTorch; no tested Bengali Android ARM64 pipeline. New Nano CPU claims are upstream claims, not this project's device benchmark. |
| OpenVoice V2 | Native list: English, Spanish, French, Chinese, Japanese, Korean; Bengali base TTS not supplied | Yes | Tone-color conversion using source TTS | Upstream MIT | Cross-lingual voice conversion alone does not produce Bengali from text; an independently validated Bengali base TTS is still required. Not chosen as a complete Bengali solution. |
| F5-TTS v1 Base | Official base model trained for Chinese/English; Bengali not established | Yes | Yes, reference WAV + transcript | Code MIT; weights CC-BY-NC-4.0 | Chosen for optional **personal/noncommercial English backend**. Python CPU integration; Android performance not established. |
| AI4Bharat IndicF5 | Official README and model card explicitly list **Bengali (`bn`)** among 11 Indian languages | Not in official supported language list | Yes, reference audio + accurate transcript | HF API model card declares MIT; source repo has no root LICENSE at reviewed revision | Chosen Bengali backend candidate; gated weights require account access acceptance. No real Bengali inference validated here; not an on-device implementation. |

Authoritative sources:

- <https://github.com/resemble-ai/chatterbox> (supported language list, model zoo)
- <https://github.com/resemble-ai/chatterbox/blob/master/LICENSE>
- <https://github.com/myshell-ai/OpenVoice> (native languages, MIT statement)
- <https://github.com/SWivid/F5-TTS> (installation/API/code and weight-license distinction)
- <https://huggingface.co/SWivid/F5-TTS> (weight license)
- <https://github.com/AI4Bharat/IndicF5> (Bengali/reference-transcript requirements)
- <https://huggingface.co/ai4bharat/IndicF5> (gated model, license metadata)
- <https://huggingface.co/charactr/vocos-mel-24khz> (MIT vocoder)

No model weights or upstream model code are bundled in the APK or redistributed
in this repository. Users must review the current model license before download.
F5 weights are not licensed for commercial use; this app's personal-use goal is
consistent with that limit. A model card declaration is recorded as evidence,
not a substitute for legal advice or a claim about all upstream training data.

## Verified download metadata

The backend resolves official Hugging Face API metadata into an immutable
revision, records exact sizes/checksums, and verifies each downloaded file. It
does not invent a URL/hash or trust mutable `main` during a download.

Metadata observed during this implementation:

| Asset | Immutable revision | Bytes |
|---|---|---:|
| IndicF5 primary `model.safetensors` | `fb652a96e508091045890dae5bb99fe511facbcf` | 1,402,789,408 |
| F5 v1 Base selected checkpoint + vocab | `84e5a410d9cead4de2f847e7c9369a6440bdfaca` | 1,348,449,561 |
| Vocos config + weights | `0feb3fdd929bcd6649e0e7c5a688cf7dd012ef21` | 54,366,452 |

IndicF5's complete snapshot additionally includes configuration/code/vocabulary;
the app displays its actual full selected download size after planning. The
primary checkpoint SHA-256 is
`ba7f3671180fb7784e24bd1dafc96e729a38ce02e7f6d3877cdef32525a1865c`.
F5 checkpoint SHA-256 is
`670900fd14e6c458b95da6e9ed317cdb20dbaf7a1c02ac06a05475a9d32b6a38`.
Vocos weight SHA-256 is
`97ec976ad1fd67a33ab2682d29c0ac7df85234fae875aefcc5fb215681a91b2a`.
These were read from the official API's LFS metadata, not generated guesses.

## Current capability boundary and hardware

There is **no verified phone-only Bengali reference-cloning runtime** in this
delivery. Packaging Python/PyTorch weights into a Flutter APK would not establish
Android compatibility, acceptable memory use, or useful speed. The app therefore
states that its inference adapter requires the explicitly configured optional
private-network backend; it does not show fake on-device generation.

Host software requirements: Linux, Python environments described in
`backend/README.md`, FFmpeg/ffprobe with `libmp3lame`, model storage, and permission
to download the selected weights. At least the above model bytes plus Python
runtime/dependencies and temporary output storage are needed. Exact minimum RAM,
inference speed, energy use, and voice quality have **not** been measured on an
Android ARM64 device. No fabricated minimum-RAM/performance number is provided.
Model file size is not peak inference RAM. A CPU-capable upstream API is not a
real-time performance guarantee. GPU recommendations from upstream are not a
requirement measured by this project.

Bengali access check returned HTTP 401 `GatedRepo` without an authorized backend
Hugging Face token. The model API confirms `gated: auto`; free access/terms must
be accepted at the model page before a backend token can retrieve weights.
Until that prerequisite and a compatible runtime are available, Bengali voice
similarity, pronunciation quality, and successful synthesis remain **unvalidated**.

## Actual validation results

**English real model inference passed** on the cloud Linux CPU host. The exact
adapter in `backend/worker.py` loaded the checksum-verified F5-TTS v1 Base and
Vocos weights through `f5_tts.api.F5TTS`, and conditioned generation on upstream's
bundled `basic_ref_en.wav` with transcript “Some call me nature, others call me
mother nature.” Target text was “This is synthetic speech from the private voice
studio.” This was an actual neural inference run, not mocked or prerecorded output.

- `f5-tts==1.1.22`, `torch==2.8.0+cpu`, `torchaudio==2.8.0+cpu`; Python 3.12.14.
- Exit status 0. Wall time **232.39 seconds** for **5.2267 seconds** of output.
- Peak process RSS **3,378,248 KiB** (about 3.22 GiB); Linux host CPU quota four
  cores, OMP/MKL thread counts four. These are observations of this run, **not
  minimum hardware requirements** or Android performance predictions.
- Output: 250,924-byte, 24 kHz, mono, 16-bit PCM WAV; all samples finite,
  RMS 0.1270. SHA-256:
  `941eb79f8f0d7733360a79ff5eccd30481b90787c5849d08b3b5fa56a35232c5`.
- Actual FFmpeg `libmp3lame` conversion succeeded; ffprobe confirmed MP3 codec,
  24 kHz, 5.28-second container duration (including codec delay).
- Subjective voice identity, accent quality and listening tests were **not**
  evaluated. Bengali inference and Android on-device inference were **not run**.

Backend validation: **36 automated tests passed**, including actual FFmpeg
encoding/decoding, corruption/duration checks, consent, authentication, upload
bounds, actual subprocess termination, generation failure cleanup, integrity
verification, safe paths, retry/removal/cancel states and Bengali segmentation.
Download transport tests use fixture data; they are not neural inference tests.
The separate English run above supplies real inference evidence. A dependency
audit after pin upgrades reported **zero known vulnerabilities** among 47
installed packages, including audit tools; this is a point-in-time advisory
check, not a guarantee against undiscovered vulnerabilities.

These results support the optional English backend integration. They do not
complete the primary requirement of Bengali cloning entirely on a phone.


A second genuine test exercised the full HTTP API after isolating Python with
`-I`: authenticated capability discovery, reference upload/decode, English model
job, polling, WAV retrieval, `/v1/convert` MP3 encoding, and job deletion. It
produced 4.5653 seconds of speech in 178.92 seconds and a 93,164-byte MP3;
post-deletion lookup correctly returned 404. The test used the upstream example
reference and a new synthesis sentence, not prerecorded output. It does not
assess subjective speaker similarity or Bengali pronunciation. A repository
`coverage/` directory initially shadowed an optional Python module; isolated
model subprocess imports corrected that integration failure.


## Separate inference dependency audit

The API audit is not a clean bill for the neural Python environment. A separate
installed-runtime audit found affected filelock, Pillow, pip and setuptools.
Updated pip 26.2.2 and setuptools 84.1.0, and selected filelock 3.20.3, which
satisfies cached-path's `<4` constraint and has no advisories in the checked
PyPI metadata. `pip check` passes. Pillow 12.3.0 still has **37 advisory records**
in the current feed; fixes require 13.0.0, while upstream Gradio 6.30.0 declares
`Pillow<13`. Installing 13 creates a dependency conflict, so that incompatible
change was reverted rather than concealed. This is a remaining upstream security
limitation of the optional inference runtime. No Gradio service is launched and
only audio uploads are accepted; no claim is made that this eliminates all risk.
`backend/requirements-f5.lock.txt` records the actual compatible environment.
Do not call this inference deployment production-secure until the upstream
constraint/advisory conflict is resolved and the model is revalidated.

After the compatible support-package repairs and the recorded inference lock,
the full genuine English HTTP/API test was repeated successfully: 4.5653 seconds
of new WAV speech, 160.98 seconds wall time, actual 93,164-byte MP3 conversion,
and confirmed private job deletion. `pip check` passed. The remaining Pillow
advisories above are unchanged; a successful synthesis test does not resolve them.
