#!/usr/bin/env python3
"""L2 dependency import smoke tests."""

from __future__ import annotations

import importlib
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from common import REPORTS, stamp, write_json  # noqa: E402

# (import_name, pip/conda package hint)
PACKAGES = [
    ("numpy", "numpy"),
    ("pandas", "pandas"),
    ("scipy", "scipy"),
    ("Bio", "biopython"),
    ("torch", "torch"),
    ("torchvision", "torchvision"),
    ("scanpy", "scanpy"),
    ("anndata", "anndata"),
    ("rdkit", "rdkit"),
    ("cellpose", "cellpose"),
    ("openmm", "openmm"),
    ("esm", "fair-esm"),
    ("scvi", "scvi-tools"),
    ("sklearn", "scikit-learn"),
    ("skimage", "scikit-image"),
    ("cv2", "opencv-python"),
    ("gget", "gget"),
    ("pysam", "pysam"),
    ("pybedtools", "pybedtools"),
    ("cooler", "cooler"),
    ("cobra", "cobra"),
    ("libsbml", "python-libsbml"),
    ("msprime", "msprime"),
    ("tskit", "tskit"),
    ("cyvcf2", "cyvcf2"),
    ("harmonypy", "harmony-pytorch"),
    ("umap", "umap-learn"),
    ("transformers", "transformers"),
    ("nibabel", "nibabel"),
    ("nilearn", "nilearn"),
    ("nnunet", "nnunet"),
    ("pylabrobot", "pylabrobot"),
    ("arxiv", "arxiv"),
    ("PyPDF2", "PyPDF2"),
    ("reportlab", "reportlab"),
    ("igraph", "igraph"),
    ("flowcytometrytools", "flowcytometrytools"),
    ("RNA", "viennarna"),
    ("lifelines", "lifelines"),
    ("faiss", "faiss-cpu"),
    ("pyliftover", "pyliftover"),
    ("biomni", "biomni"),
]


def try_import(name: str) -> dict:
    try:
        m = importlib.import_module(name)
        ver = getattr(m, "__version__", None)
        return {"name": name, "status": "PASS", "version": ver, "error": None}
    except Exception as e:  # noqa: BLE001
        err = f"{type(e).__name__}: {e}"
        status = "FAIL_DEP"
        # Heuristic: arch-related import failures
        low = err.lower()
        if any(x in low for x in ("aarch64", "arm64", "x86_64", "wrong elf", "exec format")):
            status = "FAIL_ARM"
        return {"name": name, "status": status, "version": None, "error": err}


def main() -> int:
    results = [try_import(n) for n, _ in PACKAGES]
    # torch cuda detail if present
    torch_detail = None
    try:
        import torch

        torch_detail = {
            "version": torch.__version__,
            "cuda_available": torch.cuda.is_available(),
            "cuda_version": getattr(torch.version, "cuda", None),
            "device_count": torch.cuda.device_count() if torch.cuda.is_available() else 0,
            "device_name": torch.cuda.get_device_name(0) if torch.cuda.is_available() else None,
        }
    except Exception as e:  # noqa: BLE001
        torch_detail = {"error": f"{type(e).__name__}: {e}"}

    failed = [r for r in results if r["status"] != "PASS"]
    payload = {
        "layer": "L2",
        "timestamp": stamp(),
        "overall": "PASS" if not failed else "FAIL_DEP",
        "pass_count": sum(1 for r in results if r["status"] == "PASS"),
        "fail_count": len(failed),
        "torch_detail": torch_detail,
        "results": results,
    }
    out = REPORTS / "l2_imports.json"
    write_json(out, payload)
    print(f"L2 overall={payload['overall']} pass={payload['pass_count']} fail={payload['fail_count']}")
    for r in failed:
        print(f"  [{r['status']}] {r['name']}: {r['error']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
