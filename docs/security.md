# Security model

Three independent layers protect your account and data. Understand what each
one does before loosening any of them.

## 1. Docker port publishing - the network boundary

The compose file publishes ports on `127.0.0.1` only. The web UI is a
login-gated app with access to your Claude account, your projects, and every
mounted dataset - **never publish it raw on `0.0.0.0`**.

Login links (from `claude-science url`) are single-use and expire after
about 3 minutes, but the session they create is long-lived; treat the UI
port like an SSH port, not like a public website.

The launcher page (port 8080) mints one of those login links on request, so
it shares the exact same trust boundary as the UI: anyone who can reach it
can start a signed-in session. It is published on `127.0.0.1` only for the
same reason. Do not expose it to a network. If you front the app with a
reverse proxy for remote access, proxy the UI (and put your own
authentication in front), not the launcher; set `CLAUDE_SCIENCE_LAUNCHER=false`
to switch the launcher off entirely on shared or exposed hosts.

## 2. The daemon's internal sandbox

By default the daemon confines what Claude can read, write, and reach on the
network, using [bubblewrap](https://github.com/containers/bubblewrap) (user
namespaces). Every new host file or outbound network host produces an
"approval card" in the UI (*Customize → Permissions*).

Docker's **default seccomp/AppArmor profiles block user-namespace creation**,
so out of the box you must pick one of two modes:

**Mode A - keep Claude's sandbox (compose default).** `compose.yaml` sets
`seccomp=unconfined`, `apparmor=unconfined` and `systempaths=unconfined` on
the container (bubblewrap needs to create user namespaces and mount a fresh
`/proc`, which the default profiles and masked paths block). You trade
Docker's generic syscall filter for the daemon's purpose-built analysis
sandbox and its approval cards. For a workload whose whole point is running
AI-generated code, the daemon's sandbox is the more meaningful layer - this
is the recommended mode.

**Mode B - hardened container, no internal sandbox.** Remove the
`security_opt` lines and set `CLAUDE_SCIENCE_DISABLE_SANDBOX=true`
(passes `--dangerously-no-sandbox`). Docker's default profiles stay fully
enabled, but analyses run with free rein *inside* the container, so the
container is the only isolation boundary:

- Mount datasets read-only (`:ro`).
- Don't mount anything you wouldn't hand to the analysis wholesale.
- Keep the resource limits in `compose.yaml` enabled.

Don't combine both relaxations - disabling the internal sandbox *and*
unconfining the container gives up both layers at once.

## 3. Approval prompts

Independent of the sandbox, individual actions (code execution, file access,
network, tools) prompt for approval in the UI.
`CLAUDE_SCIENCE_SKIP_APPROVALS=true` (`--dangerously-skip-approvals`)
removes every check between Claude and your files/network. Reserve it for
throwaway, fully-isolated experiments on data and prompts you wrote
yourself - prompt-injected text in a dataset could otherwise act with your
permissions, silently.

## Remote access

**Preferred: SSH tunnel.** Nothing is exposed, no TLS to manage, login
links work as-is:

```bash
ssh -L 8000:127.0.0.1:8000 -L 8001:127.0.0.1:8001 user@server
# on the server:
docker exec claude-science claude-science url
# open the printed link on your local machine
```

**Alternative: TLS reverse proxy.** Ready-made configs in
[deploy/caddy](../deploy/caddy/Caddyfile) and
[deploy/nginx](../deploy/nginx/claude-science.conf). Two rules:

1. Set `CLAUDE_SCIENCE_ALLOW_ORIGINS=https://your-hostname` so the daemon's
   CSRF gate accepts WebSocket upgrades from the proxy's Origin.
2. Publish the sandbox port (8001) on a **separate hostname**, never a
   sub-path of the UI host - it is a different origin by design, so a
   Claude-generated HTML preview can never read your session.

Use `CLAUDE_SCIENCE_BASE_PATH` if the UI must live under a sub-path
(e.g. `https://lab.example.com/science`).

## Container hardening

The image already runs as a non-root user (uid 1000) with self-update
disabled. Avoid `--privileged` and don't mount the Docker socket; nothing in
this stack needs either. If you run Mode B (hardened container), you can
additionally set `no-new-privileges:true` in `security_opt`.
