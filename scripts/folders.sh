#!/usr/bin/env bash
# Attach host folders to a running Claude Science container.
#
# Usage: scripts/folders.sh list
#        scripts/folders.sh add <host-folder> [--rw] [--name NAME]
#        scripts/folders.sh remove <NAME | host-folder>
# Env:   CONTAINER=claude-science
#
# Docker can't add a mount to a running container, so add/remove recreate it
# with the same settings plus/minus the folder. Your login, projects and
# environments live in the data volume, which is kept, so nothing is lost.
#
#   - Started with `docker compose`: the folders are written to a managed
#     compose.override.yaml next to the compose file, then `compose up -d`.
#   - Started with `docker run`: the container is recreated from its own
#     settings (image, ports, env, volumes, security options, restart policy).
#
# Added folders appear in Claude Science at /home/claude/mounts/<NAME>,
# read-only unless you pass --rw.
set -euo pipefail

CONTAINER="${CONTAINER:-claude-science}"
MOUNTS_DIR=/home/claude/mounts
OVERRIDE_MARKER="# Managed by scripts/folders.sh"

# Temp file with the desired set of extra folders; removed on exit.
desired=""
trap 'rm -f "$desired"' EXIT

die() { echo "folders: $*" >&2; exit 1; }

usage() {
    sed -n '4,7p' "$0" | sed 's/^# \{0,1\}//'
    exit "${1:-0}"
}

need_container() {
    docker inspect "$CONTAINER" >/dev/null 2>&1 \
        || die "no container named '$CONTAINER' (set CONTAINER=... if you renamed it)"
}

# Docker Desktop reports some bind sources by its VM-internal path; map them
# back to the host path so they can be passed to Docker again.
host_path() {
    local p=$1
    case "$p" in
        /host_mnt/*)
            [ -e "${p#/host_mnt}" ] && p=${p#/host_mnt} ;;
        /run/desktop/mnt/host/?/*)  # Windows: /run/desktop/mnt/host/c/Users -> C:/Users
            local rest=${p#/run/desktop/mnt/host/}
            p="$(printf '%s' "${rest%%/*}" | tr '[:lower:]' '[:upper:]'):/${rest#*/}" ;;
    esac
    printf '%s' "$p"
}

# One line per bind mount: source|destination|rw(true/false)
bind_mounts() {
    local src dst rw
    docker inspect -f '{{range .Mounts}}{{if eq .Type "bind"}}{{.Source}}|{{.Destination}}|{{.RW}}{{"\n"}}{{end}}{{end}}' \
        "$CONTAINER" | sed '/^$/d' \
        | while IFS='|' read -r src dst rw; do
            echo "$(host_path "$src")|$dst|$rw"
        done
}

# Only the folders this script manages (under /home/claude/mounts).
extra_mounts() { bind_mounts | awk -F'|' -v d="$MOUNTS_DIR/" 'index($2, d) == 1'; }

cmd_list() {
    need_container
    local any="" src dst rw
    while IFS='|' read -r src dst rw; do
        [ -n "$dst" ] || continue
        case "$dst" in
            /home/claude/ClaudeScience|"$MOUNTS_DIR"/*) ;;
            *) continue ;;
        esac
        any=1
        printf '%-45s <- %s (%s)\n' "$dst" "$src" "$([ "$rw" = true ] && echo read-write || echo read-only)"
    done < <(bind_mounts)
    [ -n "$any" ] || echo "No folders attached. Add one with: $0 add <folder>"
}

# --- recreate: docker compose ------------------------------------------------
compose_label() {
    docker inspect -f "{{index .Config.Labels \"com.docker.compose.$1\"}}" "$CONTAINER" 2>/dev/null || true
}

# $1 = file with lines source|destination|rw  (the complete desired set)
apply_compose() {
    local desired=$1 workdir service project configs override src dst rw
    workdir=$(compose_label project.working_dir)
    service=$(compose_label service)
    project=$(compose_label project)
    configs=$(compose_label project.config_files)
    override="$workdir/compose.override.yaml"

    if [ -f "$override" ] && ! head -1 "$override" | grep -qF "$OVERRIDE_MARKER"; then
        die "$override exists and was not written by this script - add the folder there by hand:
      - <host-folder>:$MOUNTS_DIR/<name>:ro"
    fi

    {
        echo "$OVERRIDE_MARKER - extra folders for Claude Science."
        echo "# Edit with scripts/folders.sh add/remove (or by hand, then 'docker compose up -d')."
        echo "services:"
        echo "  ${service}:"
        if [ -s "$desired" ]; then
            echo "    volumes:"
            while IFS='|' read -r src dst rw; do
                src=${src//\\/\\\\}; src=${src//\"/\\\"}
                echo "      - type: bind"
                echo "        source: \"$src\""
                echo "        target: \"$dst\""
                echo "        read_only: $([ "$rw" = true ] && echo false || echo true)"
            done < "$desired"
        else
            echo "    {}"
        fi
    } > "$override"

    local args=(compose --project-name "$project" --project-directory "$workdir")
    local f
    IFS=',' read -r -a files <<< "$configs"
    for f in "${files[@]}"; do args+=(-f "$f"); done
    args+=(-f "$override")
    echo "Updating $override and recreating '$service'..."
    docker "${args[@]}" up -d --no-build "$service"
}

# --- recreate: docker run ----------------------------------------------------
apply_run() {
    local desired=$1 image restart name src dst rw
    image=$(docker inspect -f '{{.Config.Image}}' "$CONTAINER")
    restart=$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$CONTAINER")

    local args=(run -d --name "$CONTAINER")
    [ -n "$restart" ] && [ "$restart" != no ] && args+=(--restart "$restart")

    local line
    while IFS= read -r line; do
        [ -n "$line" ] && args+=(-e "$line")
    done < <(docker inspect -f '{{range .Config.Env}}{{println .}}{{end}}' "$CONTAINER" | grep -E '^(CLAUDE_SCIENCE_|CS_)')

    while IFS= read -r line; do
        [ -n "$line" ] && args+=(-p "$line")
    done < <(docker inspect -f '{{range $p, $b := .HostConfig.PortBindings}}{{range $b}}{{if .HostIp}}{{.HostIp}}:{{end}}{{.HostPort}}:{{$p}}{{"\n"}}{{end}}{{end}}' "$CONTAINER")

    while IFS= read -r line; do
        [ -n "$line" ] && args+=(--security-opt "$line")
    done < <(docker inspect -f '{{range .HostConfig.SecurityOpt}}{{println .}}{{end}}' "$CONTAINER")
    # systempaths=unconfined is not recorded in SecurityOpt; it shows up as
    # empty masked paths, so carry it over from there.
    if [ "$(docker inspect -f '{{len .HostConfig.MaskedPaths}}' "$CONTAINER")" = 0 ]; then
        args+=(--security-opt systempaths=unconfined)
    fi

    # Named volumes (the data volume!) and every bind mount except the ones
    # this script manages, which come from the desired set instead.
    while IFS='|' read -r name dst rw; do
        [ -n "$name" ] && args+=(-v "$name:$dst$([ "$rw" = true ] || echo :ro)")
    done < <(docker inspect -f '{{range .Mounts}}{{if eq .Type "volume"}}{{.Name}}|{{.Destination}}|{{.RW}}{{"\n"}}{{end}}{{end}}' "$CONTAINER")
    while IFS='|' read -r src dst rw; do
        case "$dst" in "$MOUNTS_DIR"/*) continue ;; esac
        [ -n "$dst" ] && args+=(--mount "type=bind,\"source=$src\",\"target=$dst\"$([ "$rw" = true ] || echo ,readonly)")
    done < <(bind_mounts)
    while IFS='|' read -r src dst rw; do
        args+=(--mount "type=bind,\"source=$src\",\"target=$dst\"$([ "$rw" = true ] || echo ,readonly)")
    done < "$desired"

    args+=("$image")

    echo "Recreating '$CONTAINER' with the new folders (your data volume is kept)..."
    docker stop "$CONTAINER" >/dev/null
    docker rename "$CONTAINER" "$CONTAINER-old" >/dev/null
    if docker "${args[@]}" >/dev/null; then
        docker rm "$CONTAINER-old" >/dev/null
    else
        echo "folders: starting the new container failed - restoring the old one" >&2
        docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        docker rename "$CONTAINER-old" "$CONTAINER"
        docker start "$CONTAINER" >/dev/null
        exit 1
    fi
}

apply() {
    if [ -n "$(compose_label project)" ]; then
        apply_compose "$1"
    else
        apply_run "$1"
    fi
    echo "Done. Open Claude Science and add the folder from $MOUNTS_DIR."
}

cmd_add() {
    local src="" rw=false name=""
    while [ $# -gt 0 ]; do
        case "$1" in
            --rw) rw=true ;;
            --name) shift; name=${1:-} ;;
            -h|--help) usage ;;
            -*) die "unknown option: $1" ;;
            *) [ -z "$src" ] || die "one folder at a time"; src=$1 ;;
        esac
        shift
    done
    [ -n "$src" ] || usage 1
    [ -d "$src" ] || die "not a folder: $src"
    src=$(cd "$src" && pwd -P)
    name=${name:-$(basename "$src")}
    name=$(printf '%s' "$name" | tr -c 'A-Za-z0-9._-' '-' | sed 's/^-*//; s/-*$//')
    [ -n "$name" ] || die "could not derive a name; pass --name NAME"
    need_container

    desired=$(mktemp)
    extra_mounts > "$desired"
    if awk -F'|' -v d="$MOUNTS_DIR/$name" '$2 == d {found=1} END {exit !found}' "$desired"; then
        die "a folder named '$name' is already attached - pick another with --name"
    fi
    echo "$src|$MOUNTS_DIR/$name|$rw" >> "$desired"
    apply "$desired"
    echo "  $src  ->  $MOUNTS_DIR/$name ($([ "$rw" = true ] && echo read-write || echo read-only))"
}

cmd_remove() {
    [ $# -eq 1 ] || usage 1
    need_container
    local key=$1 abs=""
    if [ -d "$key" ]; then abs=$(cd "$key" && pwd -P); fi
    desired=$(mktemp)
    extra_mounts | awk -F'|' -v n="$MOUNTS_DIR/$key" -v s="$abs" '$2 != n && $1 != s' > "$desired"
    if [ "$(extra_mounts | wc -l)" -eq "$(wc -l < "$desired")" ]; then
        die "no attached folder matches '$key' (see: $0 list)"
    fi
    apply "$desired"
}

case "${1:-}" in
    list|ls) shift; cmd_list "$@" ;;
    add) shift; cmd_add "$@" ;;
    remove|rm) shift; cmd_remove "$@" ;;
    -h|--help|help) usage ;;
    *) usage 1 ;;
esac
