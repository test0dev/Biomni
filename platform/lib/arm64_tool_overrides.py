"""arm64-only replacements for x86-only tools.

Imported from platform/sitecustomize.py. No-op on x86 so upstream
biomni.tool.pharmacology.run_autosite stays unchanged.
"""

from __future__ import annotations

import os
import platform
import shutil
import subprocess


def _is_arm() -> bool:
    return platform.machine() in ("aarch64", "arm64")


ARM64_DESCRIPTION = (
    "linux-aarch64: finds ligand pockets with fpocket because ADFRsuite AutoSite "
    "and prepare_receptor are x86-only and cannot be built here. Optionally writes "
    "a receptor PDBQT with Meeko (mk_prepare_receptor). Returns a research log with "
    "estimated pocket center and size, not an AutoSite log. The spacing argument is ignored."
)


def run_autosite_arm64(pdb_file: str, output_dir: str, spacing: float = 1.0) -> str:
    """Pocket detection via fpocket; receptor PDBQT via Meeko when available."""
    del spacing  # AutoSite grid spacing has no fpocket equivalent
    os.makedirs(output_dir, exist_ok=True)
    lines = [
        f"arm64 pocket detection for {pdb_file} (fpocket; ADFRsuite AutoSite is not used)",
        f"Output directory: {output_dir}",
    ]

    mk = shutil.which("mk_prepare_receptor.py") or shutil.which("mk_prepare_receptor")
    if mk:
        stem = os.path.join(output_dir, "receptor")
        proc = subprocess.run(
            [mk, "-i", pdb_file, "-o", stem],
            capture_output=True,
            text=True,
        )
        if proc.returncode == 0:
            lines.append(f"Meeko receptor PDBQT: {stem}.pdbqt")
        else:
            err = (proc.stderr or proc.stdout or "").strip().splitlines()
            lines.append("Meeko prepare skipped: " + (err[-1] if err else f"exit {proc.returncode}"))
    else:
        lines.append("Meeko (mk_prepare_receptor) not on PATH; skipped receptor PDBQT")

    fpocket = shutil.which("fpocket")
    if not fpocket:
        lines.append("fpocket not on PATH")
        return "\n".join(lines)

    proc = subprocess.run([fpocket, "-f", pdb_file], capture_output=True, text=True)
    if proc.returncode != 0:
        err = (proc.stderr or proc.stdout or "").strip().splitlines()
        lines.append("fpocket failed: " + (err[-1] if err else f"exit {proc.returncode}"))
        return "\n".join(lines)

    base = os.path.basename(pdb_file)
    name = base[:-4] if base.lower().endswith(".pdb") else base
    parent = os.path.dirname(os.path.abspath(pdb_file)) or "."
    info = os.path.join(parent, f"{name}_out", f"{name}_info.txt")
    lines.append(f"fpocket info: {info}")
    if os.path.isfile(info):
        center = _first_pocket_center(info)
        if center:
            lines.append(f"Box Center: {center}")
            lines.append("Box Size: estimated from first fpocket pocket (see info file)")
        else:
            lines.append("Box Center and Size not parsed; see fpocket info file.")
    else:
        lines.append("fpocket info file not found.")
    return "\n".join(lines)


def _first_pocket_center(info_path: str) -> str | None:
    """Best-effort parse of the first pocket's center from fpocket info."""
    text = open(info_path, encoding="utf-8", errors="replace").read().splitlines()
    in_first = False
    for line in text:
        low = line.lower()
        if low.strip().startswith("pocket 1"):
            in_first = True
            continue
        if in_first and low.strip().startswith("pocket ") and not low.strip().startswith("pocket 1"):
            break
        if in_first and "center" in low:
            # e.g. "Center of mass : 1.2 3.4 5.6"
            tail = line.split(":", 1)[-1].strip()
            if tail:
                return tail
    return None


def apply() -> None:
    if not _is_arm():
        return
    import biomni.tool.pharmacology as pharm
    import biomni.tool.tool_description.pharmacology as desc

    pharm.run_autosite = run_autosite_arm64
    for item in desc.description:
        if isinstance(item, dict) and item.get("name") == "run_autosite":
            item["description"] = ARM64_DESCRIPTION
