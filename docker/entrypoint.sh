#!/bin/sh
# Entrypoint for the Claude Science container.
#
# No arguments        -> start the daemon (behind the Caddy proxy) as PID 1.
# With arguments      -> run any claude-science subcommand, e.g.:
#                          docker exec claude-science claude-science url
#                          docker run --rm ... image status
#
# Architecture (all in this one container):
#   browser -> Caddy (public CLAUDE_SCIENCE_PORT)
#              |-- /__cs_auth -> mint server (socat + launcher.sh, internal)
#              `-- everything else -> daemon UI (internal CS_DAEMON_PORT)
#   Caddy turns the daemon's 401 "Sign in" page into an automatic re-login,
#   so users never see it. The sandbox port (previews, a separate origin by
#   design) is forwarded by socat from the container's addresses to the
#   daemon, which binds it on 127.0.0.1 only.
set -eu

if [ "$#" -gt 0 ]; then
    exec claude-science "$@"
fi

PUBLIC_PORT="${CLAUDE_SCIENCE_PORT:-8000}"
HOST="${CLAUDE_SCIENCE_HOST:-0.0.0.0}"
SANDBOX_PORT="${CLAUDE_SCIENCE_SANDBOX_PORT:-$((PUBLIC_PORT + 1))}"
DATA_DIR="${CLAUDE_SCIENCE_DATA_DIR:-/data}"

# Internal ports, not published. Caddy owns the public port, so the daemon UI
# and the mint server live on separate localhost-only ports inside the container.
CS_DAEMON_PORT="${CS_DAEMON_PORT:-47100}"
CS_MINT_PORT="${CS_MINT_PORT:-47101}"
export CLAUDE_SCIENCE_PORT="$PUBLIC_PORT" CS_DAEMON_PORT CS_MINT_PORT

PROXY_ENABLED="${CLAUDE_SCIENCE_PROXY:-true}"
if [ "$PROXY_ENABLED" = "true" ]; then
    DAEMON_UI_PORT="$CS_DAEMON_PORT"
else
    # No proxy: the daemon serves the public port directly (old behaviour).
    DAEMON_UI_PORT="$PUBLIC_PORT"
fi

# --allow-ephemeral-data-dir: a container rootfs is always overlayfs, which the
# daemon refuses by default. Persistence is the volume's job - mount /data.
set -- serve \
    --host "$HOST" \
    --port "$DAEMON_UI_PORT" \
    --sandbox-port "$SANDBOX_PORT" \
    --data-dir "$DATA_DIR" \
    --no-browser \
    --allow-ephemeral-data-dir

# Behind the proxy, Caddy rewrites the browser's Origin to the daemon's own
# address so WebSocket upgrades are accepted (see docker/Caddyfile). No
# --allow-origin is needed here; CLAUDE_SCIENCE_ALLOW_ORIGINS below still
# applies when the proxy is turned off.

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

# --- Your folders -------------------------------------------------------------
# Warn (never fail) when a mounted host folder can't be used by the container
# user (uid 1000) - the usual cause is a Linux host folder owned by another
# user, or one Docker created as root because it did not exist yet.
is_mounted() { grep -q " $1 " /proc/self/mountinfo; }
check_folder() {
    _dir=$1
    is_mounted "$_dir" || return 0
    if ! ls "$_dir" >/dev/null 2>&1; then
        echo "[folders] WARNING: $_dir is mounted but not readable by uid 1000."
        echo "[folders]   Fix on the host:  sudo chown -R 1000:1000 <that folder>"
        return 0
    fi
    # Read-only mounts are fine; a writable mount we can't write to is not.
    if grep " $_dir " /proc/self/mountinfo | awk '{print $6}' | grep -qw rw \
        && [ ! -w "$_dir" ]; then
        echo "[folders] WARNING: $_dir is mounted read-write but uid 1000 cannot write to it,"
        echo "[folders]   so Claude cannot save results there."
        echo "[folders]   Fix on the host:  sudo chown -R 1000:1000 <that folder>"
    fi
}
check_folder /home/claude/ClaudeScience
for _m in /home/claude/mounts/*; do
    [ -d "$_m" ] && check_folder "$_m"
done
if is_mounted /home/claude/ClaudeScience; then
    echo "[folders] Your shared folder is at /home/claude/ClaudeScience"
fi

# --- Proxy + mint server -----------------------------------------------------
# These make expired sessions invisible: Caddy catches the daemon's 401 and
# routes the browser through the mint server to sign back in automatically.
proxy_pid=""
mint_pid=""
if [ "$PROXY_ENABLED" = "true" ]; then
    socat "TCP-LISTEN:${CS_MINT_PORT},reuseaddr,fork,bind=127.0.0.1" EXEC:/usr/local/bin/launcher.sh &
    mint_pid=$!
    # Caddy needs a writable config/data dir; point it at /tmp (we run non-root).
    XDG_CONFIG_HOME=/tmp XDG_DATA_HOME=/tmp \
        caddy run --config /etc/caddy/Caddyfile --adapter caddyfile &
    proxy_pid=$!
    echo "Open Claude Science at http://localhost:${PUBLIC_PORT} (sign-in is automatic)."
else
    echo "Proxy disabled. Get a login link with:  docker exec <container> claude-science url"
fi

# --- Sandbox (preview) port forwarder -----------------------------------------
# Since 0.1.5x the daemon binds the sandbox port to 127.0.0.1 only, whatever
# --host says, so Docker's port publish can't reach it. The daemon keeps that
# loopback socket (it advertises http://localhost:SANDBOX_PORT to the browser,
# so the port number must stay the same); we listen on the same port on the
# container's own addresses and forward to it.
sandbox_pids=""
for ip in $(hostname -I 2>/dev/null); do
    case "$ip" in
        *:*) listen="TCP6-LISTEN:${SANDBOX_PORT},bind=[${ip}]" ;;
        *)   listen="TCP-LISTEN:${SANDBOX_PORT},bind=${ip}" ;;
    esac
    socat "${listen},reuseaddr,fork" "TCP:127.0.0.1:${SANDBOX_PORT}" &
    sandbox_pids="$sandbox_pids $!"
done

echo "Starting: claude-science $*"

# --- Supervisor loop ---------------------------------------------------------
# The daemon restarts *itself* on certain events - most notably the first time
# you sign in, when the active org changes. Since 0.1.5x it does that by
# spawning its own successor, handing the lockfile over and exiting 0; the
# successor is then not our child (tini, PID 1, adopts and reaps it). So after
# a clean exit we look for a live daemon via `claude-science status` and
# supervise that pid instead of launching a duplicate (which would just print
# "daemon already running" and exit 0 in a loop). Stop signals go to whichever
# daemon is current, and we give up only after repeated genuine failures.
shutdown=""
child=""
term() {
    shutdown=1
    # shellcheck disable=SC2086 # sandbox_pids is a space-separated pid list
    for pid in "$child" "$proxy_pid" "$mint_pid" $sandbox_pids; do
        if [ -n "$pid" ]; then
            kill -TERM "$pid" 2>/dev/null || true
        fi
    done
}
trap term TERM INT

# Pid of a live daemon that took over via a self-restart handoff, if any.
successor_pid() {
    _pid=$(claude-science status 2>/dev/null \
        | grep -A1 -E '"running": *true' \
        | sed -nE 's/^ *"pid": *([0-9]+).*/\1/p')
    if [ -n "$_pid" ] && grep -q claude-science "/proc/$_pid/cmdline" 2>/dev/null; then
        echo "$_pid"
    fi
}

fails=0
while :; do
    claude-science "$@" &
    child=$!

    rc=0
    wait "$child" || rc=$?

    # Follow self-restart handoffs: watch each successor until it is gone.
    while [ -z "$shutdown" ] && [ "$rc" -eq 0 ]; do
        next=$(successor_pid)
        [ -n "$next" ] || break
        child=$next
        echo "[entrypoint] daemon handed off to pid $child (self-restart) - supervising it"
        while [ -z "$shutdown" ] && kill -0 "$child" 2>/dev/null; do
            # Backgrounded sleep + wait keeps the TERM trap responsive.
            sleep 2 &
            wait $! || true
        done
    done

    if [ -n "$shutdown" ]; then
        # Give a handed-off daemon (not our child, so `wait` can't) time to
        # shut down cleanly before the container exits.
        i=0
        while [ "$i" -lt 20 ] && kill -0 "$child" 2>/dev/null; do
            sleep 0.5
            i=$((i + 1))
        done
        exit 0
    fi

    if [ "$rc" -eq 0 ]; then
        echo "[entrypoint] daemon exited cleanly - relaunching"
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
