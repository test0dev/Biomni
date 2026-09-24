#!/usr/bin/env bash
# Probe / optionally download the official Biomni data lake.
# Source URL matches A1 / biomni-release S3.
#
# Usage:
#   bash platform/scripts/ensure_data_lake.sh           # probe; download if AUTO_DOWNLOAD_LAKE=1 (default)
#   bash platform/scripts/ensure_data_lake.sh --probe    # probe only (no download)
#   AUTO_DOWNLOAD_LAKE=0 bash platform/scripts/ensure_data_lake.sh
#
# Prints machine-readable lines (also human summary on stderr):
#   LAKE_PATH=...
#   LAKE_STATUS=ok|partial|missing
#   LAKE_HAVE=N
#   LAKE_EXPECTED=N
#   LAKE_MISSING=N
set -euo pipefail

BASE_URL="${BIOMNI_LAKE_URL:-https://biomni-release.s3.amazonaws.com/data_lake}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
JOBS="${JOBS:-8}"
PROBE_ONLY=0
AUTO_DOWNLOAD_LAKE="${AUTO_DOWNLOAD_LAKE:-1}"

FILES=(
  affinity_capture-ms.parquet
  affinity_capture-rna.parquet
  BindingDB_All_202409.tsv
  broad_repurposing_hub_molecule_with_smiles.parquet
  broad_repurposing_hub_phase_moa_target_info.parquet
  co-fractionation.parquet
  czi_census_datasets_v4.parquet
  DepMap_CRISPRGeneDependency.csv
  DepMap_CRISPRGeneEffect.csv
  DepMap_Model.csv
  DepMap_OmicsExpressionProteinCodingGenesTPMLogp1.csv
  ddinter_alimentary_tract_metabolism.csv
  ddinter_antineoplastic.csv
  ddinter_antiparasitic.csv
  ddinter_blood_organs.csv
  ddinter_dermatological.csv
  ddinter_hormonal.csv
  ddinter_respiratory.csv
  ddinter_various.csv
  DisGeNET.parquet
  dosage_growth_defect.parquet
  enamine_cloud_library_smiles.pkl
  evebio_assay_table.csv
  evebio_bundle_table.csv
  evebio_compound_table.csv
  evebio_control_table.csv
  evebio_detailed_result_table.csv
  evebio_observed_points_table.csv
  evebio_summary_result_table.csv
  evebio_target_table.csv
  genebass_missense_LC_filtered.pkl
  genebass_pLoF_filtered.pkl
  genebass_synonymous_filtered.pkl
  gene_info.parquet
  genetic_interaction.parquet
  go-plus.json
  gtex_tissue_gene_tpm.parquet
  gwas_catalog.pkl
  hp.obo
  kg.csv
  marker_celltype.parquet
  McPAS-TCR.parquet
  miRDB_v6.0_results.parquet
  miRTarBase_microRNA_target_interaction.parquet
  miRTarBase_microRNA_target_interaction_pubmed_abtract.txt
  miRTarBase_MicroRNA_Target_Sites.parquet
  mousemine_m1_positional_geneset.parquet
  mousemine_m2_curated_geneset.parquet
  mousemine_m3_regulatory_target_geneset.parquet
  mousemine_m5_ontology_geneset.parquet
  mousemine_m8_celltype_signature_geneset.parquet
  mousemine_mh_hallmark_geneset.parquet
  msigdb_human_c1_positional_geneset.parquet
  msigdb_human_c2_curated_geneset.parquet
  msigdb_human_c3_regulatory_target_geneset.parquet
  msigdb_human_c3_subset_transcription_factor_targets_from_GTRD.parquet
  msigdb_human_c4_computational_geneset.parquet
  msigdb_human_c5_ontology_geneset.parquet
  msigdb_human_c6_oncogenic_signature_geneset.parquet
  msigdb_human_c7_immunologic_signature_geneset.parquet
  msigdb_human_c8_celltype_signature_geneset.parquet
  msigdb_human_h_hallmark_geneset.parquet
  omim.parquet
  proteinatlas.tsv
  proximity_label-ms.parquet
  reconstituted_complex.parquet
  sgRNA_KO_SP_mouse.txt
  sgRNA_KO_SP_human.txt
  synthetic_growth_defect.parquet
  synthetic_lethality.parquet
  synthetic_rescue.parquet
  two-hybrid.parquet
  variant_table.parquet
  Virus-Host_PPI_P-HIPSTER_2020.parquet
  txgnn_name_mapping.pkl
  txgnn_prediction.pkl
)

while [[ $# -gt 0 ]]; do
  case "$1" in
    --probe)
      PROBE_ONLY=1
      shift
      ;;
    -h | --help)
      sed -n '2,16p' "$0"
      exit 0
      ;;
    *)
      echo "unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

resolve_lake_path() {
  if [[ -n "${BIOMNI_DATA_LAKE_PATH:-}" ]]; then
    echo "${BIOMNI_DATA_LAKE_PATH}"
    return
  fi
  if [[ -n "${BIOMNI_LAKE_HOST:-}" ]]; then
    echo "${BIOMNI_LAKE_HOST}"
    return
  fi
  if [[ -n "${LAKE_DIR:-}" ]]; then
    echo "${LAKE_DIR}"
    return
  fi
  if [[ -d /data/lake ]]; then
    echo /data/lake
    return
  fi
  if [[ -d "${HOME}/biomni-data-lake" ]]; then
    echo "${HOME}/biomni-data-lake"
    return
  fi
  # Default download target when nothing exists yet
  echo "${HOME}/biomni-data-lake"
}

count_present() {
  local dest="$1" n=0 name
  for name in "${FILES[@]}"; do
    if [[ -s "${dest}/${name}" ]]; then
      n=$((n + 1))
    fi
  done
  echo "${n}"
}

probe() {
  local dest expected have missing status
  dest="$(resolve_lake_path)"
  expected="${#FILES[@]}"
  if [[ ! -d "${dest}" ]]; then
    have=0
    missing="${expected}"
    status=missing
  else
    have="$(count_present "${dest}")"
    missing=$((expected - have))
    if [[ "${have}" -eq 0 ]]; then
      status=missing
    elif [[ "${missing}" -eq 0 ]]; then
      status=ok
    else
      status=partial
    fi
  fi
  LAKE_PATH="${dest}"
  LAKE_STATUS="${status}"
  LAKE_HAVE="${have}"
  LAKE_EXPECTED="${expected}"
  LAKE_MISSING="${missing}"
}

emit_probe() {
  echo "LAKE_PATH=${LAKE_PATH}"
  echo "LAKE_STATUS=${LAKE_STATUS}"
  echo "LAKE_HAVE=${LAKE_HAVE}"
  echo "LAKE_EXPECTED=${LAKE_EXPECTED}"
  echo "LAKE_MISSING=${LAKE_MISSING}"
  echo "data lake: path=${LAKE_PATH} status=${LAKE_STATUS} (${LAKE_HAVE}/${LAKE_EXPECTED})" >&2
}

download_missing() {
  local dest="$1"
  if ! command -v curl >/dev/null 2>&1; then
    echo "error: curl is required to download data lake" >&2
    return 1
  fi
  mkdir -p "${dest}"
  echo "downloading missing lake files into ${dest} (jobs=${JOBS})" >&2

  download_one() {
    local name="$1"
    local url="${BASE_URL}/${name}"
    local out="${dest}/${name}"
    local tmp="${out}.part"
    local status_file="${status_dir}/${name}.status"

    if [[ -s "${out}" ]]; then
      echo skip >"${status_file}"
      return 0
    fi
    if curl --fail --location --silent --show-error --retry 3 --retry-delay 2 \
      --continue-at - --output "${tmp}" -- "${url}"; then
      mv -f "${tmp}" "${out}"
      echo ok >"${status_file}"
    else
      rm -f "${tmp}"
      echo fail >"${status_file}"
    fi
  }

  local status_dir active name st fail=0
  status_dir="$(mktemp -d "${TMPDIR:-/tmp}/biomni-lake.XXXXXX")"
  # shellcheck disable=SC2064
  trap "rm -rf '${status_dir}'" RETURN

  active=0
  for name in "${FILES[@]}"; do
    if [[ -s "${dest}/${name}" ]]; then
      echo skip >"${status_dir}/${name}.status"
      continue
    fi
    while [[ "${active}" -ge "${JOBS}" ]]; do
      wait -n || true
      active=$((active - 1))
    done
    download_one "${name}" &
    active=$((active + 1))
  done
  while [[ "${active}" -gt 0 ]]; do
    wait -n || true
    active=$((active - 1))
  done

  for name in "${FILES[@]}"; do
    st="$(cat "${status_dir}/${name}.status" 2>/dev/null || echo fail)"
    if [[ "${st}" == "fail" ]]; then
      echo "fail  ${name}" >&2
      fail=$((fail + 1))
    fi
  done
  if [[ "${fail}" -gt 0 ]]; then
    echo "warning: ${fail} lake file(s) failed to download" >&2
    return 1
  fi
  return 0
}

probe
emit_probe

if [[ "${PROBE_ONLY}" -eq 1 ]]; then
  exit 0
fi

if [[ "${LAKE_STATUS}" == "ok" ]]; then
  exit 0
fi

if [[ "${AUTO_DOWNLOAD_LAKE}" != "1" ]]; then
  echo "warning: lake status=${LAKE_STATUS}; set AUTO_DOWNLOAD_LAKE=1 to download" >&2
  exit 0
fi

download_missing "${LAKE_PATH}" || true
probe
emit_probe
# Never fail the caller solely on lake — pack/build can proceed; tips will warn.
exit 0
