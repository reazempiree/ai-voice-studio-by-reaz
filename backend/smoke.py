"""Run and validate genuine inference with explicitly supplied local assets.

Example (after model installation):
python -m backend.smoke --language en --models .voice-data/models \
  --python .venv-f5/bin/python --reference reference.wav \
  --reference-text "Exact reference transcript." --text "New speech." \
  --output synthetic.wav
"""

import argparse
import array
import json
import os
import resource
import subprocess
import tempfile
import time
import wave
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description="Real local model inference; never substitutes sample output")
    parser.add_argument("--language", choices=["bn", "en"], required=True)
    parser.add_argument("--models", type=Path, required=True)
    parser.add_argument("--python", type=Path, required=True)
    parser.add_argument("--reference", type=Path, required=True)
    parser.add_argument("--reference-text", required=True)
    parser.add_argument("--text", required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    if args.output.exists():
        parser.error("Output exists; choose a new path")
    spec = {"models": str(args.models.resolve()), "language": args.language, "reference": str(args.reference.resolve()), "reference_text": args.reference_text, "text": args.text, "output": str(args.output.resolve())}
    environment = dict(os.environ)
    for key in ("VOICE_BACKEND_TOKEN", "HF_TOKEN"):
        environment.pop(key, None)
    with tempfile.TemporaryDirectory(prefix="voice-smoke-") as folder:
        spec["progress"] = str(Path(folder) / "progress")
        request = Path(folder) / "request.json"
        request.write_text(json.dumps(spec))
        started = time.monotonic()
        # Preserve virtualenv executable symlinks; resolving to the base binary
        # would discard that environment's installed model dependencies.
        result = subprocess.run([str(args.python.absolute()), "-I", str(Path(__file__).with_name("worker.py").resolve()), str(request)], env=environment, timeout=1800)
        result.check_returncode()
        with wave.open(str(args.output), "rb") as audio:
            if audio.getnchannels() != 1 or audio.getsampwidth() != 2 or audio.getframerate() != 24000:
                raise ValueError("Unexpected output audio format")
            samples = array.array("h", audio.readframes(audio.getnframes()))
            if not samples or not any(samples):
                raise ValueError("Inference returned empty or silent audio")
            duration = len(samples) / audio.getframerate()
        print(json.dumps({"real_model_inference": True, "language": args.language, "duration_seconds": duration, "wall_seconds": time.monotonic() - started, "max_rss_kib": resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss, "subjective_quality_evaluated": False}))


if __name__ == "__main__":
    main()
