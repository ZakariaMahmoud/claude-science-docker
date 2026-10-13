# Claude Science Docker

[![Docker Hub](https://img.shields.io/docker/pulls/zmahmoud/claude-science-docker?logo=docker&label=Docker%20Hub%20pulls)](https://hub.docker.com/r/zmahmoud/claude-science-docker)
[![Image size](https://img.shields.io/docker/image-size/zmahmoud/claude-science-docker/latest?logo=docker)](https://hub.docker.com/r/zmahmoud/claude-science-docker)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Run [Claude Science](https://claude.com/product/claude-science) in Docker. **No cloning, no terminal login, one command.**

Claude Science is Anthropic's AI workbench for research. It normally installs only on Mac and Linux. This project puts it in a Docker container so you can run it anywhere Docker runs, including Windows and home servers, and keep all your data safe in one place.

The image is on Docker Hub: **[`zmahmoud/claude-science-docker`](https://hub.docker.com/r/zmahmoud/claude-science-docker)**.

## What you need

1. **Docker** installed. Get [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac) or Docker Engine (Linux).
2. A **Claude account** on a Pro, Max, Team, or Enterprise plan.

That is it. You do **not** need to download this project.

## Option 1: Docker Hub (recommended, no download)

**Step 1.** Make a folder for your files (this is where you will put your data for Claude):

```bash
mkdir -p ~/ClaudeScience
```

**Step 2.** Run this one command (copy the whole thing):

```bash
docker run -d --name claude-science \
  -p 127.0.0.1:8000:8000 \
  -p 127.0.0.1:8001:8001 \
  -v claude-science-data:/data \
  -v "$HOME/ClaudeScience:/home/claude/ClaudeScience" \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --restart unless-stopped \
  zmahmoud/claude-science-docker:latest
```

On **Windows**, use PowerShell and run it on one line:

```powershell
mkdir -Force "$HOME\ClaudeScience"; docker run -d --name claude-science -p 127.0.0.1:8000:8000 -p 127.0.0.1:8001:8001 -v claude-science-data:/data -v "$HOME\ClaudeScience:/home/claude/ClaudeScience" --security-opt seccomp=unconfined --security-opt apparmor=unconfined --security-opt systempaths=unconfined --restart unless-stopped zmahmoud/claude-science-docker:latest
```

**Step 3.** Open **http://localhost:8000** in your browser.

**Step 4.** The first time only, click **Sign in on the web** and log in with your Claude account. That is it.

The very first start takes a few minutes while it sets itself up; you may see a short "Starting up" page until it is ready.

> A small proxy built into the image handles the app's own sign-in for you. Whenever the app needs a login link (after a restart, an update, or the one-time restart right after you connect your Claude account), the proxy quietly gets a fresh one and signs you in, so you never see the app's "Sign in" or "expired" page. No cloning, no copy-pasting links.

## Option 2: with the project files (optional)

If you want the compose file, scripts, and docs on your machine:

```bash
git clone https://github.com/ZakariaMahmoud/claude-science-docker.git
cd claude-science-docker
docker compose up -d
```

Then open http://localhost:8000, the same as above. `make up` also works.

## Using your own files

**The easy way: your `ClaudeScience` folder.** Everything you put in the `ClaudeScience` folder in your home folder shows up inside Claude Science, and anything Claude saves there appears on your computer.

1. Copy or move a project into it, e.g. `~/ClaudeScience/my-study/`.
2. In Claude Science, click **+** in the message box, then **Your files**, then **Grant folder…**
3. Open `ClaudeScience`, pick `my-study`, choose **Read-only** or **Read & write**, and click **Grant this folder**.

Grant a sub-folder like `my-study`, not `ClaudeScience` itself: then each project only sees its own files.

**Small files?** Click **+** and then **Attach files** to upload them straight from your browser. No setup needed.

**Data that lives somewhere else** (a big dataset on another disk, a network drive) and that you don't want to copy: attach the folder with the helper script. It works with both `docker run` and `docker compose` containers:

```bash
./scripts/folders.sh add /mnt/sequencer-output          # read-only (safe default)
./scripts/folders.sh add ~/results --rw                  # let Claude write there too
./scripts/folders.sh list                                # what is attached
./scripts/folders.sh remove sequencer-output             # detach it again
```

The folder then appears in **Grant folder…** under `mounts/`. Docker can't add a folder to a running container, so the script recreates it with the same settings plus the new folder; your login and projects are kept. (Didn't clone the project? Download just the script: `curl -fsSLO https://raw.githubusercontent.com/ZakariaMahmoud/claude-science-docker/main/scripts/folders.sh && chmod +x folders.sh`. On Windows, run it from Git Bash or WSL.)

> **Linux only:** the container runs as user id 1000. If Claude can't read or write a folder, the container log tells you (`docker logs claude-science`); fix it with `sudo chown -R 1000:1000 <folder>`. Mac and Windows need nothing.

## Everyday commands

| What you want | Command |
| --- | --- |
| Open it | Go to **http://localhost:8000** (sign-in is automatic) |
| See what it is doing | `docker logs -f claude-science` |
| Stop it | `docker stop claude-science` |
| Start it again | `docker start claude-science` |
| Update to the newest version | `docker pull zmahmoud/claude-science-docker:latest` then recreate |

You never have to deal with login links. If a session ever expires, the built-in proxy signs you back in automatically the next time you load the page. Your container keeps running the whole time.

## Your data is safe

Everything you do (your login, your projects, your work) is saved in a Docker volume called `claude-science-data`. It stays safe when you:

- restart the container
- rebuild or update the image
- run `docker compose down`

It is only deleted if you remove the volume on purpose (`docker volume rm claude-science-data`). If you cloned the project you can also make your own backup file any time with `./scripts/backup.sh`.

## A port is already in use?

The app uses two ports: 8000 (main app) and 8001 (previews). If one is taken, here is how to change it.

**Previews (8001).** Change **both** numbers on the `-p` line **and** add a matching `-e CLAUDE_SCIENCE_SANDBOX_PORT` line, e.g. `-p 127.0.0.1:9001:9001` with `-e CLAUDE_SCIENCE_SANDBOX_PORT=9001`. (The app tells your browser to load previews from that exact port, so both sides must match.)

**The main app port (8000).** Change **both** numbers on the `-p` line **and** add a matching `-e CLAUDE_SCIENCE_PORT` line, so the built-in proxy listens where you publish it. For example, to use 9000:

```bash
docker run -d --name claude-science \
  -e CLAUDE_SCIENCE_PORT=9000 \
  -p 127.0.0.1:9000:9000 \
  -p 127.0.0.1:8001:8001 \
  -v claude-science-data:/data \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --restart unless-stopped \
  zmahmoud/claude-science-docker:latest
```

Then open http://localhost:9000. See [.env.example](.env.example) for every setting you can change.

## Want to run it on a server or share it?

Read these guides in the [docs](docs/) folder:

- [docs/configuration.md](docs/configuration.md): every setting explained
- [docs/security.md](docs/security.md): safe remote access and how the sandbox works
- [docs/scaling.md](docs/scaling.md): run it for a whole team, backups, upgrades
- [docs/troubleshooting.md](docs/troubleshooting.md): fixes for common problems

Ready-made reverse proxy setups live in [deploy/](deploy/).

## How it works, in short

- It downloads the official Claude Science program from Anthropic when the image is built. The program is never copied into this project.
- When the app restarts itself (for example right after you connect your Claude account), the container keeps running and follows the new process.
- It runs as a normal user (not root) inside the container.
- It keeps your data in the `/data` volume, and shows your `ClaudeScience` folder (plus any folders you add) to the app.
- It uses port 8000 for the app and 8001 for previews.
- A small proxy (Caddy) sits in front of the app. When the app would show its "Sign in" or "session expired" page, the proxy quietly fetches a fresh sign-in and sends you back in, so you never see it.
- It downloads the program from the same release channel as Anthropic's official installer and checks it against the release's published sha256 checksum.

## Publish your own image (optional)

If you want your own copy on Docker Hub:

1. Put this project on GitHub.
2. Make a [Docker Hub token](https://hub.docker.com/settings/security).
3. In your GitHub repo settings, add two secrets: `DOCKERHUB_USERNAME` and `DOCKERHUB_TOKEN`.
4. Push to the `main` branch. GitHub builds and uploads the image for you, and rebuilds it every week so it stays up to date.

## Note

This is a community project. It is not made by Anthropic and is not official. The Claude Science program belongs to Anthropic and follows [Anthropic's terms](https://claude.com/legal/consumer-terms). "Claude" is a trademark of Anthropic.



## License

This packaging is [MIT licensed](LICENSE). The Claude Science program itself is owned by Anthropic.

### **Created by**

* 🇲🇦 **Mahmoud Zakaria** 
* 🌐 [www.mahmoud.ma](https://www.mahmoud.ma/)

