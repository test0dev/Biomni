# linux-arm CLI notes

See also `cli_install_report.json`.

## Source builds

| Tool | How |
|---|---|
| plink2 | `chrchang/plink-ng` `2.0/build_dynamic` |
| gcta64 | `jianyangqt/gcta` cmake |
| FastTree | compile `FastTree.c` |
| vina | `ccsb-scripps/AutoDock-Vina` `build/linux/release` Makefile |
| fpocket | `Discngine/fpocket` with gcc; bundled molfile `.a` is x86, so PDB pocket detection is linked against no-op stubs (`platform/lib/fpocket_molfile_stubs.c`). mmCIF and MD trajectory plugins are not functional |
| bwa | conda first; git `lh3/bwa` only if conda fails |

Existing aarch64 binaries under the conda prefix or `platform/biomni_tools` are reused unless `FORCE_REBUILD=1`.

System/conda deps commonly needed: `build-essential` or `gcc`, `cmake`, `zlib`, `openblas`, `lapack`, `boost`.

## Not built

| Tool | Reason |
|---|---|
| HOMER (`findMotifs.pl`) | Perl installer, not verified on linux-aarch64 |
| ADFRsuite `autosite` / `prepare_receptor` | Official packages are linux x86 only and are not compiled. On arm64, `run_autosite` is overridden to **fpocket** plus **Meeko**; the exposed description says so. x86 keeps the upstream function. |
| `gcta` (no 64 suffix) | Use `gcta64` |
