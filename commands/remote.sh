#!/bin/bash
# commands/remote.sh - Remote pull orchestration for ilma

set -euo pipefail

ILMA_DIR="$(dirname "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")")"

REMOTE_JOB_PARSE_ERROR=""
REMOTE_JOB_MANIFEST=()

remote_usage() {
    cat <<'EOF'
Usage: ilma remote pull <job-file> [OPTIONS]

Run a remote pull job: stage files from a remote host using an rsync manifest,
then invoke the local ilma backup pipeline on the staged copy.

LOCAL PATHS (set in the job file):
  stage_dir   Directory on this machine that receives the rsync pull.
              Example: /tmp/ilma-stage/server-user
  target_dir  Directory on this machine where ilma writes .bak/.context/archives.
              Example: ~/backups/server/user

OPTIONS:
  --mode LIST          Override job mode (comma-separated: backup,archive,encrypt,context)
  --target DIR         Override target directory for backup artifacts (--target passthrough)
  --stage-dir DIR      Override local staging directory
  --verify             Force verification after backup
  --no-verify          Disable verification even if job enables it
  --cleanup-stage      Delete staging directory after successful run
  --keep-stage         Keep staging directory (overrides cleanup true in job)
  --dry-run            Preview rsync pull without transferring or backing up
  -j, --job FILE       Add a job file (may be repeated)
  -h, --help           Show this help message

JOB FILE FORMAT (INI-like):
  [job]
  id=server-user
  remote=user@server
  remote_root=~
  stage_dir=/var/tmp/ilma/stage/server-user
  target_dir=/backups/server/user
  mode=backup,archive
  verify=true
  cleanup_stage=false
  basename=server-user

  [manifest]
  # rsync filter syntax copied locally so manifests survive remote loss
  + .ssh/
  + .ssh/**
  + .config/
  + .config/**
  - .cache/
  - .cache/**

Only the remote and stage_dir keys are required. Defaults:
  remote_root=~
  mode=backup
  verify=false
  cleanup_stage=false

The manifest block is required and uses rsync filter syntax ("+"/"-" rules).
It is stored locally (e.g. nodes/server/user.ini) and fed directly to rsync.
During development we keep them in the repo under nodes/, but production layouts
should prefer ~/.config/ilma/nodes/<node>.ini so manifests survive remote loss.
EOF
}

die() {
    echo "Error: $1" >&2
    exit 1
}

trim() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s' "$value"
}

to_lower() {
    printf '%s' "${1,,}"
}

parse_boolean() {
    local raw
    raw="$(to_lower "$1")"
    case "$raw" in
        true|yes|1) echo "true" ;;
        false|no|0) echo "false" ;;
        "") echo "" ;;
        *) die "Invalid boolean value '$1'" ;;
    esac
}

normalize_manifest_for_rsync() {
    local input="$1"
    local output="$2"
    local raw_line parsed include_path work_path dir_path include_rule
    declare -A emitted=()

    emitted["+ /"]=1
    echo "+ /" > "$output"

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        local printable_line="$raw_line"
        parsed="${raw_line%%#*}"
        parsed="$(trim "$parsed")"

        if [[ "$parsed" == "+"* ]]; then
            include_path="${parsed#+}"
            include_path="$(trim "$include_path")"
            if [[ -n "$include_path" ]]; then
                work_path="$include_path"
                case "$work_path" in
                    */\*\*) work_path="${work_path%%/**}" ;;
                esac
                work_path="${work_path%/}"

                while [[ -n "$work_path" && "$work_path" != "." ]]; do
                    dir_path="$(dirname "$work_path")"

                    if [[ "$dir_path" == "." ]]; then
                        break
                    fi

                    if [[ "$dir_path" == "/" ]]; then
                        if [[ -z "${emitted["+ /"]:-}" ]]; then
                            echo "+ /" >> "$output"
                            emitted["+ /"]=1
                        fi
                        break
                    fi

                    include_rule="+ ${dir_path%/}/"
                    if [[ -z "${emitted["$include_rule"]:-}" ]]; then
                        echo "$include_rule" >> "$output"
                        emitted["$include_rule"]=1
                    fi

                    work_path="$dir_path"
                done
            fi
        fi

        echo "$printable_line" >> "$output"
    done < "$input"
}

reset_job_state() {
    REMOTE_JOB_ID=""
    REMOTE_JOB_REMOTE=""
    REMOTE_JOB_REMOTE_ROOT="~"
    REMOTE_JOB_STAGE_DIR=""
    REMOTE_JOB_TARGET_DIR=""
    REMOTE_JOB_MODE="backup"
    REMOTE_JOB_VERIFY="false"
    REMOTE_JOB_CLEANUP_STAGE="false"
    REMOTE_JOB_BASENAME=""
    REMOTE_JOB_MANIFEST=()
}

try_parse_remote_job() {
    local job_file="$1"
    REMOTE_JOB_PARSE_ERROR=""
    if [[ ! -f "$job_file" ]]; then
        REMOTE_JOB_PARSE_ERROR="Job file not found: $job_file"
        return 1
    fi

    reset_job_state
    local section=""
    local in_manifest="false"
    local raw_line

    while IFS= read -r raw_line || [[ -n "$raw_line" ]]; do
        raw_line="${raw_line%$'\r'}"
        local check_line
        check_line="${raw_line%%#*}"
        check_line="$(trim "$check_line")"

        if [[ "$check_line" =~ ^\[(.+)\]$ ]]; then
            section="${BASH_REMATCH[1]}"
            local section_lower
            section_lower="$(to_lower "$section")"
            if [[ "$section_lower" == "manifest" || "$section_lower" == "manifest:"* ]]; then
                in_manifest=true
            else
                in_manifest=false
            fi
            continue
        fi

        if [[ "$in_manifest" == "true" ]]; then
            REMOTE_JOB_MANIFEST+=("$raw_line")
            continue
        fi

        if [[ -z "$check_line" ]]; then
            continue
        fi

        if [[ "$check_line" =~ ^([^=]+)=(.*)$ ]]; then
            local key
            key="$(trim "${BASH_REMATCH[1]}")"
            local value
            value="$(trim "${BASH_REMATCH[2]}")"
            local key_lower
            key_lower="$(to_lower "$key")"

            if [[ "$section" == "job" || "$section" == "remote" || -z "$section" ]]; then
                case "$key_lower" in
                    id) REMOTE_JOB_ID="$value" ;;
                    remote) REMOTE_JOB_REMOTE="$value" ;;
                    remote_root) REMOTE_JOB_REMOTE_ROOT="$value" ;;
                    stage_dir) REMOTE_JOB_STAGE_DIR="$value" ;;
                    target_dir) REMOTE_JOB_TARGET_DIR="$value" ;;
                    mode) REMOTE_JOB_MODE="$(to_lower "$value")" ;;
                    verify) REMOTE_JOB_VERIFY="$(parse_boolean "$value")" ;;
                    cleanup_stage) REMOTE_JOB_CLEANUP_STAGE="$(parse_boolean "$value")" ;;
                    basename) REMOTE_JOB_BASENAME="$value" ;;
                esac
            fi
        fi
    done < "$job_file"

    if [[ -z "$REMOTE_JOB_REMOTE" ]]; then
        REMOTE_JOB_PARSE_ERROR="Job file missing 'remote' value"
        return 1
    fi

    if [[ -z "$REMOTE_JOB_STAGE_DIR" ]]; then
        REMOTE_JOB_PARSE_ERROR="Job file missing 'stage_dir' value"
        return 1
    fi

    if [[ ${#REMOTE_JOB_MANIFEST[@]} -eq 0 ]]; then
        REMOTE_JOB_PARSE_ERROR="Job file missing [manifest] section"
        return 1
    fi

    if [[ -z "$REMOTE_JOB_MODE" ]]; then
        REMOTE_JOB_MODE="backup"
    fi

    if [[ -z "$REMOTE_JOB_VERIFY" ]]; then
        REMOTE_JOB_VERIFY="false"
    fi

    if [[ -z "$REMOTE_JOB_CLEANUP_STAGE" ]]; then
        REMOTE_JOB_CLEANUP_STAGE="false"
    fi

    if [[ -z "$REMOTE_JOB_REMOTE_ROOT" ]]; then
        REMOTE_JOB_REMOTE_ROOT="~"
    fi

    return 0
}

parse_remote_job() {
    if ! try_parse_remote_job "$1"; then
        die "$REMOTE_JOB_PARSE_ERROR"
    fi
}

normalize_mode_list() {
    local raw="$1"
    local modes=()
    IFS=',' read -ra parts <<< "$raw"
    for part in "${parts[@]}"; do
        local trimmed
        trimmed="$(trim "$part")"
        [[ -z "$trimmed" ]] && continue
        trimmed="$(to_lower "$trimmed")"
        case "$trimmed" in
            backup|archive|encrypt|context|none)
                modes+=("$trimmed")
                ;;
            *)
                die "Unsupported mode '$trimmed' (valid: backup, archive, encrypt, context, none)"
                ;;
        esac
    done

    if [[ ${#modes[@]} -eq 0 ]]; then
        modes=(backup)
    fi

    printf '%s\n' "${modes[@]}"
}

remote_pull() {
    local job_file="$1"
    shift

    local override_mode=""
    local override_target_dir=""
    local override_stage_dir=""
    local override_verify=""
    local override_cleanup=""
    local dry_run="false"

    while (( $# > 0 )); do
        case "$1" in
            --mode)
                [[ -n "${2:-}" ]] || die "--mode requires an argument"
                override_mode="${2,,}"
                shift 2
                ;;
            --mode=*)
                override_mode="${1#--mode=}"
                override_mode="${override_mode,,}"
                shift
                ;;
            --target)
                [[ -n "${2:-}" ]] || die "--target requires a directory"
                override_target_dir="$2"
                shift 2
                ;;
            --target=*)
                override_target_dir="${1#--target=}"
                shift
                ;;
            --stage-dir)
                [[ -n "${2:-}" ]] || die "--stage-dir requires a directory"
                override_stage_dir="$2"
                shift 2
                ;;
            --stage-dir=*)
                override_stage_dir="${1#--stage-dir=}"
                shift
                ;;
            --verify)
                override_verify="true"
                shift
                ;;
            --no-verify)
                override_verify="false"
                shift
                ;;
            --cleanup-stage)
                override_cleanup="true"
                shift
                ;;
            --keep-stage)
                override_cleanup="false"
                shift
                ;;
            --dry-run)
                dry_run="true"
                shift
                ;;
            -h|--help)
                remote_usage
                exit 0
                ;;
            *)
                die "Unknown option for remote pull: $1"
                ;;
        esac
    done

    parse_remote_job "$job_file"

    local modes_raw
    modes_raw="$REMOTE_JOB_MODE"
    if [[ -n "$override_mode" ]]; then
        modes_raw="$override_mode"
    fi

    mapfile -t resolved_modes < <(normalize_mode_list "$modes_raw")

    local stage_dir
    stage_dir="${override_stage_dir:-$REMOTE_JOB_STAGE_DIR}"
    [[ -n "$stage_dir" ]] || die "Stage directory is required"
    stage_dir="${stage_dir/#\~/$HOME}"
    mkdir -p "$stage_dir"
    stage_dir="$(readlink -f "$stage_dir")"

    local target_dir
    target_dir="${override_target_dir:-$REMOTE_JOB_TARGET_DIR}"

    if [[ -n "$target_dir" ]]; then
        target_dir="${target_dir/#\~/$HOME}"
        if ! mkdir -p "$target_dir" 2>/dev/null; then
            die "Target directory '$target_dir' is not accessible"
        fi
        target_dir="$(readlink -f "$target_dir")"
    fi

    local verify
    verify="${override_verify:-$REMOTE_JOB_VERIFY}"
    [[ -n "$verify" ]] || verify="false"

    local cleanup_stage
    cleanup_stage="${override_cleanup:-$REMOTE_JOB_CLEANUP_STAGE}"
    [[ -n "$cleanup_stage" ]] || cleanup_stage="false"

    local manifest_temp=""
    local normalized_manifest=""
    manifest_temp="$(mktemp)"
    normalized_manifest="$(mktemp)"
    trap '[[ -n "$manifest_temp" ]] && rm -f "$manifest_temp"; [[ -n "$normalized_manifest" ]] && rm -f "$normalized_manifest"' EXIT

    if [[ ${#REMOTE_JOB_MANIFEST[@]} -eq 0 ]]; then
        die "Manifest section is empty for job file: $job_file"
    fi

    printf '%s\n' "${REMOTE_JOB_MANIFEST[@]}" >"$manifest_temp"

    normalize_manifest_for_rsync "$manifest_temp" "$normalized_manifest"

    local remote_root
    remote_root="$REMOTE_JOB_REMOTE_ROOT"
    [[ -n "$remote_root" ]] || remote_root="."

    if [[ "$remote_root" != */ ]]; then
        remote_root="$remote_root/"
    fi

    local rsync_source
    rsync_source="${REMOTE_JOB_REMOTE}:${remote_root}"

    echo "Staging files into $stage_dir"
    local rsync_args
    rsync_args=(rsync -av --delete "--filter=merge $normalized_manifest")

    if [[ "$dry_run" == "true" ]]; then
        rsync_args+=(--dry-run)
    fi

    rsync_args+=("$rsync_source" "$stage_dir/")

    if ! "${rsync_args[@]}"; then
        die "rsync pull failed"
    fi

    if [[ "$dry_run" == "true" ]]; then
        echo "Dry run complete. No backup operations performed."
        rm -f "$manifest_temp"
        rm -f "$normalized_manifest"
        manifest_temp=""
        normalized_manifest=""
        trap - EXIT
        return
    fi

    local metadata_dir
    metadata_dir="$stage_dir/.ilma-remote"
    mkdir -p "$metadata_dir"
    cp "$manifest_temp" "$metadata_dir/manifest.filter"
    cp "$normalized_manifest" "$metadata_dir/manifest.normalized"

    local meta_file
    meta_file="$metadata_dir/job.meta"
    {
        echo "remote=${REMOTE_JOB_REMOTE}"
        echo "job_file=$job_file"
        echo "manifest_lines=${#REMOTE_JOB_MANIFEST[@]}"
        echo "fetched_at=$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
        echo "staged_dir=$stage_dir"
        echo "mode=${resolved_modes[*]}"
    } > "$meta_file"

    local run_backup="false"
    local op
    for op in "${resolved_modes[@]}"; do
        case "$op" in
            backup|archive|encrypt|context)
                run_backup="true"
                break
                ;;
        esac
    done

    if [[ "$run_backup" == "false" ]]; then
        echo "No backup operations requested by mode; staging complete."
        return
    fi

    local backup_cmd
    backup_cmd=("$ILMA_DIR/ilma" backup)

    if [[ "$verify" == "true" ]]; then
        backup_cmd+=(--verify)
    fi

    if [[ -n "$target_dir" ]]; then
        backup_cmd+=(--target "$target_dir")
    fi

    if [[ -n "$REMOTE_JOB_BASENAME" ]]; then
        backup_cmd+=(--basename "$REMOTE_JOB_BASENAME")
    fi

    for op in "${resolved_modes[@]}"; do
        case "$op" in
            backup) backup_cmd+=(--backup) ;;
            archive) backup_cmd+=(--archive) ;;
            encrypt) backup_cmd+=(--encrypt) ;;
            context) backup_cmd+=(--context) ;;
            none) ;; # skip
        esac
    done

    backup_cmd+=("$stage_dir")

    echo "Running ilma backup pipeline on staged data"
    "${backup_cmd[@]}"

    rm -f "$manifest_temp" "$normalized_manifest"
    manifest_temp=""
    normalized_manifest=""
    trap - EXIT

    if [[ "$cleanup_stage" == "true" ]]; then
        echo "Cleaning up staging directory $stage_dir"
        if [[ "$stage_dir" == "/" ]]; then
            die "Refusing to remove staging directory '/'"
        fi
        rm -rf -- "$stage_dir"
    fi
}

pull_alias_main() {
    local raw_args=("$@")
    local args=()
    local found_pull=false
    local token

    for token in "${raw_args[@]}"; do
        if [[ "$found_pull" == false ]]; then
            if [[ "$token" == "pull" ]]; then
                found_pull=true
            fi
            continue
        fi
        args+=("$token")
    done

    if [[ "$found_pull" == false ]]; then
        die "Pull command invocation malformed"
    fi

    if [[ ${#args[@]} -eq 0 ]]; then
        remote_usage
        exit 1
    fi

    local -a job_specs=()
    local -a passthrough=()

    local idx=0
    while (( idx < ${#args[@]} )); do
        local current="${args[idx]}"
        case "$current" in
            -j|--job|--jobs)
                (( idx + 1 < ${#args[@]} )) || die "$current requires a value"
                local job_value="${args[idx + 1]}"
                job_value="${job_value/#\~/$HOME}"
                job_specs+=("$job_value")
                idx=$((idx + 2))
                continue
                ;;
            --dry-run|--cleanup-stage|--keep-stage|--verify|--no-verify)
                passthrough+=("$current")
                idx=$((idx + 1))
                continue
                ;;
            --mode|--target|--stage-dir|--basename)
                (( idx + 1 < ${#args[@]} )) || die "$current requires a value"
                passthrough+=("$current" "${args[idx + 1]}")
                idx=$((idx + 2))
                continue
                ;;
            --mode=*|--target=*|--stage-dir=*|--basename=*)
                passthrough+=("$current")
                idx=$((idx + 1))
                continue
                ;;
            -h|--help)
                remote_usage
                exit 0
                ;;
            --)
                passthrough+=("${args[@]:idx}")
                break
                ;;
            *)
                if [[ "$current" == -* ]]; then
                    passthrough+=("$current")
                else
                    local job_value="$current"
                    job_value="${job_value/#\~/$HOME}"
                    job_specs+=("$job_value")
                fi
                idx=$((idx + 1))
                continue
                ;;
        esac
    done

    if [[ ${#job_specs[@]} -eq 0 ]]; then
        die "No job files specified. Use --job <file> or provide a job path."
    fi

    local job_spec
    for job_spec in "${job_specs[@]}"; do
        local job_path="$job_spec"
        job_path="${job_path/#\~/$HOME}"
        if [[ ! -f "$job_path" ]]; then
            die "Job file not found: $job_spec"
        fi
        if ! job_path="$(readlink -f "$job_path")"; then
            die "Unable to resolve job file path: $job_spec"
        fi
        echo "Running job: $job_path"
        remote_pull "$job_path" "${passthrough[@]}"
    done

    return 0
}

remote_main() {
    if [[ $# -eq 0 ]]; then
        remote_usage
        exit 1
    fi

    shift  # Drop the literal 'remote'

    if [[ $# -eq 0 ]]; then
        remote_usage
        exit 1
    fi

    local subcommand="$1"
    shift

    case "$subcommand" in
        pull)
            pull_alias_main remote pull "$@"
            ;;
        -h|--help|help)
            remote_usage
            ;;
        *)
            die "Unknown remote subcommand '$subcommand'"
            ;;
    esac
}
