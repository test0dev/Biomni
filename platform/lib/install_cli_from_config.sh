#!/usr/bin/env bash
# Install CLI tools from a platform-specific JSON config.
# Does not read or modify biomni_env/cli_tools_config.json.
set -euo pipefail

PLATFORM_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$PLATFORM_DIR/lib/common.sh"

CONFIG_FILE="${1:-}"
REPORT_FILE="${2:-$PLATFORM_DIR/cli_install_report.json}"

[[ -n "$CONFIG_FILE" && -f "$CONFIG_FILE" ]] || die "usage: install_cli_from_config.sh <config.json> [report.json]"
command -v jq &>/dev/null || die "jq is required"

mkdir -p "$PLATFORM_TOOLS/bin" "$PLATFORM_TOOLS/src"
activate_env

export PATH="${CONDA_PREFIX}/bin:${PLATFORM_TOOLS}/bin:${PATH}"

num_tools="$(jq '.tools | length' "$CONFIG_FILE")"
log_info "installing $num_tools tools from $(basename "$CONFIG_FILE")"

RESULTS='[]'
SKIPPED=0
INSTALLED=0
FAILED=0

append_result() {
  local name="$1" status="$2" detail="$3"
  RESULTS="$(jq -c --arg n "$name" --arg s "$status" --arg d "$detail" \
    '. + [{name:$n, status:$s, detail:$d}]' <<<"$RESULTS")"
}

link_into_tools() {
  local binary="$1"
  local src
  src="$(command -v "$binary" || true)"
  if [[ -n "$src" && -e "$src" ]]; then
    ln -sfn "$src" "$PLATFORM_TOOLS/bin/$binary"
  fi
}

verify_arch() {
  local binary="$1"
  local path
  path="$(command -v "$binary" || true)"
  [[ -n "$path" ]] || return 1
  local info
  info="$(file -b -L "$path" 2>/dev/null || true)"
  local host
  host="$(uname -m)"
  if [[ "$host" == "aarch64" || "$host" == "arm64" ]]; then
    if echo "$info" | grep -qiE 'x86-64|x86_64|Intel 80386'; then
      log_err "$binary is wrong arch: $info"
      return 2
    fi
  fi
  return 0
}

smoke_test() {
  local binary="$1"
  shift
  local args=("$@")
  if [[ ${#args[@]} -eq 0 ]]; then
    return 0
  fi
  # Some tools print help to stderr and exit non-zero; accept if binary runs without Exec format error
  set +e
  out="$("$binary" "${args[@]}" 2>&1)"
  rc=$?
  set -e
  if echo "$out" | grep -qi 'Exec format error'; then
    return 1
  fi
  return 0
}

# True when an arch-ok binary already lives under conda or platform tools.
owned_binary() {
  local binary="$1"
  local path real
  path="$(command -v "$binary" 2>/dev/null || true)"
  [[ -n "$path" ]] || return 1
  real="$(readlink -f "$path" 2>/dev/null || echo "$path")"
  verify_arch "$binary" || return 1
  [[ "$real" == "$CONDA_PREFIX/"* || "$real" == "$PLATFORM_TOOLS/"* ]]
}

# Build from source. jq_prefix selects the object (.tools[i] or .tools[i].fallback).
# Sets SOURCE_BUILD_RESULT to pass:<detail> or fail:<detail>
source_build() {
  local jq_prefix="$1"
  local binary name
  binary="$(jq -r "${jq_prefix}.binary" "$CONFIG_FILE")"
  name="$(jq -r "${jq_prefix}.name // \"${binary}\"" "$CONFIG_FILE")"
  SOURCE_BUILD_RESULT=""

fetch_archive() {
  local url="$1" dest="$2"
  local tgz top
  tgz="$(mktemp /tmp/biomni-src-XXXXXX.tgz)"
  curl --http1.1 -fL --retry 3 --retry-delay 2 -o "$tgz" "$url" || { rm -f "$tgz"; return 1; }
  top="$(tar -tzf "$tgz" | head -1 | cut -d/ -f1)"
  [[ -n "$top" ]] || { rm -f "$tgz"; return 1; }
  rm -rf "$dest" "${dest%/*}/$top"
  tar -xzf "$tgz" -C "$(dirname "$dest")"
  if [[ "$(dirname "$dest")/$top" != "$dest" ]]; then
    mv "$(dirname "$dest")/$top" "$dest"
  fi
  touch "$dest/.source_ready"
  rm -f "$tgz"
}

  if [[ "${FORCE_REBUILD:-0}" != "1" ]] && owned_binary "$binary"; then
    link_into_tools "$binary"
    SOURCE_BUILD_RESULT="pass:reuse $(command -v "$binary")"
    return 0
  fi

  local conda_deps
  conda_deps="$(jq -r "${jq_prefix}.conda_deps[]?" "$CONFIG_FILE" | tr '\n' ' ')"
  if [[ -n "${conda_deps// /}" ]]; then
    # shellcheck disable=SC2086
    conda install -y -c conda-forge ${conda_deps} || log_warn "conda deps failed for $name"
  fi

  local src_dirname src_dir
  src_dirname="$(jq -r "${jq_prefix}.src_dirname // empty" "$CONFIG_FILE")"
  [[ -n "$src_dirname" ]] || src_dirname="$binary"
  src_dir="$PLATFORM_TOOLS/src/$src_dirname"
  mkdir -p "$PLATFORM_TOOLS/src"

  local repo_url source_url
  repo_url="$(jq -r "${jq_prefix}.repo_url // empty" "$CONFIG_FILE")"
  source_url="$(jq -r "${jq_prefix}.source_url // empty" "$CONFIG_FILE")"

  if [[ -n "$repo_url" || -n "$(jq -r "${jq_prefix}.archive_url // empty" "$CONFIG_FILE")" ]]; then
    archive_url="$(jq -r "${jq_prefix}.archive_url // empty" "$CONFIG_FILE")"
    if [[ ! -d "$src_dir/.git" && ! -f "$src_dir/.source_ready" ]]; then
      fetched=0
      if [[ -n "$archive_url" ]]; then
        log_info "fetch archive for $name"
        if fetch_archive "$archive_url" "$src_dir"; then
          fetched=1
        else
          log_warn "archive download failed for $name"
        fi
      fi
      if [[ "$fetched" -ne 1 && -n "$repo_url" ]]; then
        for attempt in 1 2 3; do
          rm -rf "$src_dir"
          if git -c http.version=HTTP/1.1 clone --depth 1 "$repo_url" "$src_dir"; then
            fetched=1
            break
          fi
          log_warn "git clone attempt $attempt failed for $name"
          sleep 2
        done
      fi
      [[ "$fetched" -eq 1 ]] || { SOURCE_BUILD_RESULT="fail:could not fetch source"; return 0; }
    fi
  elif [[ -n "$source_url" ]]; then
    mkdir -p "$src_dir"
    local fname
    fname="$(basename "$source_url")"
    if [[ ! -f "$src_dir/$fname" ]]; then
      if command -v curl &>/dev/null; then
        curl -fsSL -o "$src_dir/$fname" "$source_url" || { SOURCE_BUILD_RESULT="fail:download $source_url"; return 0; }
      else
        wget -q -O "$src_dir/$fname" "$source_url" || { SOURCE_BUILD_RESULT="fail:download $source_url"; return 0; }
      fi
    fi
  else
    SOURCE_BUILD_RESULT="fail:source_build missing repo_url/source_url"
    return 0
  fi

  local build_subdir build_dir build_cmd
  build_subdir="$(jq -r "${jq_prefix}.build_subdir // \".\"" "$CONFIG_FILE")"
  build_dir="$src_dir/$build_subdir"
  mkdir -p "$build_dir"
  build_cmd="$(jq -r "${jq_prefix}.build_cmd" "$CONFIG_FILE")"
  [[ -n "$build_cmd" && "$build_cmd" != "null" ]] || { SOURCE_BUILD_RESULT="fail:missing build_cmd"; return 0; }

  log_info "source_build $name in $build_dir"
  local blog
  blog="$PLATFORM_TOOLS/src/${binary}.build.log"
  if ! (cd "$build_dir" && bash -c "$build_cmd") >"$blog" 2>&1; then
    SOURCE_BUILD_RESULT="fail:build failed (see $blog)"
    tail -n 20 "$blog" >&2 || true
    return 0
  fi

  local artifact found
  artifact="$(jq -r "${jq_prefix}.artifact // \"${binary}\"" "$CONFIG_FILE")"
  if [[ -x "$build_dir/$artifact" ]]; then
    found="$build_dir/$artifact"
  elif [[ -x "$src_dir/$artifact" ]]; then
    found="$src_dir/$artifact"
  else
    found="$(find "$src_dir" -type f -name "$(basename "$artifact")" -perm -u+x 2>/dev/null | head -1 || true)"
  fi
  [[ -n "$found" && -f "$found" ]] || { SOURCE_BUILD_RESULT="fail:artifact not found: $artifact"; return 0; }

  cp -f "$found" "${CONDA_PREFIX}/bin/$binary"
  chmod +x "${CONDA_PREFIX}/bin/$binary"
  ln -sfn "${CONDA_PREFIX}/bin/$binary" "$PLATFORM_TOOLS/bin/$binary"
  hash -r 2>/dev/null || true
  if ! verify_arch "$binary"; then
    SOURCE_BUILD_RESULT="fail:arch check failed after build"
    return 0
  fi
  mapfile -t vargs < <(jq -r "${jq_prefix}.version_args[]?" "$CONFIG_FILE")
  if ! smoke_test "$binary" "${vargs[@]+"${vargs[@]}"}"; then
    SOURCE_BUILD_RESULT="fail:smoke test failed"
    return 0
  fi
  SOURCE_BUILD_RESULT="pass:source_build $(command -v "$binary")"
}

for ((i = 0; i < num_tools; i++)); do
  name="$(jq -r ".tools[$i].name" "$CONFIG_FILE")"
  binary="$(jq -r ".tools[$i].binary" "$CONFIG_FILE")"
  method="$(jq -r ".tools[$i].method" "$CONFIG_FILE")"
  reason="$(jq -r ".tools[$i].reason // empty" "$CONFIG_FILE")"
  log_info "[$i] $name ($binary) method=$method"

  case "$method" in
    skip)
      log_warn "skip $name: ${reason:-no reason}"
      append_result "$name" "skip" "${reason:-skipped}"
      SKIPPED=$((SKIPPED + 1))
      continue
      ;;
    conda)
      packages=()
      while IFS= read -r pkg; do
        [[ -n "$pkg" ]] && packages+=("$pkg")
      done < <(jq -r ".tools[$i].packages[]?" "$CONFIG_FILE")
      channels=()
      while IFS= read -r ch; do
        [[ -n "$ch" ]] && channels+=("-c" "$ch")
      done < <(jq -r ".tools[$i].channels[]?" "$CONFIG_FILE")
      if [[ ${#packages[@]} -eq 0 ]]; then
        append_result "$name" "fail" "conda method but no packages"
        FAILED=$((FAILED + 1))
        continue
      fi
      if command -v "$binary" &>/dev/null && verify_arch "$binary"; then
        log_ok "$binary already present and arch-ok"
      else
        log_info "conda install ${packages[*]}"
        if ! conda install -y "${channels[@]}" "${packages[@]}"; then
          if jq -e ".tools[$i].fallback" "$CONFIG_FILE" >/dev/null; then
            log_warn "conda failed for $name; trying source_build fallback"
            source_build ".tools[$i].fallback"
            result="$SOURCE_BUILD_RESULT"
            status="${result%%:*}"
            detail="${result#*:}"
            if [[ "$status" == "pass" ]]; then
              append_result "$name" "pass" "$detail"
              INSTALLED=$((INSTALLED + 1))
              log_ok "$name $detail"
            else
              append_result "$name" "fail" "$detail"
              FAILED=$((FAILED + 1))
            fi
            continue
          fi
          append_result "$name" "fail" "conda install failed"
          FAILED=$((FAILED + 1))
          continue
        fi
      fi
      # aliases (e.g. iqtree2 -> iqtree)
      while IFS= read -r alias; do
        [[ -z "$alias" || "$alias" == "null" ]] && continue
        if [[ -x "${CONDA_PREFIX}/bin/$binary" ]]; then
          ln -sfn "${CONDA_PREFIX}/bin/$binary" "${CONDA_PREFIX}/bin/$alias"
          ln -sfn "${CONDA_PREFIX}/bin/$binary" "$PLATFORM_TOOLS/bin/$alias"
        fi
      done < <(jq -r ".tools[$i].aliases[]?" "$CONFIG_FILE")
      link_into_tools "$binary"
      if ! verify_arch "$binary"; then
        append_result "$name" "fail" "arch check failed after conda install"
        FAILED=$((FAILED + 1))
        continue
      fi
      mapfile -t vargs < <(jq -r ".tools[$i].version_args[]?" "$CONFIG_FILE")
      if ! smoke_test "$binary" "${vargs[@]+"${vargs[@]}"}"; then
        append_result "$name" "fail" "smoke test failed"
        FAILED=$((FAILED + 1))
        continue
      fi
      append_result "$name" "pass" "conda: $(command -v "$binary")"
      INSTALLED=$((INSTALLED + 1))
      log_ok "$name OK → $(command -v "$binary")"
      ;;
    download)
      url="$(jq -r ".tools[$i].url // empty" "$CONFIG_FILE")"
      [[ -n "$url" ]] || { append_result "$name" "fail" "download missing url"; FAILED=$((FAILED + 1)); continue; }
      dest_dir="$PLATFORM_TOOLS/downloads/$binary"
      mkdir -p "$dest_dir"
      fname="$(basename "$url")"
      archive="$dest_dir/$fname"
      if [[ ! -f "$archive" ]]; then
        log_info "download $url"
        if command -v wget &>/dev/null; then
          wget -q -O "$archive" "$url" || { append_result "$name" "fail" "wget failed"; FAILED=$((FAILED + 1)); continue; }
        else
          curl -fsSL -o "$archive" "$url" || { append_result "$name" "fail" "curl failed"; FAILED=$((FAILED + 1)); continue; }
        fi
      fi
      # Best-effort extract / link — x86 path only in practice
      binary_path="$(jq -r ".tools[$i].binary_path // \"$binary\"" "$CONFIG_FILE")"
      case "$archive" in
        *.zip) unzip -qo "$archive" -d "$dest_dir" ;;
        *.tar.gz|*.tgz) tar -xzf "$archive" -C "$dest_dir" ;;
        *.c)
          if [[ ! -x "$dest_dir/FastTree" ]]; then
            gcc -O3 -finline-functions -funroll-loops -o "$dest_dir/FastTree" "$archive" -lm || true
          fi
          ;;
        *)
          # raw binary
          chmod +x "$archive" || true
          ln -sfn "$archive" "$PLATFORM_TOOLS/bin/$binary"
          ;;
      esac
      # locate binary under dest_dir
      found="$(find "$dest_dir" -type f -name "$(basename "$binary_path")" 2>/dev/null | head -1 || true)"
      if [[ -n "$found" ]]; then
        chmod +x "$found" || true
        ln -sfn "$found" "$PLATFORM_TOOLS/bin/$binary"
      fi
      if command -v "$binary" &>/dev/null; then
        append_result "$name" "pass" "download: $(command -v "$binary")"
        INSTALLED=$((INSTALLED + 1))
      else
        append_result "$name" "fail" "binary not found after download"
        FAILED=$((FAILED + 1))
      fi
      ;;
    local_or_skip)
      found=""
      while IFS= read -r cand; do
        [[ -z "$cand" || "$cand" == "null" ]] && continue
        # expand env vars
        cand_exp="$(eval echo "$cand")"
        if [[ -x "$cand_exp" ]]; then
          found="$cand_exp"
          break
        fi
      done < <(jq -r ".tools[$i].local_candidates[]?" "$CONFIG_FILE")
      if [[ -n "$found" ]]; then
        dest="${CONDA_PREFIX}/bin/$binary"
        if [[ "$(readlink -f "$found" 2>/dev/null || echo "$found")" != "$(readlink -f "$dest" 2>/dev/null || echo "$dest")" ]]; then
          cp -f "$found" "$dest"
          chmod +x "$dest"
        fi
        ln -sfn "$dest" "$PLATFORM_TOOLS/bin/$binary"
        if verify_arch "$binary"; then
          append_result "$name" "pass" "local: $found"
          INSTALLED=$((INSTALLED + 1))
          log_ok "$name from local $found"
        else
          append_result "$name" "fail" "local binary wrong arch: $found"
          FAILED=$((FAILED + 1))
        fi
      elif command -v "$binary" &>/dev/null && verify_arch "$binary"; then
        link_into_tools "$binary"
        append_result "$name" "pass" "already present: $(command -v "$binary")"
        INSTALLED=$((INSTALLED + 1))
        log_ok "$name already present"
      else
        log_warn "skip $name: ${reason:-no local candidate}"
        append_result "$name" "skip" "${reason:-no local aarch64 binary}"
        SKIPPED=$((SKIPPED + 1))
      fi
      ;;
    source_build)
      source_build ".tools[$i]"
      result="$SOURCE_BUILD_RESULT"
      status="${result%%:*}"
      detail="${result#*:}"
      if [[ "$status" == "pass" ]]; then
        append_result "$name" "pass" "$detail"
        INSTALLED=$((INSTALLED + 1))
        log_ok "$name $detail"
      else
        append_result "$name" "fail" "$detail"
        FAILED=$((FAILED + 1))
        log_err "$name $detail"
      fi
      ;;
    source_git)
      # Build from git (e.g. BWA) — best effort
      repo_url="$(jq -r ".tools[$i].url // empty" "$CONFIG_FILE")"
      src_dir="$PLATFORM_TOOLS/src/$binary"
      if command -v "$binary" &>/dev/null && verify_arch "$binary"; then
        link_into_tools "$binary"
        append_result "$name" "pass" "already present: $(command -v "$binary")"
        INSTALLED=$((INSTALLED + 1))
      else
        mkdir -p "$PLATFORM_TOOLS/src"
        if [[ ! -d "$src_dir/.git" ]]; then
          git clone --depth 1 "$repo_url" "$src_dir" || {
            append_result "$name" "fail" "git clone failed"
            FAILED=$((FAILED + 1))
            continue
          }
        fi
        make -C "$src_dir" -j"$(nproc)" || {
          append_result "$name" "fail" "make failed"
          FAILED=$((FAILED + 1))
          continue
        }
        if [[ -x "$src_dir/$binary" ]]; then
          cp -f "$src_dir/$binary" "${CONDA_PREFIX}/bin/$binary"
          ln -sfn "${CONDA_PREFIX}/bin/$binary" "$PLATFORM_TOOLS/bin/$binary"
          append_result "$name" "pass" "built: $src_dir/$binary"
          INSTALLED=$((INSTALLED + 1))
        else
          append_result "$name" "fail" "build produced no binary"
          FAILED=$((FAILED + 1))
        fi
      fi
      ;;
    *)
      append_result "$name" "fail" "unknown method: $method"
      FAILED=$((FAILED + 1))
      ;;
  esac
done

jq -n \
  --arg platform "$(jq -r '.platform // empty' "$CONFIG_FILE")" \
  --arg config "$CONFIG_FILE" \
  --argjson results "$RESULTS" \
  --argjson installed "$INSTALLED" \
  --argjson skipped "$SKIPPED" \
  --argjson failed "$FAILED" \
  '{platform:$platform, config:$config, installed:$installed, skipped:$skipped, failed:$failed, results:$results}' \
  >"$REPORT_FILE"

log_info "report → $REPORT_FILE"
log_ok "CLI done: installed=$INSTALLED skipped=$SKIPPED failed=$FAILED"
# Non-zero only if hard failures (skips are OK)
[[ "$FAILED" -eq 0 ]]
