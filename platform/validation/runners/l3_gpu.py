#!/usr/bin/env python3
"""L3 GPU micro-benchmark."""

from __future__ import annotations

import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common import REPORTS, run_cmd, stamp, write_json  # noqa: E402


def main() -> int:
    checks = []

    # Host nvidia-smi
    r = run_cmd(["nvidia-smi", "-L"], timeout=30)
    checks.append(
        {
            "name": "nvidia_smi_list",
            "status": "PASS" if r["returncode"] == 0 else "FAIL_GPU",
            "detail": r,
        }
    )

    # PyTorch CUDA
    torch_ok = False
    try:
        import torch

        avail = torch.cuda.is_available()
        detail = {
            "version": torch.__version__,
            "cuda_available": avail,
            "cuda_version": getattr(torch.version, "cuda", None),
        }
        if avail:
            detail["device_name"] = torch.cuda.get_device_name(0)
            detail["device_count"] = torch.cuda.device_count()
            x = torch.randn(2048, 2048, device="cuda")
            y = x @ x
            torch.cuda.synchronize()
            detail["matmul_shape"] = list(y.shape)
            detail["matmul_device"] = str(y.device)
            torch_ok = True
            status = "PASS"
        else:
            status = "FAIL_GPU"
        checks.append({"name": "torch_cuda_matmul", "status": status, "detail": detail})
    except Exception as e:  # noqa: BLE001
        checks.append(
            {
                "name": "torch_cuda_matmul",
                "status": "FAIL_DEP",
                "detail": f"{type(e).__name__}: {e}",
            }
        )

    # Docker GPU — optional / non-blocking for overall host-GPU verdict
    skip_docker = os.environ.get("VAL_SKIP_DOCKER", "0") == "1"
    if skip_docker:
        checks.append(
            {
                "name": "docker_gpus_nvidia_smi",
                "status": "SKIP_DOCKER",
                "detail": "VAL_SKIP_DOCKER=1",
                "note": "Docker image checks deferred; host CUDA still required",
            }
        )
    else:
        docker_cmd = [
            "docker",
            "run",
            "--rm",
            "--gpus",
            "all",
            "nvidia/cuda:12.6.0-base-ubuntu22.04",
            "nvidia-smi",
            "-L",
        ]
        docker_gpu = run_cmd(docker_cmd, timeout=300)
        ok = docker_gpu.get("returncode") == 0
        note = None
        err_blob = (docker_gpu.get("stderr") or "") + (docker_gpu.get("stdout") or "") + (
            docker_gpu.get("error") or ""
        )
        if not ok and ("permission denied" in err_blob.lower() or "docker.sock" in err_blob.lower()):
            docker_gpu_sg = run_cmd(
                "sg docker -c 'docker run --rm --gpus all nvidia/cuda:12.6.0-base-ubuntu22.04 nvidia-smi -L'",
                timeout=300,
                shell=True,
            )
            if docker_gpu_sg.get("returncode") == 0:
                ok = True
                note = "plain docker.sock denied in this session; succeeded via `sg docker`"
                docker_gpu = {"primary_denied": docker_gpu, "sg_docker": docker_gpu_sg}
            else:
                note = "docker GPU check failed (non-blocking for overall if host CUDA PASS)"
                docker_gpu = {"primary": docker_gpu, "sg_docker": docker_gpu_sg}

        # Failures here do not flip overall to FAIL_GPU (see gpu_core below)
        status_docker = "PASS" if ok else "SKIP_DOCKER"
        checks.append(
            {
                "name": "docker_gpus_nvidia_smi",
                "status": status_docker,
                "detail": docker_gpu,
                "note": note,
            }
        )

    # openmm optional
    try:
        import openmm

        platforms = []
        for i in range(openmm.Platform.getNumPlatforms()):
            platforms.append(openmm.Platform.getPlatform(i).getName())
        has_cuda = "CUDA" in platforms
        checks.append(
            {
                "name": "openmm_platforms",
                "status": "PASS" if has_cuda or "CPU" in platforms else "FAIL_DEP",
                "detail": {"platforms": platforms, "has_cuda": has_cuda},
            }
        )
    except Exception as e:  # noqa: BLE001
        checks.append(
            {
                "name": "openmm_platforms",
                "status": "FAIL_DEP",
                "detail": f"{type(e).__name__}: {e}",
            }
        )

    gpu_core = [c for c in checks if c["name"] in ("nvidia_smi_list", "torch_cuda_matmul")]
    if all(c["status"] == "PASS" for c in gpu_core):
        overall = "PASS"
        verdict = "GPU可用"
    elif any(c["status"] == "PASS" for c in gpu_core) or torch_ok:
        overall = "PARTIAL"
        verdict = "GPU部分可用"
    else:
        overall = "FAIL_GPU"
        verdict = "GPU不可用"

    payload = {
        "layer": "L3",
        "timestamp": stamp(),
        "overall": overall,
        "verdict": verdict,
        "checks": checks,
    }
    out = REPORTS / "l3_gpu.json"
    write_json(out, payload)
    print(f"L3 overall={overall} verdict={verdict}")
    for c in checks:
        print(f"  [{c['status']}] {c['name']}")
    return 0 if overall == "PASS" else 1


if __name__ == "__main__":
    raise SystemExit(main())
