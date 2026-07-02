#!/bin/sh
# Snapshot the Claude Science data volume to a timestamped tar.gz.
#
# Usage: scripts/backup.sh [backup-dir]           (default: ./backups)
# Env:   VOLUME=claude-science-data  CONTAINER=claude-science
#
# The daemon is paused during the copy (if running) so the snapshot is
# consistent, then resumed.
set -eu

VOLUME="${VOLUME:-claude-science-data}"
CONTAINER="${CONTAINER:-claude-science}"
BACKUP_DIR="${1:-./backups}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ARCHIVE="claude-science-data-${STAMP}.tar.gz"

if ! docker volume inspect "$VOLUME" >/dev/null 2>&1; then
    echo "Volume '$VOLUME' does not exist - nothing to back up." >&2
    exit 1
fi

mkdir -p "$BACKUP_DIR"

RUNNING=false
if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    RUNNING=true
    echo "Pausing $CONTAINER for a consistent snapshot..."
    docker pause "$CONTAINER" >/dev/null
fi

# Resume the daemon on any exit - success, tar failure, or interruption
# (Ctrl-C / SIGTERM) - so an aborted backup never leaves it paused.
resume() {
    if [ "$RUNNING" = true ]; then
        docker unpause "$CONTAINER" >/dev/null 2>&1 || true
        echo "Resumed $CONTAINER."
    fi
}
trap resume EXIT INT TERM

# Exclude transient runtime sockets - they can't be archived (tar warns and
# skips them) and are recreated by the daemon on start.
docker run --rm \
    -v "$VOLUME":/data:ro \
    -v "$(cd "$BACKUP_DIR" && pwd)":/backup \
    alpine:3 \
    tar czf "/backup/${ARCHIVE}" -C /data \
        --exclude='./daemon.sock' \
        --exclude='./sbx-bind-src' \
        --exclude='*.sock' \
        .

echo "Backup written: ${BACKUP_DIR}/${ARCHIVE}"
