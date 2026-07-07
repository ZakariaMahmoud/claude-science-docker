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
  -p 127.0.0.1:8080:8080 \
  -v claude-science-data:/data \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --restart unless-stopped \
  zmahmoud/claude-science-docker:latest
```

**Step 2.** Open **http://localhost:8080** in your browser and click **Launch Claude Science**.

That is it. The page waits until the app is ready, then signs you in with one click. The very first start takes a few minutes while it sets itself up; the page shows "Starting up" until it is done.

> The one command downloads the ready-made image from Docker Hub, keeps your data in a safe volume, and starts a small welcome page on port 8080 that logs you in. No cloning, no copy-pasting login links.

## Option 2: with the project files (optional)

If you want the compose file, scripts, and docs on your machine:

```bash
git clone https://github.com/ZakariaMahmoud/claude-science-docker.git
cd claude-science-docker
docker compose up -d
```

Then open http://localhost:8080 and click Launch, the same as above. `make up` also works.

## Everyday commands

| What you want | Command |
| --- | --- |
| Sign in again | Open **http://localhost:8080** and click Launch |
| See what it is doing | `docker logs -f claude-science` |
| Stop it | `docker stop claude-science` |
| Start it again | `docker start claude-science` |
| Update to the newest version | `docker pull zmahmoud/claude-science-docker:latest` then recreate |

The one-click sign-in link lasts about 3 minutes and works once. If it stops working, just reopen **http://localhost:8080** and click Launch again. Your container keeps running the whole time.

## Your data is safe

Everything you do (your login, your projects, your work) is saved in a Docker volume called `claude-science-data`. It stays safe when you:

- restart the container
- rebuild or update the image
- run `docker compose down`

It is only deleted if you remove the volume on purpose (`docker volume rm claude-science-data`). If you cloned the project you can also make your own backup file any time with `./scripts/backup.sh`.

## A port is already in use?

The app uses three ports: 8000 (main app), 8001 (previews), and 8080 (the launcher page). If one is taken, here is how to change it.

**The launcher page (8080) or previews (8001).** Just change the left number of that `-p` line. For example, to open the launcher on 9090 instead:

```
-p 127.0.0.1:9090:8080
```

Then open http://localhost:9090.

**The main app port (8000).** This one needs two changes together, because the sign-in link points at whatever port the app uses inside the container. Change **both** numbers on the `-p` line **and** add a matching `-e CLAUDE_SCIENCE_PORT` line. For example, to use 9000:

```bash
docker run -d --name claude-science \
  -e CLAUDE_SCIENCE_PORT=9000 \
  -p 127.0.0.1:9000:9000 \
  -p 127.0.0.1:8001:8001 \
  -p 127.0.0.1:8080:8080 \
  -v claude-science-data:/data \
  --security-opt seccomp=unconfined \
  --security-opt apparmor=unconfined \
  --security-opt systempaths=unconfined \
  --restart unless-stopped \
  zmahmoud/claude-science-docker:latest
```

You still open the launcher at http://localhost:8080; it sends you to the app on the new port automatically. See [.env.example](.env.example) for every setting you can change.

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
- It uses port 8000 for the app, 8001 for previews, and 8080 for the one-click launcher page you open first.
- The launcher is a tiny built-in page. When you click Launch it asks the app for a fresh sign-in link and sends you straight there.

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

