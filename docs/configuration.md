# Configuration

All runtime configuration is done with environment variables - set them in
[.env](../.env.example) for Compose, or with `-e` for `docker run`.

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_SCIENCE_PORT` | `8000` | Web UI port inside the container |
| `CLAUDE_SCIENCE_SANDBOX_PORT` | `8001` | Port serving Claude-generated HTML previews (isolated origin so a preview can never read your session) |
| `CLAUDE_SCIENCE_LAUNCHER_PORT` | `8080` | Port for the one-click launcher page (open this one first) |
| `CLAUDE_SCIENCE_LAUNCHER` | `true` | Set to `false` to turn the launcher page off (then get login links with `claude-science url`) |
| `CLAUDE_SCIENCE_HOST` | `0.0.0.0` | Bind address inside the container. Leave as-is - Docker's port publishing is the real network gate |
| `CLAUDE_SCIENCE_DATA_DIR` | `/data` | State directory; mount your volume here |
| `CLAUDE_SCIENCE_AUTO_UPDATE` | `false` | Let the daemon self-update in place. Keep off in containers - pull a new image instead |
| `CLAUDE_SCIENCE_BASE_PATH` | - | Serve under a URL prefix behind a reverse proxy, e.g. `/science` (leading slash, no trailing slash) |
| `CLAUDE_SCIENCE_ALLOW_ORIGINS` | - | Space-separated browser Origins allowed through the daemon's CSRF gate, e.g. `https://science.example.com`. Needed whenever a reverse proxy serves the UI from its own hostname |
| `CLAUDE_SCIENCE_DISABLE_SANDBOX` | `false` | ⚠️ Disable the daemon's internal sandbox - see [security.md](security.md) before touching this |
| `CLAUDE_SCIENCE_SKIP_APPROVALS` | `false` | ⚠️ Auto-approve every permission prompt (code execution, network, files). Never use on data or prompts you did not write |
| `CLAUDE_SCIENCE_EXTRA_ARGS` | - | Extra `claude-science serve` flags, word-split verbatim |

## Build-time arguments

| Arg | Default | Purpose |
|---|---|---|
| `CLAUDE_SCIENCE_URL` | `.../claude-science/latest/linux-x64` | Where the binary is fetched from. Point at a versioned URL to pin a build |
| `BASE_IMAGE` | `debian:bookworm-slim` | Runtime base image |

```bash
docker build -f docker/Dockerfile \
  --build-arg CLAUDE_SCIENCE_URL=https://downloads.claude.ai/claude-science/<version>/linux-x64 \
  -t claude-science:pinned .
```

## Running CLI subcommands

Any argument passed to the container is forwarded to the `claude-science`
CLI; with no arguments the entrypoint starts the daemon:

```bash
docker exec claude-science claude-science url          # single-use login link (~3 min)
docker exec claude-science claude-science status       # daemon status as JSON
docker exec claude-science claude-science logs --tail  # daemon's own logs
docker run --rm claude-science:local --version         # version of the baked binary
```

## Data location & persistence

Everything - login session, projects, analysis environments - lives in
`/data`, which the image symlinks to `~/.claude-science` so the CLI's
defaults work unchanged.

- The compose file uses the named volume `claude-science-data`. It survives
  container restart, recreation, image upgrades and `docker compose down`;
  only an explicit `docker compose down -v` or `docker volume rm` deletes it.
- Prefer a host directory you can see? Replace the volume line with a bind
  mount: `- ./claude-science-data:/data` (the directory must be writable by
  uid 1000).
- Snapshots: [`scripts/backup.sh`](../scripts/backup.sh) and
  [`scripts/restore.sh`](../scripts/restore.sh) - see
  [scaling.md](scaling.md#backups) for a cron example.

## Mounting datasets

Give the workbench your data as extra read-only mounts, kept separate from
the state volume:

```yaml
volumes:
  - claude-science-data:/data
  - ./datasets:/home/claude/datasets:ro
  - /mnt/sequencer-output:/home/claude/sequencer:ro
```
