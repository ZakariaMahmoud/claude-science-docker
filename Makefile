# Set IMAGE to your Docker Hub repository, e.g. `make build IMAGE=yourname/claude-science`
IMAGE     ?= claude-science
TAG       ?= local
CONTAINER ?= claude-science
PORT      ?= 8000

.PHONY: help build up down run url status logs shell stop rm push backup version

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the image
	docker build -f docker/Dockerfile -t $(IMAGE):$(TAG) .

up: ## Start via docker compose (recommended)
	docker compose up -d --build
	@echo "Waiting for the daemon, then printing a login link..."
	@sleep 5 && $(MAKE) --no-print-directory url

down: ## Stop the compose stack (data volume is kept)
	docker compose down

run: ## Run without compose (detached, localhost-only, persistent volume)
	docker run -d --name $(CONTAINER) \
		-p 127.0.0.1:$(PORT):8000 \
		-p 127.0.0.1:$(shell expr $(PORT) + 1):8001 \
		-v claude-science-data:/data \
		--security-opt seccomp=unconfined \
		--security-opt apparmor=unconfined \
		--security-opt systempaths=unconfined \
		--restart unless-stopped \
		$(IMAGE):$(TAG)
	@echo "Waiting for the daemon, then printing a login link..."
	@sleep 5 && $(MAKE) --no-print-directory url

url: ## Print a single-use login link (~3 min validity)
	@./scripts/login-url.sh $(CONTAINER)

status: ## Show daemon status (JSON)
	docker exec $(CONTAINER) claude-science status

logs: ## Tail container logs
	docker logs -f $(CONTAINER)

shell: ## Open a shell inside the container
	docker exec -it $(CONTAINER) sh

stop: ## Stop the container
	docker stop $(CONTAINER)

rm: stop ## Stop and remove the container (volume is kept)
	docker rm $(CONTAINER)

backup: ## Snapshot the data volume to ./backups/
	./scripts/backup.sh

push: build ## Build and push to the registry
	docker push $(IMAGE):$(TAG)

version: ## Print the claude-science version inside the image
	docker run --rm $(IMAGE):$(TAG) --version
