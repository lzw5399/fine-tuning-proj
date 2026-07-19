CONFIG ?= configs/sft.yaml

.PHONY: help validate build up down logs ps smoke train

help:
	@printf '%s\n' \
	  'make validate                    Validate repository configuration' \
	  'make build                       Build the pinned LLaMA-Factory image' \
	  'make up                          Start the LLaMA-Factory WebUI' \
	  'make down                        Stop this Compose project' \
	  'make logs                        Follow WebUI logs' \
	  'make ps                          Show Compose service status' \
	  'make smoke                       Run the bounded official-data smoke SFT' \
	  'make train                       Run configs/sft.yaml' \
	  'make train CONFIG=configs/x.yaml Run another repository config'

validate:
	@./scripts/validate.sh

build:
	docker compose build llamafactory

up:
	docker compose up -d llamafactory

down:
	docker compose down

logs:
	docker compose logs -f llamafactory

ps:
	docker compose ps

smoke:
	@./scripts/train.sh configs/sft-smoke.yaml

train:
	@./scripts/train.sh "$(CONFIG)"
