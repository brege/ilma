#!/bin/bash
# Shared helpers for resolving ilma configuration paths.

get_ilma_config_home() {
  if [[ -n "${ILMA_CONFIG_HOME:-}" ]]; then
    printf '%s\n' "${ILMA_CONFIG_HOME%/}"
    return
  fi
  local base="${XDG_CONFIG_HOME:-$HOME/.config}"
  printf '%s\n' "$base/ilma"
}

get_ilma_global_config_path() {
  if [[ -n "${ILMA_CONFIG_FILE:-}" ]]; then
    local candidate="${ILMA_CONFIG_FILE/#\~/$HOME}"
    if [[ -f "$candidate" ]]; then
      readlink -f "$candidate"
      return 0
    fi
  fi

  local config_home
  config_home="$(get_ilma_config_home)"
  local user_config="$config_home/config.ini"
  if [[ -f "$user_config" ]]; then
    printf '%s\n' "$user_config"
    return 0
  fi

  local repo_config="$ILMA_DIR/config.ini"
  if [[ -f "$repo_config" ]]; then
    printf '%s\n' "$repo_config"
    return 0
  fi

  return 1
}

get_ilma_nodes_dirs() {
  local -a dirs=()
  local config_home
  config_home="$(get_ilma_config_home)"
  local home_nodes="$config_home/nodes"
  if [[ -d "$home_nodes" ]]; then
    dirs+=("$home_nodes")
  fi
  local repo_nodes="$ILMA_DIR/nodes"
  if [[ -d "$repo_nodes" && "$repo_nodes" != "$home_nodes" ]]; then
    dirs+=("$repo_nodes")
  fi
  if [[ ${#dirs[@]} -gt 0 ]]; then
    printf '%s\n' "${dirs[@]}"
  fi
  return 0
}
