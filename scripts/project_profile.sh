#!/usr/bin/env bash

# Loaded by ../build.  The public command stays "build project.dpr profile";
# this file implements the optional, versioned project description beside the
# DPR without leaking compiler switches into developer instructions.

add_project_source_tree() {
  local tree=$1 path
  [[ -d "$tree" ]] || {
    echo "project source tree does not exist: $tree" >&2
    return 1
  }
  options+=("-Fu$tree" "-Fi$tree")
  while IFS= read -r -d '' path; do
    options+=("-Fu$path" "-Fi$path")
  done < <(find -L "$tree" -mindepth 1 -type d \
    -not -path '*/.git' -not -path '*/.git/*' \
    -not -path '*/.moonbot' -not -path '*/.moonbot/*' \
    -not -path '*/dcu' -not -path '*/dcu/*' \
    -not -path '*/build' -not -path '*/build/*' \
    -print0 | sort -z)
}

project_manifest_path() {
  printf '%s.mooncompiler' "${project%.*}"
}

manifest_absolute_path() {
  local value=$1
  if [[ "$value" == /* ]]; then
    printf '%s' "$value"
  else
    printf '%s/%s' "$manifest_dir" "$value"
  fi
}

ensure_project_dependency() {
  local spec=$1 name url commit source_list destination temporary head
  local -a dependency_sources
  IFS='|' read -r name url commit source_list <<<"$spec"
  [[ -n "$name" && -n "$url" && -n "$commit" && -n "$source_list" ]] || {
    echo "invalid dependency entry in $manifest: $spec" >&2
    return 1
  }
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || {
    echo "invalid dependency name in $manifest: $name" >&2
    return 1
  }
  [[ "$commit" =~ ^[0-9a-fA-F]{40}$ ]] || {
    echo "dependency must use a full 40-character commit: $name" >&2
    return 1
  }
  command -v git >/dev/null 2>&1 || {
    echo "git is required to fetch project dependency: $name" >&2
    return 1
  }

  destination="$STATE/dependencies/$name/${commit,,}"
  if [[ ! -d "$destination/.git" ]]; then
    mkdir -p "$(dirname "$destination")"
    temporary="$destination.new.$$"
    rm -rf "$temporary"
    if ! git init -q "$temporary" ||
       ! git -C "$temporary" remote add origin "$url" ||
       ! git -C "$temporary" fetch -q --depth=1 origin "$commit" ||
       ! git -C "$temporary" checkout -q --detach FETCH_HEAD; then
      rm -rf "$temporary"
      echo "could not fetch pinned dependency $name at $commit" >&2
      return 1
    fi
    head=$(git -C "$temporary" rev-parse HEAD)
    if [[ "${head,,}" != "${commit,,}" ]]; then
      rm -rf "$temporary"
      echo "dependency $name resolved to $head instead of $commit" >&2
      return 1
    fi
    mv "$temporary" "$destination"
  fi

  head=$(git -C "$destination" rev-parse HEAD)
  [[ "${head,,}" == "${commit,,}" ]] || {
    echo "cached dependency $name is at $head instead of $commit" >&2
    return 1
  }
  [[ -z "$(git -C "$destination" status --porcelain --untracked-files=all)" ]] || {
    echo "cached dependency is not clean: $destination" >&2
    return 1
  }

  local relative source
  IFS=',' read -ra dependency_sources <<<"$source_list"
  for relative in "${dependency_sources[@]}"; do
    source="$destination/$relative"
    add_project_source_tree "$source"
  done
}

compile_project_ansi_bundle() {
  local entry=$1 ansi_unit_dir="$unit_dir/ansi" source path
  local ansi_options=(
    -n "@$TOOLCHAIN/etc/fpc.cfg" -Mdelphi -Mansistrings
    -MduplicateLocals -Madvancedrecords -Marrayoperators
    -Munderscoreisseparator -Mfunctionreferences -Manonymousfunctions
    -Minlinevars -Mimplicitgenerics -Mautoderef
    -Px86_64 -Tlinux -Rintel -dPOSIX -B
    -dMOONBOT_MM_PROFILE_REQUIRED -dFPCMM_BOOSTER -dFPCMM_MOONSHARD
    "--pinned-unit=mormot.core.fpcx64mm=$MM_SOURCE"
    --required-first-unit=mormot.core.fpcx64mm
    "${namespace_options[@]}"
    "-FU$ansi_unit_dir"
  )
  mkdir -p "$ansi_unit_dir"
  for source in "${ansi_sources[@]}"; do
    while IFS= read -r -d '' path; do
      ansi_options+=("-Fu$path" "-Fi$path")
    done < <(find -L "$source" -type d \
      -not -path '*/.git' -not -path '*/.git/*' \
      -not -path '*/dcu' -not -path '*/dcu/*' \
      -not -path '*/build' -not -path '*/build/*' \
      -print0 | sort -z)
  done
  "$TOOLCHAIN/bin/fpc" "${ansi_options[@]}" "${profile_options[@]}" "$entry"
  options+=("-Fu$ansi_unit_dir")
}

configure_project_profile() {
  local line key value source entry=
  manifest=$(project_manifest_path)
  manifest_dir=$project_dir
  local -a sources=() dependencies=() aliases=()
  ansi_sources=()

  if [[ ! -f "$manifest" ]]; then
    add_project_source_tree "$project_dir"
    return
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    line=${line%$'\r'}
    [[ -z "$line" || "$line" == \#* ]] && continue
    [[ "$line" == *=* ]] || {
      echo "invalid line in $manifest: $line" >&2
      return 1
    }
    key=${line%%=*}
    value=${line#*=}
    [[ -n "$value" ]] || {
      echo "empty $key entry in $manifest" >&2
      return 1
    }
    case "$key" in
      source) sources+=("$(manifest_absolute_path "$value")") ;;
      alias) aliases+=("$value") ;;
      dependency) dependencies+=("$value") ;;
      ansi-source) ansi_sources+=("$(manifest_absolute_path "$value")") ;;
      ansi-entry)
        [[ -z "$entry" ]] || {
          echo "duplicate ansi-entry in $manifest" >&2
          return 1
        }
        entry=$(manifest_absolute_path "$value")
        ;;
      *)
        echo "unknown project manifest directive in $manifest: $key" >&2
        return 1
        ;;
    esac
  done < "$manifest"

  options+=("-Fu$project_dir" "-Fi$project_dir")
  for value in "${aliases[@]}"; do
    [[ "$value" == *=* ]] || {
      echo "invalid unit alias in $manifest: $value" >&2
      return 1
    }
    options+=("-Ua$value")
  done
  for value in "${dependencies[@]}"; do
    ensure_project_dependency "$value"
  done
  for source in "${sources[@]}"; do
    add_project_source_tree "$source"
  done

  if [[ -n "$entry" ]]; then
    [[ -f "$entry" ]] || {
      echo "ANSI bundle entry does not exist: $entry" >&2
      return 1
    }
    [[ ${#ansi_sources[@]} -gt 0 ]] || {
      echo "ansi-entry requires at least one ansi-source in $manifest" >&2
      return 1
    }
    for source in "${ansi_sources[@]}"; do
      [[ -d "$source" ]] || {
        echo "ANSI source tree does not exist: $source" >&2
        return 1
      }
    done
    compile_project_ansi_bundle "$entry"
  elif [[ ${#ansi_sources[@]} -gt 0 ]]; then
    echo "ansi-source requires ansi-entry in $manifest" >&2
    return 1
  fi
}
