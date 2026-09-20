# Biomni ARM + GPU Validation (platform/)

Ported from Factory `Biomni/biomni_env/validation/`. Paths resolve to **biomni-arm** repo root.

**Run on linux-arm only.** linux-x86 is not validated in this environment.

## Quick start

```bash
conda activate biomni_e1
cd biomni-arm
source platform/setup_path.sh   # after platform/install.sh
bash platform/validation/run_all.sh
```

Default layers: **L0, L1, L3 (GPU)**.  
`VAL_RUN_L2=1` / `VAL_RUN_L4=1` for imports / full 224 tools.  
`VAL_SKIP_DOCKER=1` skips Docker GPU check (host CUDA still required for L3 PASS).

Reports: `platform/validation/reports/`.

## Layers

| Layer | Purpose |
|-------|---------|
| L0 | Arch, nvidia-smi, docker presence |
| L1 | ELF arch gate for CLI binaries |
| L2 | Dependency import smoke (opt-in) |
| L3 | torch CUDA + nvidia-smi (+ optional docker GPU) + OpenMM |
| L4 | Full tool matrix (opt-in, long) |
