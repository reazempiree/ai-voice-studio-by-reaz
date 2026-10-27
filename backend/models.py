"""Explicit, integrity-checked model installation. Never downloads at startup."""

import hashlib
import json
import os
import shutil
import threading
import urllib.parse
import urllib.request
from pathlib import Path, PurePosixPath


SOURCES = {
    "indicf5": "ai4bharat/IndicF5",
    "f5": "SWivid/F5-TTS",
    "vocos": "charactr/vocos-mel-24khz",
}


class SafeRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        parsed = urllib.parse.urlparse(newurl)
        if parsed.scheme != "https":
            raise ValueError("Non-HTTPS model redirect rejected")
        redirected = super().redirect_request(req, fp, code, msg, headers, newurl)
        if parsed.hostname != urllib.parse.urlparse(req.full_url).hostname:
            redirected.remove_header("Authorization")
        return redirected


opener = urllib.request.build_opener(SafeRedirect())


def request(url: str):
    headers = {"User-Agent": "AI-Voice-Studio/1.0"}
    # Optional gated-model access. Values never enter files, logs, or clients.
    token = os.environ.get("HF_TOKEN")
    if token:
        headers["Authorization"] = f"Bearer {token}"
    return urllib.request.Request(url, headers=headers)


def safe_name(name: str) -> str:
    path = PurePosixPath(name)
    if path.is_absolute() or ".." in path.parts or "\\" in name or not path.parts:
        raise ValueError("Unsafe model filename")
    return name


def selected(engine: str, name: str) -> bool:
    if engine == "f5":
        return name in {"F5TTS_v1_Base/model_1250000.safetensors", "F5TTS_v1_Base/vocab.txt"}
    if engine == "vocos":
        return name in {"config.yaml", "pytorch_model.bin"}
    # IndicF5 uses Hugging Face custom code; source files stay alongside weights.
    return name.endswith((".json", ".py", ".safetensors", ".txt", ".yaml", ".bin", ".pt")) and not name.startswith(("samples/", "prompts/"))


def metadata(engine: str) -> dict:
    repo = SOURCES[engine]
    url = f"https://huggingface.co/api/models/{repo}/revision/main?blobs=true"
    with opener.open(request(url), timeout=30) as response:
        result = json.load(response)
    revision = result["sha"]
    if len(revision) != 40 or any(c not in "0123456789abcdef" for c in revision):
        raise ValueError("Invalid immutable model revision")
    files = []
    for item in result["siblings"]:
        name = safe_name(item["rfilename"])
        if selected(engine, name):
            lfs = item.get("lfs") or {}
            digest = lfs.get("sha256") or item.get("blobId")
            size = item.get("size", lfs.get("size"))
            if not digest or size is None:
                raise ValueError("Authoritative file size/checksum unavailable")
            files.append({"name": name, "size": size, "digest": digest, "algorithm": "sha256" if lfs else "git-sha1"})
    if not files:
        raise ValueError("No compatible model files found")
    return {"id": engine, "repo": repo, "revision": revision, "license": result.get("cardData", {}).get("license", "unverified"), "gated": bool(result.get("gated")), "bytes": sum(f["size"] for f in files), "files": files}


def verify_file(path: Path, entry: dict) -> bool:
    if not path.is_file() or path.stat().st_size != entry["size"]:
        return False
    digest = hashlib.sha256() if entry["algorithm"] == "sha256" else hashlib.sha1()
    if entry["algorithm"] == "git-sha1":
        digest.update(f"blob {entry['size']}\0".encode())
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest() == entry["digest"]


class ModelManager:
    def __init__(self, root: Path):
        self.root = root
        self.root.mkdir(parents=True, exist_ok=True)
        self.states = {}
        self.cancellations = {}
        self.lock = threading.Lock()
        self.verified = {}

    def installed(self, engine: str, full: bool = False) -> bool:
        path = self.root / engine / "manifest.json"
        try:
            manifest = json.loads(path.read_text())
            fingerprints = [(path.stat().st_mtime_ns, path.stat().st_size)]
            for entry in manifest["files"]:
                item = path.parent / safe_name(entry["name"])
                fingerprints.append((item.stat().st_mtime_ns, item.stat().st_size))
            if not full and self.verified.get(engine) == fingerprints:
                return True
            valid = bool(manifest["files"]) and all(verify_file(path.parent / safe_name(f["name"]), f) for f in manifest["files"])
            if valid:
                self.verified[engine] = fingerprints
            return valid
        except (OSError, ValueError, KeyError, TypeError):
            return False

    def install(self, plan: dict):
        engine = plan["id"]
        with self.lock:
            if self.states.get(engine, {}).get("status") == "downloading":
                raise ValueError("Download already in progress")
            event = threading.Event()
            self.cancellations[engine] = event
            self.states[engine] = {"id": engine, "status": "downloading", "downloaded": 0, "bytes": plan["bytes"]}
        threading.Thread(target=self._download, args=(plan, event), daemon=True).start()

    def _download(self, plan: dict, cancel: threading.Event):
        engine = plan["id"]
        folder = self.root / engine
        folder.mkdir(exist_ok=True)
        state = self.states[engine]
        try:
            if shutil.disk_usage(self.root).free < plan["bytes"] + 512 * 1024 * 1024:
                raise ValueError("Insufficient storage")
            for entry in plan["files"]:
                target = folder / safe_name(entry["name"])
                target.parent.mkdir(parents=True, exist_ok=True)
                if verify_file(target, entry):
                    state["downloaded"] += entry["size"]
                    continue
                url = f"https://huggingface.co/{plan['repo']}/resolve/{plan['revision']}/{urllib.parse.quote(entry['name'], safe='/')}"
                partial = target.with_name(target.name + ".partial")
                with opener.open(request(url), timeout=60) as response, partial.open("wb") as output:
                    while block := response.read(1024 * 1024):
                        if cancel.is_set():
                            raise InterruptedError("Download cancelled")
                        output.write(block)
                        state["downloaded"] += len(block)
                        if output.tell() > entry["size"]:
                            raise ValueError("Model download exceeds declared size")
                if not verify_file(partial, entry):
                    partial.unlink(missing_ok=True)
                    raise ValueError("Model checksum mismatch")
                os.replace(partial, target)
            if cancel.is_set():
                raise InterruptedError("Download cancelled")
            temp = folder / "manifest.partial"
            temp.write_text(json.dumps(plan))
            os.replace(temp, folder / "manifest.json")
            state["status"] = "installed"
        except Exception as error:
            state.update(status="cancelled" if cancel.is_set() else "failed", error=str(error))

    def remove(self, engine: str):
        event = self.cancellations.get(engine)
        if event and self.states.get(engine, {}).get("status") == "downloading":
            event.set()
            return {"id": engine, "status": "cancelling"}
        shutil.rmtree(self.root / engine, ignore_errors=True)
        self.states.pop(engine, None)
        return {"id": engine, "status": "missing"}
