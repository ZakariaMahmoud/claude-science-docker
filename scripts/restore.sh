#!/bin/sh
# Restore a backup archive into the Claude Science data volume.
#
# Usage: scripts/restore.sh <backup.tar.gz>
# Env:   VOLUME=claude-science-data  CONTAINER=claude-science
#
# Refuses to run while the container is up, and empties the volume before
# restoring so the result exactly matches the archive.
set -eu

VOLUME="${VOLUME:-claude-science-data}"
CONTAINER="${CONTAINER:-claude-science}"
ARCHIVE="${1:?usage: scripts/restore.sh <backup.tar.gz>}"

if [ ! -f "$ARCHIVE" ]; then
    echo "No such file: $ARCHIVE" >&2
    exit 1
fi

if docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Container '$CONTAINER' is running. Stop it first:" >&2
    echo "  docker compose down   (or: make stop)" >&2
    exit 1
fi

printf 'This ERASES the current contents of volume %s. Continue? [y/N] ' "$VOLUME"
read -r answer
case "$answer" in
    y|Y|yes|YES) ;;
    *) echo "Aborted."; exit 1 ;;
esac

ARCHIVE_DIR="$(cd "$(dirname "$ARCHIVE")" && pwd)"
ARCHIVE_NAME="$(basename "$ARCHIVE")"

docker run --rm \
    -v "$VOLUME":/data \
    -v "$ARCHIVE_DIR":/backup:ro \
    alpine:3 \
    sh -c "rm -rf /data/* /data/..?* /data/.[!.]* 2>/dev/null; tar xzf '/backup/${ARCHIVE_NAME}' -C /data"

echo "Restored ${ARCHIVE_NAME} into ${VOLUME}. Start the stack with: docker compose up -d"
