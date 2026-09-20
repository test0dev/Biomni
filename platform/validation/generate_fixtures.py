#!/usr/bin/env python3
"""Generate per-tool fixture stubs + curated invoke kwargs for L4."""

from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO))

from inventory import inventory  # noqa: E402

VAL = Path(__file__).parent
FIX = VAL / "fixtures"
DATA = VAL / "data"

# Curated minimal invoke fixtures (module.name -> kwargs). Paths are relative to VAL.
CURATED: dict[str, dict] = {
    "support_tools.run_python_repl": {
        "mode": "invoke",
        "kwargs": {"command": "print(1+1)"},
        "expect_substr": "2",
    },
    "support_tools.read_function_source_code": {
        "mode": "invoke",
        "kwargs": {"function_name": "biomni.tool.support_tools.run_python_repl"},
    },
    "support_tools.download_synapse_data": {
        "mode": "skip_auth",
        "kwargs": {"entity_ids": "syn000000"},
        "auth_env": "SYNAPSE_AUTH_TOKEN",
    },
    "protocols.list_local_protocols": {"mode": "invoke", "kwargs": {}},
    "glycoengineering.list_glycoengineering_resources": {"mode": "invoke", "kwargs": {}},
    "glycoengineering.find_n_glycosylation_motifs": {
        "mode": "invoke",
        "kwargs": {"protein_sequence": "MKTNKLLVLVLLVCLTSVFSNXST"},
    },
    "glycoengineering.predict_o_glycosylation_hotspots": {
        "mode": "invoke",
        "kwargs": {"protein_sequence": "MKTSTSTSTAAAA"},
    },
    "molecular_biology.annotate_open_reading_frames": {
        "mode": "invoke",
        "kwargs": {
            "sequence": "ATGAAACCCGGGTTTTAA" * 3,
        },
    },
    "molecular_biology.find_restriction_sites": {
        "mode": "invoke",
        "kwargs": {"sequence": "GAATTCGCGGCCGCAAGCTT"},
    },
    "molecular_biology.pcr_simple": {
        "mode": "invoke",
        "kwargs": {
            "sequence": "ATGAAACCCGGG" * 20,
            "forward_primer": "ATGAAA",
            "reverse_primer": "CCCGGG",
        },
    },
    "molecular_biology.design_primer": {
        "mode": "invoke",
        "kwargs": {"template": "ATGAAACCCGGGTTTTAAATGAAACCCGGGTTTTAA", "start": 1, "end": 20},
    },
    "database.query_uniprot": {
        "mode": "invoke",
        "kwargs": {"prompt": "Find information about human insulin protein", "max_results": 1},
        "timeout_s": 60,
    },
    "database.query_kegg": {
        "mode": "invoke",
        "kwargs": {"prompt": "What is pathway hsa00010?", "verbose": False},
        "timeout_s": 60,
    },
    "database.query_pdb": {
        "mode": "invoke",
        "kwargs": {"prompt": "Find structures of human hemoglobin", "max_results": 1},
        "timeout_s": 60,
    },
    "database.query_alphafold": {
        "mode": "invoke",
        "kwargs": {"uniprot_id": "P01308", "download": False},
        "timeout_s": 60,
    },
    "literature.query_arxiv": {
        "mode": "invoke",
        "kwargs": {"query": "single cell RNA sequencing", "max_papers": 1},
        "timeout_s": 60,
    },
    "literature.query_pubmed": {
        "mode": "invoke",
        "kwargs": {"query": "CRISPR Cas9", "max_results": 1},
        "timeout_s": 60,
    },
    "lab_automation.get_pylabrobot_documentation_liquid": {"mode": "invoke", "kwargs": {}},
    "lab_automation.get_pylabrobot_documentation_material": {"mode": "invoke", "kwargs": {}},
    "systems_biology.model_protein_dimerization_network": {
        "mode": "import_and_try",
        "kwargs": {
            "monomer_concentrations": {"A": 1.0, "B": 1.0},
            "dimerization_rates": {"A|B": 0.1},
            "simulation_time": 1.0,
        },
        "note": "dimerization_rates may require tuple keys at runtime; import/try best-effort",
    },
}

# Map binary name -> tools that should FAIL_ARM if binary is FAIL_ARM
BIN_TO_TOOLS = {
    "plink2": ["genomics.analyze_comparative_genomics_and_haplotypes"],
    "muscle": ["genetics.analyze_protein_phylogeny"],
    "iqtree2": ["genetics.analyze_protein_phylogeny"],
    "iqtree": ["genetics.analyze_protein_phylogeny"],
    "gcta64": ["genetics.fit_genomic_prediction_model"],
}


def default_fixture(row: dict, tags: dict) -> dict:
    key = row["key"]
    if key in CURATED:
        return {"key": key, **CURATED[key]}

    tinfo = tags.get(key, {})
    tagset = set(tinfo.get("tags") or [])

    if "py310" in tagset or "extra_env" in tagset:
        return {
            "key": key,
            "mode": "skip_extra_env",
            "kwargs": {},
            "reason": "requires dedicated conda env (see known_conflicts.md)",
        }
    if "auth" in tagset:
        return {
            "key": key,
            "mode": "skip_auth",
            "kwargs": {},
            "auth_env": "SYNAPSE_AUTH_TOKEN",
        }

    # Build kwargs from schema defaults when possible
    kwargs = {}
    for p in row.get("required_parameters") or []:
        pname = p.get("name")
        default = p.get("default")
        if default is not None:
            kwargs[pname] = default
        else:
            # placeholder by type/name heuristics
            typ = (p.get("type") or "str").lower()
            if "path" in (pname or "").lower() or "file" in (pname or "").lower():
                kwargs[pname] = str(DATA / "placeholder.txt")
            elif "sequence" in (pname or "").lower():
                kwargs[pname] = "ATGAAACCCGGGTTTTAA"
            elif "smiles" in (pname or "").lower():
                kwargs[pname] = "CCO"
            elif typ.startswith("int"):
                kwargs[pname] = 1
            elif typ.startswith("float"):
                kwargs[pname] = 1.0
            elif typ.startswith("bool"):
                kwargs[pname] = False
            elif "list" in typ:
                kwargs[pname] = []
            elif "dict" in typ:
                kwargs[pname] = {}
            else:
                kwargs[pname] = "test"

    # Prefer import_only for heavy gpu/docker unless curated
    if "docker" in tagset:
        return {
            "key": key,
            "mode": "import_only",
            "kwargs": {},
            "timeout_s": 30,
            "tags": sorted(tagset),
            "note": "docker tool — import check only in harness (host docker may lack permissions)",
        }
    if "gpu" in tagset:
        return {
            "key": key,
            "mode": "import_and_try",
            "kwargs": kwargs,
            "timeout_s": 120,
            "tags": sorted(tagset),
        }

    if "network" in tagset:
        return {
            "key": key,
            "mode": "import_and_try",
            "kwargs": kwargs,
            "timeout_s": 45,
            "tags": sorted(tagset),
        }

    return {
        "key": key,
        "mode": "import_and_try",
        "kwargs": kwargs,
        "timeout_s": 30,
        "tags": sorted(tagset),
    }


def main() -> int:
    FIX.mkdir(parents=True, exist_ok=True)
    DATA.mkdir(parents=True, exist_ok=True)
    (DATA / "placeholder.txt").write_text("placeholder for validation\n")

    tags_path = VAL / "tags.json"
    if not tags_path.exists():
        from generate_tags import generate_tags

        tags_payload = generate_tags()
        tags_path.write_text(json.dumps(tags_payload, indent=2))
    else:
        tags_payload = json.loads(tags_path.read_text())
    tags = tags_payload.get("tools", {})

    rows = inventory()
    index = {}
    for row in rows:
        fix = default_fixture(row, tags)
        mod_dir = FIX / row["module"]
        mod_dir.mkdir(parents=True, exist_ok=True)
        path = mod_dir / f"{row['name']}.json"
        path.write_text(json.dumps(fix, indent=2, ensure_ascii=False))
        index[row["key"]] = str(path.relative_to(VAL))

    (FIX / "index.json").write_text(json.dumps(index, indent=2))
    print(f"Wrote {len(index)} fixtures under {FIX}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
