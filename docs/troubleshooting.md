# Troubleshooting

## First stop: what does the daemon think?

```bash
docker logs -f claude-science                           # container = daemon stdout
docker exec claude-science claude-science status        # daemon status as JSON
docker exec claude-science claude-science logs --tail   # daemon's own log file
docker inspect --format '{{.State.Health.Status}}' claude-science
```

## Common issues

**The login link 404s or times out right after start.**
First launch downloads and sets up the analysis runtime, which takes a few
minutes. Watch `docker logs -f claude-science` until it settles; the
healthcheck allows 5 minutes before flagging the container unhealthy.

**"Login link expired."**
Links are single-use and live ~3 minutes. Mint a fresh one:
`scripts/login-url.sh` (or `docker exec claude-science claude-science url`).

**Login page loads but sign-in fails.**
You need a claude.ai account on Pro, Max, Team, or Enterprise; Team and
Enterprise additionally require an admin to enable Claude Science for the
workspace.

**Daemon crash-loops with "Sandbox unavailable: bwrap ...".**
The daemon sandboxes analyses with bubblewrap, which needs user namespaces -
blocked by Docker's default seccomp/AppArmor/masked-path profiles. The
compose file already relaxes them (`seccomp=unconfined`,
`apparmor=unconfined`, `systempaths=unconfined`); if you run plain
`docker run`, add all three `--security-opt` flags (see the README) or set
`CLAUDE_SCIENCE_DISABLE_SANDBOX=true` instead. Trade-offs in
[security.md](security.md#2-the-daemons-internal-sandbox).

**Warning about the data dir being on ephemeral storage.**
The `/data` volume isn't mounted, so state will die with the container. Add
`-v claude-science-data:/data` (docker run) or use the compose file, which
always mounts it.

**My projects disappeared after recreating the container.**
Same cause as above - the container ran without the volume, or with a
different one. Check `docker volume ls` for `claude-science-data` and
inspect what's inside:
`docker run --rm -v claude-science-data:/data alpine ls -la /data`.
If you have archives from `scripts/backup.sh`, restore the newest.

**WebSocket errors behind a reverse proxy.**
Two usual suspects: the proxy isn't forwarding `Upgrade`/`Connection`
headers (see [deploy/nginx](../deploy/nginx/claude-science.conf)), or the
daemon's CSRF gate is rejecting the proxy's Origin - set
`CLAUDE_SCIENCE_ALLOW_ORIGINS=https://your-hostname`.

**Container is `unhealthy`.**
The healthcheck just asks whether anything answers HTTP on the UI port.
`docker exec claude-science claude-science status` tells you if the daemon
is alive; if it is but on the wrong port, check you didn't set
`CLAUDE_SCIENCE_PORT` without re-publishing the matching port.

**Port already in use on the host.**
Set `CLAUDE_SCIENCE_PORT`/`CLAUDE_SCIENCE_SANDBOX_PORT` in `.env` (they only
change the host side of the mapping in the compose file).

**Slow on Apple Silicon / ARM servers.**
Anthropic only ships a linux-x64 binary, so ARM hosts run it under QEMU
emulation. On Macs, prefer the native macOS app; this image targets x86-64
Linux servers.

## Still stuck?

Open an issue with the output of:

```bash
docker exec claude-science claude-science status
docker logs --tail 100 claude-science
docker version --format '{{.Server.Version}}'
```
