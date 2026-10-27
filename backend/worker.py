"""One isolated process per request: terminating it really cancels inference.

This is real model integration, not a mock synthesizer. Separate Python virtual
environments avoid IndicF5's fork colliding with upstream f5_tts imports.
"""

import json
import os
import re
import sys
import unicodedata
from pathlib import Path


def segments(text, limit=250):
    result = []
    for sentence in re.split(r"(?<=[।.!?])\s+|\n+", text.strip()):
        while len(sentence) > limit:
            index = sentence.rfind(" ", 0, limit + 1)
            if index < 1:
                index = limit
                # Keep Bengali vowel signs/combining marks with their base.
                while index > 1 and (
                    unicodedata.category(sentence[index]).startswith("M")
                    or sentence[index] == "\u200d"
                    or sentence[index - 1] in {"\u09cd", "\u200d"}
                ):
                    index -= 1
            result.append(sentence[:index].strip())
            sentence = sentence[index:].strip()
        if sentence:
            result.append(sentence)
    return result


def run(spec):
    # All required files must already be installed. No hidden model download.
    os.environ["HF_HUB_OFFLINE"] = "1"
    os.environ["TRANSFORMERS_OFFLINE"] = "1"
    os.environ["HF_HUB_DISABLE_TELEMETRY"] = "1"
    os.environ["DO_NOT_TRACK"] = "1"
    os.environ["WANDB_MODE"] = "disabled"
    import numpy as np
    import soundfile as sf

    root = Path(spec["models"])
    if spec["language"] == "bn":
        from transformers import AutoModel

        # Only explicitly approved, pinned, verified snapshot code is executed.
        model = AutoModel.from_pretrained(
            str(root / "indicf5"), trust_remote_code=True, local_files_only=True
        )
        sample_rate = 24000

        def synthesize(text):
            return model(text, ref_audio_path=spec["reference"], ref_text=spec["reference_text"])
    else:
        from f5_tts.api import F5TTS

        model = F5TTS(
            model="F5TTS_v1_Base",
            ckpt_file=str(root / "f5/F5TTS_v1_Base/model_1250000.safetensors"),
            vocab_file=str(root / "f5/F5TTS_v1_Base/vocab.txt"),
            vocoder_local_path=str(root / "vocos"),
            device=os.environ.get("VOICE_DEVICE", "cpu"),
        )
        sample_rate = 24000

        def synthesize(text):
            audio, rate, _ = model.infer(ref_file=spec["reference"], ref_text=spec["reference_text"], gen_text=text)
            if rate != sample_rate:
                raise ValueError("Unexpected model sample rate")
            return audio

    chunks = segments(spec["text"])
    with sf.SoundFile(spec["output"], "w", samplerate=sample_rate, channels=1, subtype="PCM_16") as output:
        for index, text in enumerate(chunks):
            audio = np.asarray(synthesize(text))
            if audio.dtype == np.int16:
                audio = audio.astype(np.float32) / 32768.0
            audio = np.squeeze(audio).astype(np.float32)
            if audio.ndim != 1 or not audio.size or not np.isfinite(audio).all():
                raise ValueError("Model returned invalid audio")
            output.write(np.clip(audio, -1, 1))
            if index < len(chunks) - 1:
                output.write(np.zeros(int(sample_rate * 0.12), dtype=np.float32))
            Path(spec["progress"]).write_text(str((index + 1) / len(chunks)))


if __name__ == "__main__":
    run(json.loads(Path(sys.argv[1]).read_text()))
