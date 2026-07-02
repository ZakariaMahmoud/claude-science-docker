#!/bin/sh
# Entrypoint for the Claude Science container.
#
# No arguments        -> start the daemon in the foreground (container's PID 1).
# With arguments      -> run any claude-science subcommand, e.g.:
#                          docker exec claude-science claude-science url
#                          docker run --rm ... image status
set -eu

if [ "$#" -gt 0 ]; then
    exec claude-science "$@"
fi

PORT="${CLAUDE_SCIENCE_PORT:-8000}"
HOST="${CLAUDE_SCIENCE_HOST:-0.0.0.0}"
SANDBOX_PORT="${CLAUDE_SCIENCE_SANDBOX_PORT:-$((PORT + 1))}"
DATA_DIR="${CLAUDE_SCIENCE_DATA_DIR:-/data}"

# --allow-ephemeral-data-dir: a container rootfs is always overlayfs, which the
# daemon refuses by default. Persistence is the volume's job - mount /data.
set -- serve \
    --host "$HOST" \
    --port "$PORT" \
    --sandbox-port "$SANDBOX_PORT" \
    --data-dir "$DATA_DIR" \
    --no-browser \
    --allow-ephemeral-data-dir

# Self-update is off by default: containers should be updated by pulling a new
# image, not by mutating a running one.
if [ "${CLAUDE_SCIENCE_AUTO_UPDATE:-false}" != "true" ]; then
    set -- "$@" --no-auto-update
fi

# Serve under a URL prefix behind a reverse proxy, e.g. "/science".
if [ -n "${CLAUDE_SCIENCE_BASE_PATH:-}" ]; then
    set -- "$@" --base-path "$CLAUDE_SCIENCE_BASE_PATH"
fi

# Space-separated list of extra Origins allowed through the CSRF gate,
# e.g. "https://science.example.com".
for origin in ${CLAUDE_SCIENCE_ALLOW_ORIGINS:-}; do
    set -- "$@" --allow-origin "$origin"
done

# The daemon sandboxes Claude's file/network access by default. Its isolation
# primitives may be unavailable inside a container; set to "true" only because
# the container itself is your isolation boundary.
if [ "${CLAUDE_SCIENCE_DISABLE_SANDBOX:-false}" = "true" ]; then
    set -- "$@" --dangerously-no-sandbox
fi

# Auto-approves every permission prompt (code execution, network, files).
# Never enable this on data or prompts you did not write yourself.
if [ "${CLAUDE_SCIENCE_SKIP_APPROVALS:-false}" = "true" ]; then
    set -- "$@" --dangerously-skip-approvals
fi

# Escape hatch for flags this script doesn't model (word-split on purpose).
if [ -n "${CLAUDE_SCIENCE_EXTRA_ARGS:-}" ]; then
    # shellcheck disable=SC2086 # deliberate word-splitting into separate args
    set -- "$@" ${CLAUDE_SCIENCE_EXTRA_ARGS}
fi

echo "Starting: claude-science $*"
echo "Once running, get a login link with:  docker exec <container> claude-science url"

# --- Supervisor loop ---------------------------------------------------------
# The daemon restarts *itself* on certain events - most notably the first time
# you sign in, when the active org changes (it exits 0 via SIGTERM to reload).
# If we `exec` it as PID 1, that self-restart takes the whole container down
# and breaks the in-flight login ("session has expired"). Instead we supervise:
# relaunch on a clean exit, forward stop signals so `docker stop` is instant,
# and give up only after repeated genuine failures so Docker can surface them.
shutdown=""
child=""
term() {
    shutdown=1
    [ -n "$child" ] && kill -TERM "$child" 2>/dev/null || true
}
trap term TERM INT

fails=0
while :; do
    claude-science "$@" &
    child=$!

    rc=0
    wait "$child" || rc=$?

    if [ -n "$shutdown" ]; then
        exit 0
    fi

    if [ "$rc" -eq 0 ]; then
        echo "[entrypoint] daemon exited cleanly (self-restart) - relaunching"
        fails=0
        continue
    fi

    fails=$((fails + 1))
    echo "[entrypoint] daemon exited with code $rc (consecutive failure #$fails)"
    if [ "$fails" -ge 5 ]; then
        echo "[entrypoint] giving up after $fails failures so Docker can surface it"
        exit "$rc"
    fi
    sleep 2
done
