# Set IMAGE to your Docker Hub repository, e.g. `make build IMAGE=yourname/claude-science`
IMAGE     ?= claude-science
TAG       ?= local
CONTAINER ?= claude-science
PORT      ?= 8000

.PHONY: help build up down run url status logs shell stop rm push backup version folders add-folder remove-folder

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-10s\033[0m %s\n", $$1, $$2}'

build: ## Build the image
	docker build -f docker/Dockerfile -t $(IMAGE):$(TAG) .

up: ## Start via docker compose (recommended)
	@mkdir -p "$(HOME)/ClaudeScience"
	docker compose up -d --build
	@echo "Open http://localhost:$${CLAUDE_SCIENCE_PORT:-8000} (sign-in is automatic)"

down: ## Stop the compose stack (data volume is kept)
	docker compose down

run: ## Run without compose (detached, localhost-only, persistent volume)
	@mkdir -p "$(HOME)/ClaudeScience"
	docker run -d --name $(CONTAINER) \
		-e CLAUDE_SCIENCE_PORT=$(PORT) \
		-e CLAUDE_SCIENCE_SANDBOX_PORT=$(shell expr $(PORT) + 1) \
		-p 127.0.0.1:$(PORT):$(PORT) \
		-p 127.0.0.1:$(shell expr $(PORT) + 1):$(shell expr $(PORT) + 1) \
		-v claude-science-data:/data \
		-v "$(HOME)/ClaudeScience:/home/claude/ClaudeScience" \
		--security-opt seccomp=unconfined \
		--security-opt apparmor=unconfined \
		--security-opt systempaths=unconfined \
		--restart unless-stopped \
		$(IMAGE):$(TAG)
	@echo "Open http://localhost:$(PORT) (sign-in is automatic)"

url: ## Print a single-use login link (~3 min validity)
	@docker exec $(CONTAINER) claude-science url

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

folders: ## List the folders Claude Science can see
	./scripts/folders.sh list

add-folder: ## Attach a host folder, e.g. make add-folder DIR=/mnt/data [RW=1]
	./scripts/folders.sh add "$(DIR)" $(if $(RW),--rw)

remove-folder: ## Detach a folder, e.g. make remove-folder NAME=data
	./scripts/folders.sh remove "$(NAME)"
