#!/bin/sh
# Print a single-use login link for a running Claude Science container.
# Usage: scripts/login-url.sh [container-name]
set -eu

CONTAINER="${1:-claude-science}"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
    echo "Container '$CONTAINER' is not running." >&2
    echo "Start it first:  docker compose up -d   (or: make run)" >&2
    exit 1
fi

docker exec "$CONTAINER" claude-science url
