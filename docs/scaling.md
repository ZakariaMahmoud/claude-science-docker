# Scaling & operations

Claude Science is a **single-user daemon**: one login session, one data
directory, one instance per data-dir. That shapes how you scale it - you
don't replicate one instance behind a load balancer; you run **one isolated
instance per user** and size the host for the sum.

## Multi-user hosts

[deploy/multi-instance/compose.yaml](../deploy/multi-instance/compose.yaml)
runs one container + one volume + one port pair per person:

```bash
docker compose -f deploy/multi-instance/compose.yaml up -d
docker exec claude-science-alice claude-science url   # Alice signs in
docker exec claude-science-bob   claude-science url   # Bob signs in
```

Adding a user is copying a service block and bumping the port. Each instance
is fully isolated - own claude.ai login, own projects, own analysis
environments. Front them with one reverse proxy
(`alice.science.example.com`, `bob.science.example.com`) if you want TLS
hostnames per user.

## Sizing

The daemon itself is light; the load comes from the analyses it runs
(Python/R environments, genomics tooling). Plan roughly:

- **Disk** is the resource that actually grows: analysis environments and
  datasets accumulate in the data volume. Give volumes room and monitor with
  `docker system df -v`.
- **CPU/RAM** scale with concurrent analyses. Enable the per-service
  resource limits in the compose files on shared hosts so one heavy job
  can't starve the others.

## Backups

State is precious (it holds your projects and login). Two supplied scripts
wrap the volume in tar archives:

```bash
scripts/backup.sh                 # → backups/claude-science-data-<stamp>.tar.gz
scripts/restore.sh backups/claude-science-data-20260702-120000.tar.gz
```

`backup.sh` pauses the container during the copy for consistency, then
resumes it. Cron example (daily at 03:15, keep 14 days):

```cron
15 3 * * * cd /opt/claude-science-docker && ./scripts/backup.sh /var/backups/claude-science && find /var/backups/claude-science -name '*.tar.gz' -mtime +14 -delete
```

For multi-instance hosts run it per volume:
`VOLUME=claude-science-data-alice CONTAINER=claude-science-alice scripts/backup.sh`.

## Upgrades

Daemon self-update is disabled in the image; the image itself is the unit of
upgrade. CI rebuilds weekly against Anthropic's `latest` channel and tags
each build with the exact upstream version, so:

```bash
docker compose pull && docker compose up -d   # roll forward
# roll back: set CLAUDE_SCIENCE_IMAGE to a previous version tag and re-up
```

The data volume is untouched by upgrades. Take a backup before major version
jumps anyway - `claude-science import` exists but treat migrations as
one-way.

## Moving to a bigger machine

1. `scripts/backup.sh` on the old host.
2. Copy the archive over; on the new host: clone this repo,
   `docker compose up -d` once (creates the volume), `docker compose down`,
   `scripts/restore.sh <archive>`, `docker compose up -d`.
3. Sessions survive the move; if the login is invalidated, open the launcher
   page (port 8080) or run `docker exec claude-science claude-science url`.
