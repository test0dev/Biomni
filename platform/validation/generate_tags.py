#!/usr/bin/env python3
"""Auto-tag tools by scanning implementation source (network/gpu/docker/extbin/…)."""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO_ROOT))

from inventory import inventory  # noqa: E402

VAL_DIR = Path(__file__).parent

GPU_RE = re.compile(r"\bgpu\b|\bcuda\b|torch\.cuda|device\s*=\s*[\"']cuda|num_gpus|use_gpu", re.I)
DOCKER_RE = re.compile(r"\bdocker\b", re.I)
NET_RE = re.compile(
    r"requests\.|urllib|httpx|aiohttp|Entrez|Bio\.Entrez|urlopen|BeautifulSoup|scholarly|arxiv",
    re.I,
)
BIN_RE = re.compile(
    r"(plink2|gcta64?|iqtree2?|muscle|bwa|samtools|macs2|findMotifs|vina|autosite|"
    r"prepare_receptor|FastTree|homer|bowtie2|blastn|blastp|mafft|bedtools)",
    re.I,
)

# Tools known to need separate envs
EXTRA_ENV = {
    "cancer_biology.analyze_copy_number_purity_ploidy_and_focal_events": "py310",
    "genomics.annotate_celltype_with_panhumanpy": "extra_env",
}

# Tools that depend on known x86-only Linux CLI bundles from install_cli_tools.sh
ARM_RISK_BINS = {
    "plink2": ["genetics.fit_genomic_prediction_model", "genomics.analyze_comparative_genomics_and_haplotypes"],
    "muscle": ["genetics.analyze_protein_phylogeny"],
    "iqtree": ["genetics.analyze_protein_phylogeny"],
    "iqtree2": ["genetics.analyze_protein_phylogeny"],
    "gcta64": ["genetics.fit_genomic_prediction_model"],
    "gcta": ["genetics.fit_genomic_prediction_model"],
}

AUTH_TOOLS = {
    "support_tools.download_synapse_data",
    "database.query_synapse",
    "literature.advanced_web_search_claude",
}


def _function_body(src: str, name: str) -> str:
    m = re.search(rf"^def {re.escape(name)}\s*\(", src, re.M)
    if not m:
        return ""
    start = m.start()
    nxt = re.search(r"^def ", src[m.end() :], re.M)
    end = m.end() + (nxt.start() if nxt else len(src))
    return src[start:end]


def generate_tags() -> dict:
    rows = inventory()
    tags: dict[str, dict] = {}
    for r in rows:
        key = r["key"]
        mod = r["module"]
        name = r["name"]
        impl_path = REPO_ROOT / "biomni" / "tool" / f"{mod}.py"
        body = ""
        if impl_path.exists():
            body = _function_body(impl_path.read_text(errors="ignore"), name)

        label_set: set[str] = set()
        bins: list[str] = []
        if GPU_RE.search(body) or GPU_RE.search(name):
            label_set.add("gpu")
        if DOCKER_RE.search(body):
            label_set.add("docker")
        if NET_RE.search(body) or mod in ("database", "literature"):
            label_set.add("network")
        for m in BIN_RE.finditer(body):
            label_set.add("extbin")
            bins.append(m.group(1).lower())
        if key in EXTRA_ENV:
            label_set.add(EXTRA_ENV[key])
        if key in AUTH_TOOLS:
            label_set.add("auth")
        if not label_set:
            label_set.add("pure_python")

        arm_risk = False
        for b in bins:
            for risky, keys in ARM_RISK_BINS.items():
                if b.startswith(risky.rstrip("64").rstrip("2")[:4]) or b == risky:
                    if key in keys or True:
                        # mark if body references known x86 linux binaries
                        if b in ("plink2", "muscle", "iqtree", "iqtree2", "gcta64", "gcta"):
                            arm_risk = True
        if any(b in ("plink2", "muscle", "iqtree", "iqtree2", "gcta64", "gcta") for b in bins):
            arm_risk = True
            label_set.add("arm_risk")

        tags[key] = {
            "module": mod,
            "name": name,
            "tags": sorted(label_set),
            "bins": sorted(set(bins)),
            "arm_risk": arm_risk,
            "impl_exists": r["impl_exists"],
        }

    # Manual overrides for GPU tools listed in the plan
    for key in (
        "pharmacology.run_diffdock_with_smiles",
        "genomics.generate_gene_embeddings_with_ESM_models",
        "genomics.generate_transcriptformer_embeddings",
        "genomics.generate_embeddings_with_state",
        "genomics.unsupervised_celltype_transfer_between_scRNA_datasets",
        "bioimaging.segment_with_nn_unet",
        "microbiology.segment_cells_with_deep_learning",
    ):
        if key in tags:
            t = set(tags[key]["tags"])
            t.add("gpu")
            if "pure_python" in t and len(t) > 1:
                t.discard("pure_python")
            tags[key]["tags"] = sorted(t)

    return {
        "generated_by": "generate_tags.py",
        "count": len(tags),
        "tools": tags,
    }


def main() -> int:
    payload = generate_tags()
    out = VAL_DIR / "tags.json"
    out.write_text(json.dumps(payload, indent=2, ensure_ascii=False))
    # summary counts
    from collections import Counter

    c: Counter[str] = Counter()
    for t in payload["tools"].values():
        for tag in t["tags"]:
            c[tag] += 1
    print(json.dumps({"count": payload["count"], "tag_counts": dict(c)}, indent=2))
    print(f"Wrote {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
