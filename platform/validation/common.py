"""Shared helpers for validation runners."""

from __future__ import annotations

import json
import os
import platform
import shutil
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path

VAL_DIR = Path(__file__).resolve().parent
REPO_ROOT = VAL_DIR.parents[1]
REPORTS = VAL_DIR / "reports"
DATA = VAL_DIR / "data"


def now_iso() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def stamp() -> str:
    return datetime.now().strftime("%Y%m%d_%H%M%S")


def write_json(path: Path, obj) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(obj, indent=2, ensure_ascii=False, default=str))


def load_json(path: Path):
    return json.loads(path.read_text())


def host_info() -> dict:
    info = {
        "machine": platform.machine(),
        "platform": platform.platform(),
        "python": platform.python_version(),
        "processor": platform.processor(),
        "cwd": os.getcwd(),
        "conda_prefix": os.environ.get("CONDA_PREFIX"),
        "conda_default_env": os.environ.get("CONDA_DEFAULT_ENV"),
    }
    try:
        uname = subprocess.check_output(["uname", "-a"], text=True).strip()
        info["uname"] = uname
    except Exception as e:  # noqa: BLE001
        info["uname_error"] = str(e)
    return info


def run_cmd(cmd: list[str] | str, timeout: int = 60, shell: bool = False) -> dict:
    t0 = time.time()
    try:
        p = subprocess.run(
            cmd,
            shell=shell,
            capture_output=True,
            text=True,
            timeout=timeout,
            check=False,
        )
        return {
            "cmd": cmd if isinstance(cmd, str) else " ".join(cmd),
            "returncode": p.returncode,
            "stdout": (p.stdout or "")[:4000],
            "stderr": (p.stderr or "")[:4000],
            "elapsed_s": round(time.time() - t0, 3),
            "error": None,
        }
    except subprocess.TimeoutExpired as e:
        return {
            "cmd": cmd if isinstance(cmd, str) else " ".join(cmd),
            "returncode": None,
            "stdout": (e.stdout or "")[:4000] if isinstance(e.stdout, str) else "",
            "stderr": (e.stderr or "")[:4000] if isinstance(e.stderr, str) else "",
            "elapsed_s": round(time.time() - t0, 3),
            "error": "TimeoutExpired",
        }
    except Exception as e:  # noqa: BLE001
        return {
            "cmd": cmd if isinstance(cmd, str) else " ".join(cmd),
            "returncode": None,
            "stdout": "",
            "stderr": "",
            "elapsed_s": round(time.time() - t0, 3),
            "error": f"{type(e).__name__}: {e}",
        }


def which(name: str) -> str | None:
    return shutil.which(name)


def classify_elf(path: str) -> dict:
    """Use `file -L` to detect ELF architecture (follow symlinks)."""
    # Resolve symlinks so we inspect the real ELF
    try:
        real = str(Path(path).resolve())
    except Exception:  # noqa: BLE001
        real = path
    r = run_cmd(["file", "-b", "-L", real], timeout=10)
    text = (r.get("stdout") or "").strip()
    arch = "unknown"
    if "ARM aarch64" in text or "ARM64" in text or "aarch64" in text:
        arch = "aarch64"
    elif "x86-64" in text or "x86_64" in text:
        arch = "x86_64"
    elif "Intel 80386" in text:
        arch = "i386"
    elif any(x in text for x in ("Perl script", "Python script", "shell script", "ASCII text")):
        arch = "script"
    host = platform.machine()
    runnable = True
    status = "PASS"
    note = text
    if arch == "x86_64" and host in ("aarch64", "arm64"):
        runnable = False
        status = "FAIL_ARM"
        note = f"x86_64 binary on {host}: {text}"
    elif arch == "i386" and host in ("aarch64", "arm64"):
        runnable = False
        status = "FAIL_ARM"
        note = f"i386 binary on {host}: {text}"
    elif arch == "unknown" and host in ("aarch64", "arm64"):
        # Try executing --version briefly; Exec format error => FAIL_ARM
        smoke = run_cmd([real], timeout=5)
        blob = (smoke.get("stderr") or "") + (smoke.get("error") or "")
        if "Exec format error" in blob or "cannot execute binary file" in blob:
            runnable = False
            status = "FAIL_ARM"
            note = f"unknown arch but Exec format error on {host}: {text}"
    return {
        "path": path,
        "resolved": real,
        "file": text,
        "arch": arch,
        "runnable_on_host": runnable,
        "status": status,
        "note": note,
        "file_cmd": r,
    }
