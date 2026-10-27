"""Private, opt-in inference API. Start with python -m backend.app."""

import asyncio
import hmac
import json
import os
import shutil
import subprocess
import sys
import threading
import time
import tempfile
import uuid
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import Depends, FastAPI, File, Form, Header, HTTPException, UploadFile
from fastapi.responses import FileResponse
from starlette.background import BackgroundTask
from pydantic import BaseModel

from backend.models import SOURCES, ModelManager, metadata

ROOT = Path(os.environ.get("VOICE_DATA_DIR", "./.voice-data")).resolve()
ROOT.mkdir(mode=0o700, parents=True, exist_ok=True)
TOKEN = os.environ.get("VOICE_BACKEND_TOKEN", "")
manager = ModelManager(ROOT / "models")
jobs = {}
plans = {}
generation_lock = threading.Lock()


def authorize(authorization: str | None = Header(default=None)):
    if not TOKEN or len(TOKEN) < 24:
        raise HTTPException(503, "Set VOICE_BACKEND_TOKEN to a random token of at least 24 characters")
    if not authorization or not hmac.compare_digest(authorization, f"Bearer {TOKEN}"):
        raise HTTPException(401, "Authentication required")


@asynccontextmanager
async def lifespan(_app):
    # Never resume uploads or unfinished synthesis after termination. Temporary
    # recordings and outputs are session-only and expire after 30 minutes.
    shutil.rmtree(ROOT / "jobs", ignore_errors=True)
    (ROOT / "jobs").mkdir(mode=0o700)
    async def cleanup():
        while True:
            await asyncio.sleep(60)
            for key, job in list(jobs.items()):
                if time.time() - job["created"] > 1800:
                    cancel_job(job)
                    shutil.rmtree(job["folder"], ignore_errors=True)
                    jobs.pop(key, None)
    task = asyncio.create_task(cleanup())
    yield
    task.cancel()
    for job in list(jobs.values()):
        cancel_job(job)
        shutil.rmtree(job["folder"], ignore_errors=True)
    jobs.clear()


app = FastAPI(title="AI Voice Studio private backend", version="1.0.0", dependencies=[Depends(authorize)], lifespan=lifespan)


class UploadLimit:
    """Reject large bodies including chunked uploads before multipart spooling."""
    def __init__(self, app):
        self.app = app

    async def __call__(self, scope, receive, send):
        if scope["type"] != "http":
            return await self.app(scope, receive, send)
        limit = (101 if scope["path"] == "/v1/convert" else 26) * 1024 * 1024
        headers = dict(scope.get("headers", []))
        try:
            declared = int(headers.get(b"content-length", b"0"))
        except ValueError:
            declared = limit + 1
        if declared > limit:
            from starlette.responses import JSONResponse
            return await JSONResponse({"detail": "Upload exceeds allowed size"}, 413)(scope, receive, send)
        total = 0
        async def bounded_receive():
            nonlocal total
            message = await receive()
            total += len(message.get("body", b""))
            if total > limit:
                raise HTTPException(413, "Upload exceeds allowed size")
            return message
        await self.app(scope, bounded_receive, send)


app.add_middleware(UploadLimit)


def engine_ready(language, full=False):
    variable = "INDICF5_PYTHON" if language == "bn" else "F5_PYTHON"
    interpreter = os.environ.get(variable)
    required = ["indicf5"] if language == "bn" else ["f5", "vocos"]
    # Cached status is insufficient: verify model integrity before each request.
    return bool(interpreter and Path(interpreter).is_file() and all(manager.installed(engine, full=full) for engine in required))


@app.get("/v1/capabilities")
def capabilities():
    engines = [{"id": "indicf5" if lang == "bn" else "f5", "language": lang, "available": engine_ready(lang), "requires_reference_text": True, "inference_validated": False} for lang in ("bn", "en")]
    return {"languages": [e["language"] for e in engines if e["available"]], "available": any(e["available"] for e in engines), "engines": engines, "on_device": False, "reason": "Optional local-network backend; model inference must be validated on the selected host", "max_characters": 3000, "max_reference_seconds": 30, "formats": ["wav", "mp3"] if shutil.which("ffmpeg") else ["wav"]}


@app.get("/v1/models")
def model_list():
    result = []
    for key, repo in SOURCES.items():
        state = manager.states.get(key, {})
        plan = plans.get(key, {})
        if not plan:
            try:
                plan = json.loads((manager.root / key / "manifest.json").read_text())
            except (OSError, ValueError):
                plan = {}
        result.append({"id": key, "name": repo, "status": state.get("status", "installed" if manager.installed(key) else "missing"), "bytes": plan.get("bytes", state.get("bytes", 0)), "total_bytes": plan.get("bytes", state.get("bytes", 0)), "downloaded": state.get("downloaded", 0), "downloaded_bytes": state.get("downloaded", 0), "license": plan.get("license", "unverified"), "error": state.get("error")})
    return {"models": result}


def known_model(engine):
    if engine not in SOURCES:
        raise HTTPException(404, "Unknown model")


@app.post("/v1/models/{engine}/plan")
def plan_model(engine: str):
    known_model(engine)
    try:
        plan = metadata(engine)
        plans[engine] = plan
        return plan
    except Exception:
        raise HTTPException(502, "Model metadata unavailable; verify Hugging Face network access. No download started.")


class InstallConsent(BaseModel):
    accept_license: bool = False
    accept_remote_code: bool = False


@app.post("/v1/models/{engine}/install", status_code=202)
def install_model(engine: str, consent: InstallConsent):
    known_model(engine)
    if generation_lock.locked():
        raise HTTPException(409, "Cancel generation before changing models")
    if not consent.accept_license or (engine == "indicf5" and not consent.accept_remote_code):
        raise HTTPException(422, "Explicit license and custom-code acceptance required")
    plan = plans.get(engine)
    if not plan:
        raise HTTPException(409, "Fetch authoritative size and checksums first using /plan")
    expected_license = "cc-by-nc-4.0" if engine == "f5" else "mit"
    if plan["license"] != expected_license:
        raise HTTPException(409, "Model license is unverified or changed; installation blocked")
    try:
        manager.install(plan)
    except ValueError as error:
        raise HTTPException(409, str(error))
    return manager.states[engine]


@app.delete("/v1/models/{engine}")
def remove_model(engine: str):
    known_model(engine)
    if generation_lock.locked():
        raise HTTPException(409, "Cancel generation before removing models")
    return manager.remove(engine)


def probe_audio(path):
    try:
        result = subprocess.run(["ffprobe", "-v", "error", "-protocol_whitelist", "file,pipe", "-show_entries", "format=duration,format_name", "-of", "json", str(path)], capture_output=True, timeout=20, check=True)
        info = json.loads(result.stdout)["format"]
        if not set(info["format_name"].split(",")) & {"wav", "mp3", "mov", "m4a"}:
            raise ValueError("Unsupported audio container")
        duration = float(info["duration"])
        if not 0.5 <= duration <= 30:
            raise ValueError("Reference audio must be between 0.5 and 30 seconds")
        return duration
    except (subprocess.SubprocessError, KeyError, ValueError, OSError):
        raise HTTPException(422, "Unreadable reference audio or duration outside 0.5–30 seconds")


@app.post("/v1/jobs", status_code=202)
async def create_job(audio: UploadFile = File(...), text: str = Form(...), language: str = Form(...), reference_text: str = Form(...), consent: bool = Form(False)):
    if not consent:
        raise HTTPException(422, "Permission to clone and send reference audio is required")
    if language not in {"bn", "en"} or not text.strip() or len(text) > 3000 or not reference_text.strip() or len(reference_text) > 1000:
        raise HTTPException(422, "Invalid language, text, or reference transcript")
    if not await asyncio.to_thread(engine_ready, language, True):
        raise HTTPException(503, "Install verified models and configure the corresponding inference Python environment first")
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        raise HTTPException(503, "FFmpeg and ffprobe are required")
    if not generation_lock.acquire(blocking=False):
        raise HTTPException(409, "A generation is already running")
    key = uuid.uuid4().hex
    folder = ROOT / "jobs" / key
    uploaded = folder / "reference.upload"
    try:
        folder.mkdir(mode=0o700, parents=True)
        count = 0
        with uploaded.open("wb") as output:
            while block := await audio.read(1024 * 1024):
                count += len(block)
                if count > 25 * 1024 * 1024:
                    raise HTTPException(413, "Reference exceeds 25 MiB")
                output.write(block)
        if count == 0:
            raise HTTPException(422, "Reference is empty")
        await asyncio.to_thread(probe_audio, uploaded)
        reference = folder / "reference.wav"
        await asyncio.to_thread(subprocess.run, ["ffmpeg", "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe", "-i", str(uploaded), "-t", "30", "-ac", "1", "-ar", "24000", "-c:a", "pcm_s16le", str(reference)], check=True, timeout=30, capture_output=True)
        uploaded.unlink()
        spec = {"text": text.strip(), "language": language, "reference_text": reference_text.strip(), "reference": str(reference), "models": str(manager.root), "output": str(folder / "audio.wav"), "progress": str(folder / "progress")}
        (folder / "request.json").write_text(json.dumps(spec))
        job = {"id": key, "status": "queued", "progress": 0, "created": time.time(), "folder": folder, "process": None, "cancel": threading.Event()}
        jobs[key] = job
        threading.Thread(target=execute, args=(job, language), daemon=True).start()
        return public_job(job)
    except Exception as error:
        generation_lock.release()
        shutil.rmtree(folder, ignore_errors=True)
        if isinstance(error, subprocess.SubprocessError):
            raise HTTPException(422, "Reference audio decoding failed") from error
        if isinstance(error, OSError) and error.errno == 28:
            raise HTTPException(507, "Insufficient backend storage") from error
        raise
    finally:
        await audio.close()


def execute(job, language):
    folder = job["folder"]
    try:
        if job["cancel"].is_set():
            return
        job["status"] = "running"
        interpreter = os.environ["INDICF5_PYTHON" if language == "bn" else "F5_PYTHON"]
        with (folder / "error.log").open("wb") as errors:
            worker_env = dict(os.environ)
            for variable in ("HF_TOKEN", "VOICE_BACKEND_TOKEN"):
                worker_env.pop(variable, None)
            process = subprocess.Popen([interpreter, "-I", str(Path(__file__).with_name("worker.py").resolve()), str(folder / "request.json")], cwd=folder, stdout=subprocess.DEVNULL, stderr=errors, start_new_session=True, env=worker_env)
            job["process"] = process
            if job["cancel"].is_set():
                process.kill()
            code = process.wait(timeout=1800)
        if job["cancel"].is_set():
            job["status"] = "cancelled"
        elif code:
            job.update(status="failed", error="Inference failed. Check the private backend error.log for missing dependencies, unsupported hardware, model initialization, or memory errors.")
        else:
            path = folder / "audio.wav"
            with __import__("wave").open(str(path), "rb") as sound:
                duration = sound.getnframes() / sound.getframerate()
            if duration <= 0:
                raise ValueError("Empty inference output")
            job.update(status="completed", progress=1.0, duration_seconds=duration)
    except subprocess.TimeoutExpired:
        if job.get("process"):
            job["process"].kill()
            job["process"].wait()
        job.update(status="failed", error="Generation exceeded 30 minutes")
    except Exception:
        job.update(status="failed", error="Generation failed; check model installation, available memory and backend logs")
    finally:
        # Reference recordings and source text are not retained after inference.
        for name in ("reference.wav", "request.json"):
            (folder / name).unlink(missing_ok=True)
        if job["cancel"].is_set():
            (folder / "audio.wav").unlink(missing_ok=True)
            job["status"] = "cancelled"
            shutil.rmtree(folder, ignore_errors=True)
            jobs.pop(job["id"], None)
        generation_lock.release()


def get_job(key):
    job = jobs.get(key)
    if not job:
        raise HTTPException(404, "Job not found or expired")
    return job


def public_job(job):
    progress = job["folder"] / "progress"
    if progress.is_file():
        try:
            job["progress"] = float(progress.read_text())
        except ValueError:
            pass
    return {key: job[key] for key in ("id", "status", "progress", "error", "duration_seconds") if key in job}


def cancel_job(job):
    job["cancel"].set()
    process = job.get("process")
    if process and process.poll() is None:
        process.kill()
    job["status"] = "cancelled"


@app.get("/v1/jobs/{key}")
def job_status(key: str):
    return public_job(get_job(key))


@app.delete("/v1/jobs/{key}")
def delete_job(key: str):
    job = get_job(key)
    cancel_job(job)
    process = job.get("process")
    if process:
        try:
            process.wait(timeout=10)
        except subprocess.TimeoutExpired:
            raise HTTPException(409, "Cancellation is still in progress")
    # Worker owns active paths until it has finished cleanup.
    if not generation_lock.locked():
        shutil.rmtree(job["folder"], ignore_errors=True)
        jobs.pop(key, None)
    return {"id": key, "status": "cancelled"}


@app.get("/v1/jobs/{key}/audio")
def audio_file(key: str, format: str = "wav"):
    job = get_job(key)
    if job["status"] != "completed":
        raise HTTPException(409, "Audio is not ready")
    if format not in {"wav", "mp3"}:
        raise HTTPException(422, "Only WAV and MP3 are supported")
    path = job["folder"] / f"audio.{format}"
    if format == "mp3" and not path.exists():
        try:
            subprocess.run(["ffmpeg", "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe", "-i", str(job["folder"] / "audio.wav"), "-c:a", "libmp3lame", "-b:a", "192k", str(path)], timeout=60, check=True, capture_output=True)
        except (OSError, subprocess.SubprocessError):
            path.unlink(missing_ok=True)
            raise HTTPException(500, "MP3 encoder unavailable; WAV is still available")
    return FileResponse(path, media_type="audio/wav" if format == "wav" else "audio/mpeg", filename=f"synthetic-{key}.{format}", headers={"Cache-Control": "no-store", "X-Synthetic-Audio": "true"})


@app.post("/v1/convert")
async def convert_audio(audio: UploadFile = File(...)):
    if not shutil.which("ffmpeg"):
        raise HTTPException(503, "FFmpeg is required for MP3 conversion")
    folder = Path(tempfile.mkdtemp(prefix="convert-", dir=ROOT))
    source = folder / "input.wav"
    target = folder / "synthetic.mp3"
    try:
        count = 0
        with source.open("wb") as output:
            while block := await audio.read(1024 * 1024):
                count += len(block)
                if count > 100 * 1024 * 1024:
                    raise HTTPException(413, "Conversion input exceeds 100 MiB")
                output.write(block)
        import wave
        try:
            with wave.open(str(source), "rb") as sound:
                duration = sound.getnframes() / sound.getframerate()
                if not 0 < duration <= 1200:
                    raise ValueError("Audio duration outside limit")
        except (wave.Error, EOFError, ValueError):
            raise HTTPException(422, "Expected a valid PCM WAV of at most 20 minutes")
        try:
            await asyncio.to_thread(subprocess.run, ["ffmpeg", "-nostdin", "-v", "error", "-protocol_whitelist", "file,pipe", "-i", str(source), "-c:a", "libmp3lame", "-b:a", "192k", str(target)], timeout=120, check=True, capture_output=True)
        except (OSError, subprocess.SubprocessError):
            raise HTTPException(500, "MP3 encoding failed")
        return FileResponse(target, media_type="audio/mpeg", filename="synthetic.mp3", headers={"Cache-Control": "no-store"}, background=BackgroundTask(shutil.rmtree, folder, ignore_errors=True))
    except Exception:
        shutil.rmtree(folder, ignore_errors=True)
        raise
    finally:
        await audio.close()


if __name__ == "__main__":
    if len(TOKEN) < 24:
        sys.exit("Set VOICE_BACKEND_TOKEN to a securely generated token of at least 24 characters")
    import uvicorn
    uvicorn.run(app, host=os.environ.get("VOICE_BIND_HOST", "127.0.0.1"), port=int(os.environ.get("VOICE_PORT", "8765")))
