# Configuration

All runtime configuration is done with environment variables - set them in
[.env](../.env.example) for Compose, or with `-e` for `docker run`.

| Variable | Default | Purpose |
|---|---|---|
| `CLAUDE_SCIENCE_PORT` | `8000` | Public web UI port (the Caddy proxy listens here; open this in your browser) |
| `CLAUDE_SCIENCE_SANDBOX_PORT` | `8001` | Port serving Claude-generated HTML previews (isolated origin so a preview can never read your session). The daemon tells the browser to load previews from `localhost:<this port>`, so publish it on the **same** host port (`-p 127.0.0.1:9001:9001` with `CLAUDE_SCIENCE_SANDBOX_PORT=9001`) |
| `CLAUDE_SCIENCE_PROXY` | `true` | Front the daemon with the auto sign-in proxy. Set `false` to serve the daemon directly on `CLAUDE_SCIENCE_PORT` (then use `claude-science url` for links) |
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
| `CLAUDE_SCIENCE_RELEASE` | `latest` | Upstream release to bake in: `latest`, or a release id (8 hex chars) to pin a build |
| `CLAUDE_SCIENCE_DIST` | Anthropic's release bucket | Release channel base URL (the same one the official installer uses) |
| `BASE_IMAGE` | `debian:bookworm-slim` | Runtime base image |

The build resolves the release, then verifies the binary against the
release manifest's sha256 - the same check the official installer does. The
build log prints the version and release id (`Claude Science 0.1.60
(8db2454a)`); pass that id to rebuild the exact same binary later:

```bash
docker build -f docker/Dockerfile \
  --build-arg CLAUDE_SCIENCE_RELEASE=8db2454a \
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

## Your files

| Inside the container | Comes from | How |
|---|---|---|
| `/home/claude/ClaudeScience` | `~/ClaudeScience` on the host (`CLAUDE_SCIENCE_FOLDER` in `.env`) | Mounted by default, read-write |
| `/home/claude/mounts/<name>` | Any host folder | `scripts/folders.sh add <folder> [--rw] [--name NAME]` |

The app only lets Claude use folders you grant in the UI (**+** → **Your
files** → **Grant folder…**), so mounting a folder makes it *available*; it
does not hand it to Claude. Grant sub-folders, not the mount points
themselves.

`scripts/folders.sh` recreates the container with the extra bind mounts
(read-only unless `--rw`); the data volume is untouched, so login and
projects survive. For Compose installs it writes a managed
`compose.override.yaml` next to your compose file, which plain
`docker compose up -d` picks up from then on. Run `scripts/folders.sh list`
to see what is attached, `remove <name>` to detach. `make folders`,
`make add-folder DIR=... [RW=1]` and `make remove-folder NAME=...` wrap it.

On Linux, the container user is uid 1000. At startup the entrypoint warns in
`docker logs` if a mounted folder isn't readable (or, for read-write mounts,
writable) by that user; fix it with `sudo chown -R 1000:1000 <folder>`.
