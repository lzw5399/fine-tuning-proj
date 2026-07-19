CONFIG ?= configs/sft.yaml

.PHONY: help validate build up down logs ps train train-sft train-dpo

help:
	@printf '%s\n' \
	  'make validate                    Validate repository configuration' \
	  'make build                       Build the pinned LLaMA-Factory image' \
	  'make up                          Start the LLaMA-Factory WebUI' \
	  'make down                        Stop this Compose project' \
	  'make logs                        Follow WebUI logs' \
	  'make ps                          Show Compose service status' \
	  'make train                       Run CONFIG (defaults to configs/sft.yaml)' \
	  'make train-sft                   Run configs/sft.yaml explicitly' \
	  'make train-dpo                   Run configs/dpo.yaml explicitly' \
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

train:
	@./scripts/train.sh "$(CONFIG)"

train-sft:
	@./scripts/train.sh configs/sft.yaml

train-dpo:
	@./scripts/train.sh configs/dpo.yaml
