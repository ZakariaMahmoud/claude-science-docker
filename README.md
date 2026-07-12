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

**Step 1.** Run this one command (copy the whole thing):

```bash
docker run -d --name claude-science \
  -p 127.0.0.1:8000:8000 \
  -p 127.0.0.1:8001:8001 \
  -v claude-science-data:/data \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --restart unless-stopped \
  zmahmoud/claude-science-docker:latest
```

**Step 2.** Open **http://localhost:8000** in your browser.

That is it. Sign-in is automatic. The very first start takes a few minutes while it sets itself up; you will see a short "Starting up" page until it is ready, then it drops you straight into Claude Science.

> A small proxy built into the image handles sign-in for you. Whenever a login is needed (including the one-time restart the first time you connect your Claude account), it quietly gets a fresh session so you never see a login screen or an "expired" page. No cloning, no copy-pasting links.

## Option 2: with the project files (optional)

If you want the compose file, scripts, and docs on your machine:

```bash
git clone https://github.com/ZakariaMahmoud/claude-science-docker.git
cd claude-science-docker
docker compose up -d
```

Then open http://localhost:8000, the same as above. `make up` also works.

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

**Previews (8001).** Just change the left number of that `-p` line, e.g. `-p 127.0.0.1:9001:8001`.

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
- It runs as a normal user (not root) inside the container.
- It keeps your data in the `/data` volume.
- It uses port 8000 for the app and 8001 for previews.
- A small proxy (Caddy) sits in front of the app. When the app would show its "session expired" page, the proxy quietly fetches a fresh sign-in and sends you back in, so you never see it.

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

