# syntax=docker/dockerfile:1

# -----------------------------------------------------------------------------
# Claude Science - unofficial Docker image
# https://claude.com/product/claude-science
#
# Anthropic ships Claude Science as a single linux-x64 binary. This image wraps
# it for container use: headless serve, persistent data volume, non-root user.
# -----------------------------------------------------------------------------

ARG BASE_IMAGE=debian:bookworm-slim

# --- Stage 1: fetch and verify the binary ------------------------------------
# BASE_IMAGE defaults to the tagged debian:bookworm-slim; hadolint can't see
# through the ARG, so DL3006 (require an explicit tag) is a false positive here.
# hadolint ignore=DL3006
FROM ${BASE_IMAGE} AS download

# Same release channel as Anthropic's official installer
# (https://claude.ai/install-claude-science.sh):
#   <base>/latest                 -> sha8 of the current release
#   <base>/<sha8>/manifest.json   -> {"version", "sha256": {"linux-x64": ...}}
#   <base>/<sha8>/operon-linux-x64 -> the binary
ARG CLAUDE_SCIENCE_DIST=https://storage.googleapis.com/operon-dist-cf94a20e-f71c-413c-bd00-9e12b1fedf59/operon-releases
# "latest" (default) or a release sha8 to pin a build, e.g.
#   --build-arg CLAUDE_SCIENCE_RELEASE=8db2454a
ARG CLAUDE_SCIENCE_RELEASE=latest

# Fail a piped RUN if any stage of the pipe fails.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Versions are intentionally unpinned: this image tracks the moving upstream
# release, so reproducibility comes from CLAUDE_SCIENCE_RELEASE, not apt pins.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl jq \
    && rm -rf /var/lib/apt/lists/*

# Resolve the release, then verify the binary against the manifest's sha256
# (the same integrity check the official installer performs).
RUN dl() { curl -fsS --proto '=https' --tlsv1.2 --retry 3 --retry-all-errors "$@"; } \
    && sha8="${CLAUDE_SCIENCE_RELEASE}" \
    && if [ "$sha8" = "latest" ] || [ "$sha8" = "stable" ]; then sha8="$(dl "${CLAUDE_SCIENCE_DIST}/latest")"; fi \
    && [[ "$sha8" =~ ^[0-9a-f]{8}$ ]] || { echo "bad release pointer: $sha8" >&2; exit 1; } \
    && manifest="$(dl "${CLAUDE_SCIENCE_DIST}/${sha8}/manifest.json")" \
    && checksum="$(jq -r '.sha256["linux-x64"] // empty' <<<"$manifest")" \
    && [[ "$checksum" =~ ^[a-f0-9]{64}$ ]] || { echo "no linux-x64 checksum in manifest" >&2; exit 1; } \
    && echo "Claude Science $(jq -r .version <<<"$manifest") (${sha8})" \
    && dl "${CLAUDE_SCIENCE_DIST}/${sha8}/operon-linux-x64" -o /claude-science \
    && echo "${checksum}  /claude-science" | sha256sum -c - \
    && chmod 0755 /claude-science \
    && /claude-science --version

# --- Stage 2: runtime ---------------------------------------------------------
# hadolint ignore=DL3006
FROM ${BASE_IMAGE}

LABEL org.opencontainers.image.title="Claude Science (unofficial)" \
      org.opencontainers.image.description="Anthropic's Claude Science research workbench, containerized for headless/server use" \
      org.opencontainers.image.url="https://claude.com/product/claude-science" \
      org.opencontainers.image.source="https://github.com/ZakariaMahmoud/claude-science-docker" \
      org.opencontainers.image.licenses="MIT"

# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        bubblewrap \
        ca-certificates \
        curl \
        git \
        procps \
        python3 \
        socat \
        tini \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --user-group claude \
    && mkdir -p /data \
    && chown claude:claude /data \
    # Point the default data dir at the volume so every CLI command
    # (url, status, logs, stop) works without extra flags.
    && ln -s /data /home/claude/.claude-science \
    # Where your own files appear: the shared folder (mounted from the host's
    # ~/ClaudeScience) and extra folders added with scripts/folders.sh.
    && mkdir -p /home/claude/ClaudeScience /home/claude/mounts \
    && chown claude:claude /home/claude/ClaudeScience /home/claude/mounts

# Caddy proxy binary, copied from the official static image (no apt needed).
COPY --from=caddy:2-alpine /usr/bin/caddy /usr/local/bin/caddy

# Build context is the repository root: docker build -f docker/Dockerfile .
COPY --from=download /claude-science /usr/local/bin/claude-science
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 docker/launcher.sh /usr/local/bin/launcher.sh
COPY docker/Caddyfile /etc/caddy/Caddyfile

# hadolint ignore=DL3066
USER claude
WORKDIR /home/claude

ENV CLAUDE_SCIENCE_HOST=0.0.0.0 \
    CLAUDE_SCIENCE_PORT=8000 \
    CLAUDE_SCIENCE_SANDBOX_PORT=8001 \
    CLAUDE_SCIENCE_DATA_DIR=/data

# 8000 = web UI (through the Caddy proxy, sign-in is automatic),
# 8001 = isolated sandbox port for Claude-generated HTML previews.
EXPOSE 8000 8001

VOLUME ["/data"]

# Any HTTP response means the daemon is alive (login-gated routes may answer
# 4xx, so -f is deliberately not used). First launch downloads the analysis
# runtime, hence the generous start period.
# Shell form on purpose: it expands ${CLAUDE_SCIENCE_PORT}.
# hadolint ignore=DL3025
HEALTHCHECK --interval=30s --timeout=5s --start-period=300s --retries=3 \
    CMD curl -s -o /dev/null "http://127.0.0.1:${CLAUDE_SCIENCE_PORT}/" || exit 1

# tini is PID 1: the daemon's self-restart spawns a successor that gets
# reparented to PID 1, and tini reaps it (and forwards signals to the script).
ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/entrypoint.sh"]
