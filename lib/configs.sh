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

get_ilma_user_projects_dir() {
    local config_home
    config_home="$(get_ilma_config_home)"
    local dir="$config_home/projects"
    if [[ -d "$dir" ]]; then
        printf '%s\n' "$dir"
    fi
}

get_ilma_builtin_projects_dir() {
    local dir="$ILMA_DIR/configs/projects"
    if [[ -d "$dir" ]]; then
        printf '%s\n' "$dir"
    fi
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

resolve_ilma_type_config() {
    local type="$1"
    local user_dir
    user_dir="$(get_ilma_user_projects_dir)"
    if [[ -n "$user_dir" ]]; then
        local user_candidate="$user_dir/${type}.ilma.conf"
        if [[ -f "$user_candidate" ]]; then
            printf '%s\n' "$user_candidate"
            return 0
        fi
    fi

    local builtin_dir
    builtin_dir="$(get_ilma_builtin_projects_dir)"
    if [[ -n "$builtin_dir" ]]; then
        local builtin_candidate="$builtin_dir/${type}.ilma.conf"
        if [[ -f "$builtin_candidate" ]]; then
            printf '%s\n' "$builtin_candidate"
            return 0
        fi
    fi

    return 1
}
