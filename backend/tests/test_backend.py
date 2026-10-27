import hashlib
import io
import json
import os
import subprocess
import sys
import threading
import time
import wave
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

os.environ.setdefault("VOICE_DATA_DIR", "/tmp/voice-studio-test-data")
from backend import app as service
from backend.models import ModelManager, safe_name, verify_file
from backend import models as model_module
from backend.worker import segments


@pytest.fixture
def client(monkeypatch, tmp_path):
    monkeypatch.setattr(service, "ROOT", tmp_path)
    monkeypatch.setattr(service, "TOKEN", "test-only-token-at-least-24-characters")
    monkeypatch.setattr(service, "manager", ModelManager(tmp_path / "models"))
    service.jobs.clear()
    service.plans.clear()
    with TestClient(service.app) as client:
        client.headers["Authorization"] = "Bearer test-only-token-at-least-24-characters"
        yield client


def wav_bytes(seconds=1):
    data = io.BytesIO()
    with wave.open(data, "wb") as sound:
        sound.setnchannels(1)
        sound.setsampwidth(2)
        sound.setframerate(24000)
        sound.writeframes(b"\0\0" * int(24000 * seconds))
    return data.getvalue()


def test_authentication_is_mandatory(client):
    assert client.get("/v1/capabilities", headers={"Authorization": "Bearer invalid"}).status_code == 401


def test_oversized_upload_rejected_before_spooling(client):
    response = client.post("/v1/jobs", content=b"x", headers={"Content-Length": str(27 * 1024 * 1024)})
    assert response.status_code == 413


def test_missing_server_token_does_not_open_service(client, monkeypatch):
    monkeypatch.setattr(service, "TOKEN", "")
    assert client.get("/v1/capabilities").status_code == 503


def test_capabilities_never_claim_uninstalled_inference(client, monkeypatch):
    monkeypatch.delenv("F5_PYTHON", raising=False)
    monkeypatch.delenv("INDICF5_PYTHON", raising=False)
    data = client.get("/v1/capabilities").json()
    assert data["languages"] == []
    assert not data["available"]
    assert not data["on_device"]
    assert all(not e["inference_validated"] for e in data["engines"])


def test_consent_required_before_generation(client):
    response = client.post("/v1/jobs", data={"text": "হ্যালো", "language": "bn", "reference_text": "আমার কণ্ঠ", "consent": "false"}, files={"audio": ("voice.wav", wav_bytes())})
    assert response.status_code == 422
    assert not service.jobs


@pytest.mark.parametrize("text,language,reference", [("", "bn", "কণ্ঠ"), ("hello", "xx", "voice"), ("hello", "en", ""), ("a" * 3001, "en", "voice")])
def test_generation_input_validation(client, text, language, reference):
    response = client.post("/v1/jobs", data={"text": text, "language": language, "reference_text": reference, "consent": "true"}, files={"audio": ("voice.wav", wav_bytes())})
    assert response.status_code == 422


def test_missing_engine_blocks_generation(client):
    response = client.post("/v1/jobs", data={"text": "হ্যালো", "language": "bn", "reference_text": "কণ্ঠ", "consent": "true"}, files={"audio": ("voice.wav", wav_bytes())})
    assert response.status_code == 503


def test_duplicate_generation_rejected(client, monkeypatch):
    monkeypatch.setattr(service, "engine_ready", lambda *_: True)
    service.generation_lock.acquire()
    try:
        response = client.post("/v1/jobs", data={"text": "hello", "language": "en", "reference_text": "voice", "consent": "true"}, files={"audio": ("voice.wav", wav_bytes())})
        assert response.status_code == 409
    finally:
        service.generation_lock.release()


def test_real_job_failure_surfaces_and_reference_is_deleted(client, monkeypatch, tmp_path):
    # The worker deliberately has no usable runtime; this tests failure cleanup,
    # NOT successful inference and NOT a mocked successful audio result.
    monkeypatch.setattr(service, "engine_ready", lambda *_: True)
    monkeypatch.setenv("F5_PYTHON", "/does-not-exist/python")
    response = client.post("/v1/jobs", data={"text": "hello", "language": "en", "reference_text": "voice", "consent": "true"}, files={"audio": ("voice.wav", wav_bytes())})
    assert response.status_code == 202
    key = response.json()["id"]
    for _ in range(100):
        result = client.get(f"/v1/jobs/{key}").json()
        if result["status"] == "failed" and not service.generation_lock.locked():
            break
        time.sleep(0.01)
    assert result["status"] == "failed"
    assert result["error"]
    assert not (tmp_path / "jobs" / key / "reference.wav").exists()
    assert not (tmp_path / "jobs" / key / "request.json").exists()
    assert client.get(f"/v1/jobs/{key}/audio").status_code == 409


def test_real_decoder_rejects_corrupted_audio(tmp_path):
    source = tmp_path / "corrupt.mp3"
    source.write_bytes(b"not valid audio")
    with pytest.raises(service.HTTPException) as error:
        service.probe_audio(source)
    assert error.value.status_code == 422


def test_real_decoder_reads_duration(tmp_path):
    source = tmp_path / "voice.wav"
    source.write_bytes(wav_bytes(2))
    assert service.probe_audio(source) == 2


def test_real_decoder_rejects_long_recording(tmp_path):
    source = tmp_path / "voice.wav"
    source.write_bytes(wav_bytes(31))
    with pytest.raises(service.HTTPException):
        service.probe_audio(source)


def test_mp3_conversion_is_real_and_temporary_upload_deleted(client):
    response = client.post("/v1/convert", files={"audio": ("voice.wav", wav_bytes())})
    assert response.status_code == 200
    assert response.headers["content-type"] == "audio/mpeg"
    assert not response.content.startswith(b"RIFF")
    probe = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "stream=codec_name", "-of", "json", "-"], input=response.content, capture_output=True, check=True)
    assert json.loads(probe.stdout)["streams"][0]["codec_name"] == "mp3"
    assert not list(service.ROOT.glob("convert-*"))


def test_invalid_export_has_readable_error(client):
    assert client.post("/v1/convert", files={"audio": ("voice.wav", b"broken")}).status_code == 422


def test_unknown_jobs_and_models(client):
    assert client.get("/v1/jobs/../../etc/passwd").status_code == 404
    assert client.get("/v1/jobs/missing").status_code == 404
    assert client.delete("/v1/models/unknown").status_code == 404


def test_model_size_not_fabricated(client):
    models = client.get("/v1/models").json()["models"]
    assert len(models) == 3
    assert all(m["status"] == "missing" and m["bytes"] == 0 and m["license"] == "unverified" for m in models)


def test_install_requires_authoritative_plan_and_consent(client):
    assert client.post("/v1/models/indicf5/install", json={"accept_license": True}).status_code == 422
    assert client.post("/v1/models/f5/install", json={"accept_license": True}).status_code == 409


def test_unverified_license_blocks_install(client):
    service.plans["f5"] = {"license": "unverified"}
    assert client.post("/v1/models/f5/install", json={"accept_license": True}).status_code == 409


@pytest.mark.parametrize("name", ["../model.bin", "/etc/passwd", "test/../../secret", "a\\..\\secret"])
def test_model_path_traversal_rejected(name):
    with pytest.raises(ValueError):
        safe_name(name)


def test_integrity_detects_corruption_and_truncation(tmp_path):
    file = tmp_path / "model"
    file.write_bytes(b"model-weights")
    entry = {"size": 13, "digest": hashlib.sha256(b"model-weights").hexdigest(), "algorithm": "sha256"}
    assert verify_file(file, entry)
    file.write_bytes(b"model-corrupt")
    assert not verify_file(file, entry)
    file.write_bytes(b"x")
    assert not verify_file(file, entry)


def test_git_blob_checksum(tmp_path):
    path = tmp_path / "config.json"
    path.write_bytes(b"{}")
    assert verify_file(path, {"size": 2, "digest": hashlib.sha1(b"blob 2\0{}").hexdigest(), "algorithm": "git-sha1"})


def test_model_installation_is_not_just_a_marker(tmp_path):
    manager = ModelManager(tmp_path)
    folder = tmp_path / "f5"
    folder.mkdir()
    (folder / "manifest.json").write_text(json.dumps({"files": [{"name": "weights.bin", "size": 1, "digest": "invalid", "algorithm": "sha256"}]}))
    assert not manager.installed("f5")


def sample_plan(data=b"verified-model"):
    return {"id": "f5", "repo": "SWivid/F5-TTS", "revision": "a" * 40, "license": "cc-by-nc-4.0", "bytes": len(data), "files": [{"name": "weights.bin", "size": len(data), "algorithm": "sha256", "digest": hashlib.sha256(data).hexdigest()}]}


def test_model_download_verifies_and_reuses_complete_files(tmp_path, monkeypatch):
    data = b"verified-model"
    calls = []
    def fetch(*args, **kwargs):
        calls.append(args)
        return io.BytesIO(data)
    monkeypatch.setattr(model_module.opener, "open", fetch)
    manager = ModelManager(tmp_path)
    plan = sample_plan(data)
    manager.states["f5"] = {"status": "downloading", "downloaded": 0}
    manager._download(plan, threading.Event())
    assert manager.states["f5"]["status"] == "installed"
    assert manager.installed("f5")
    assert len(calls) == 1
    manager.states["f5"] = {"status": "downloading", "downloaded": 0}
    manager._download(plan, threading.Event())
    assert len(calls) == 1
    assert manager.states["f5"]["downloaded"] == len(data)
    manager.remove("f5")
    assert not manager.installed("f5")


def test_corrupt_model_download_never_installs(tmp_path, monkeypatch):
    monkeypatch.setattr(model_module.opener, "open", lambda *a, **kw: io.BytesIO(b"corrupt-model!"))
    manager = ModelManager(tmp_path)
    manager.states["f5"] = {"status": "downloading", "downloaded": 0}
    manager._download(sample_plan(), threading.Event())
    assert manager.states["f5"]["status"] == "failed"
    assert not manager.installed("f5")
    assert not (tmp_path / "f5/manifest.json").exists()


def test_cancelled_download_never_installs(tmp_path, monkeypatch):
    monkeypatch.setattr(model_module.opener, "open", lambda *a, **kw: io.BytesIO(b"verified-model"))
    manager = ModelManager(tmp_path)
    manager.states["f5"] = {"status": "downloading", "downloaded": 0}
    cancel = threading.Event()
    cancel.set()
    manager._download(sample_plan(), cancel)
    assert manager.states["f5"]["status"] == "cancelled"
    assert not manager.installed("f5")


def test_model_detects_changed_weights_after_cached_verification(tmp_path, monkeypatch):
    monkeypatch.setattr(model_module.opener, "open", lambda *a, **kw: io.BytesIO(b"verified-model"))
    manager = ModelManager(tmp_path)
    manager.states["f5"] = {"status": "downloading", "downloaded": 0}
    manager._download(sample_plan(), threading.Event())
    assert manager.installed("f5")
    (tmp_path / "f5/weights.bin").write_bytes(b"modified-model")
    assert not manager.installed("f5")


def test_segmentation_preserves_bengali_text_and_punctuation():
    text = "এটি আমার কণ্ঠ। এটি একটি পরীক্ষা! Bengali বাংলা।"
    chunks = segments(text, 25)
    assert all(len(chunk) <= 25 for chunk in chunks)
    assert " ".join(chunks) == text


def test_long_unbroken_text_has_bounded_segments():
    assert segments("ক" * 501) == ["ক" * 250, "ক" * 250, "ক"]


def test_segmentation_keeps_bengali_vowel_signs_with_base():
    chunks = segments("কা" * 200, 249)
    assert all(not chunk.startswith("া") for chunk in chunks)
    assert "".join(chunks) == "কা" * 200


def test_cancellation_terminates_actual_process(client, tmp_path):
    process = subprocess.Popen([sys.executable, "-c", "import time; time.sleep(60)"])
    folder = tmp_path / "job"
    folder.mkdir()
    service.jobs["test"] = {"id": "test", "status": "running", "progress": 0, "created": time.time(), "process": process, "folder": folder, "cancel": threading.Event()}
    response = client.delete("/v1/jobs/test")
    assert response.status_code == 200
    assert process.poll() is not None
    assert not folder.exists()
