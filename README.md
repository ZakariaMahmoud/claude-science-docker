# Claude Science Docker

Run [Claude Science](https://claude.com/product/claude-science) in Docker with one command.

Claude Science is Anthropic's AI workbench for research. It normally installs only on Mac and Linux. This project puts it in a Docker container so you can run it anywhere Docker runs, including Windows and home servers, and keep all your data safe in one place.

## What you need

1. **Docker** installed. Get [Docker Desktop](https://www.docker.com/products/docker-desktop/) (Windows/Mac) or Docker Engine (Linux).
2. A **Claude account** on a Pro, Max, Team, or Enterprise plan.

That is it.

## Setup in 3 steps

**Step 1.** Download this project and open its folder:

```bash
git clone https://github.com/ZakariaMahmoud/claude-science-docker.git
cd claude-science-docker
```

**Step 2.** Start it:

```bash
docker compose up -d
```

The first start takes a few minutes while it sets itself up. That is normal.

**Step 3.** Get your login link and open it in your browser:

```bash
./scripts/login-url.sh
```

Copy the link it prints, paste it in your browser, and sign in with your Claude account. Done.

That is the whole setup. If you want, you can use `make up` instead of steps 2 and 3, and it does both for you.

## Everyday commands

| What you want | Command |
| --- | --- |
| Start it | `docker compose up -d` |
| Get a new login link | `./scripts/login-url.sh` |
| See what it is doing | `docker logs -f claude-science` |
| Stop it | `docker compose down` |
| Save a backup of your data | `./scripts/backup.sh` |

The login link works once and lasts about 3 minutes. If it stops working, just run `./scripts/login-url.sh` again for a new one. Your container keeps running.

## Your data is safe

Everything you do (your login, your projects, your work) is saved in a Docker volume called `claude-science-data`. It stays safe when you:

- restart the container
- rebuild or update the image
- run `docker compose down`

It is only deleted if you run `docker compose down -v` on purpose. You can also make your own backup file any time with `./scripts/backup.sh`.

## The port is already in use?

By default the app uses port 8000. If something else on your computer already uses it, pick another one. Create a file named `.env` in the folder with this line:

```
CLAUDE_SCIENCE_PORT=8100
```

Then run `docker compose up -d` again. See [.env.example](.env.example) for every setting you can change.

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
- It uses port 8000 for the app and port 8001 for previews.

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
