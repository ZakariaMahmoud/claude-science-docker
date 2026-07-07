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
FROM ${BASE_IMAGE} AS download

# Override to pin a specific build, e.g.
#   --build-arg CLAUDE_SCIENCE_URL=https://downloads.claude.ai/claude-science/<version>/linux-x64
ARG CLAUDE_SCIENCE_URL=https://downloads.claude.ai/claude-science/latest/linux-x64

# Fail a piped RUN if any stage of the pipe fails (needed for the ELF check).
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# Versions are intentionally unpinned: this image tracks the moving upstream
# "latest" binary, so reproducibility comes from the binary URL, not apt pins.
# hadolint ignore=DL3008
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

# The magic-byte check fails the build early if the CDN returned an error page
# instead of an ELF executable.
RUN curl -fSL --retry 3 --retry-delay 5 "${CLAUDE_SCIENCE_URL}" -o /claude-science \
    && chmod 0755 /claude-science \
    && head -c 4 /claude-science | LC_ALL=C grep -q 'ELF' \
    && /claude-science --version

# --- Stage 2: runtime ---------------------------------------------------------
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
        socat \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 --user-group claude \
    && mkdir -p /data \
    && chown claude:claude /data \
    # Point the default data dir at the volume so every CLI command
    # (url, status, logs, stop) works without extra flags.
    && ln -s /data /home/claude/.claude-science

# Build context is the repository root: docker build -f docker/Dockerfile .
COPY --from=download /claude-science /usr/local/bin/claude-science
COPY --chmod=0755 docker/entrypoint.sh /usr/local/bin/entrypoint.sh
COPY --chmod=0755 docker/launcher.sh /usr/local/bin/launcher.sh

USER claude
WORKDIR /home/claude

ENV CLAUDE_SCIENCE_HOST=0.0.0.0 \
    CLAUDE_SCIENCE_PORT=8000 \
    CLAUDE_SCIENCE_SANDBOX_PORT=8001 \
    CLAUDE_SCIENCE_LAUNCHER_PORT=8080 \
    CLAUDE_SCIENCE_DATA_DIR=/data

# 8000 = web UI, 8001 = isolated sandbox port for Claude-generated HTML previews,
# 8080 = one-click launcher page (open this one first).
EXPOSE 8000 8001 8080

VOLUME ["/data"]

# Any HTTP response means the daemon is alive (login-gated routes may answer
# 4xx, so -f is deliberately not used). First launch downloads the analysis
# runtime, hence the generous start period.
HEALTHCHECK --interval=30s --timeout=5s --start-period=300s --retries=3 \
    CMD curl -s -o /dev/null "http://127.0.0.1:${CLAUDE_SCIENCE_PORT}/" || exit 1

ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
