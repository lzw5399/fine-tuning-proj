CONFIG ?= configs/sft.yaml

.PHONY: help validate training-build webui-up webui-down webui-logs webui-ps \
	build up down logs ps train train-sft train-dpo \
	serve-check serve-up serve-down serve-logs serve-ps serve-models

help:
	@printf '%s\n' \
	  'make validate                    Validate repository configuration' \
	  'make training-build              Build the LLaMA-Factory training image' \
	  'make webui-up                    Start the training WebUI' \
	  'make webui-down                  Stop the training WebUI' \
	  'make webui-logs                  Follow training WebUI logs' \
	  'make webui-ps                    Show training WebUI status' \
	  'make train                       Run CONFIG (defaults to configs/sft.yaml)' \
	  'make train-sft                   Run configs/sft.yaml explicitly' \
	  'make train-dpo                   Run configs/dpo.yaml explicitly' \
	  'make train CONFIG=configs/x.yaml Run another repository config' \
	  'make serve-check                 Validate the configured LoRA Adapter' \
	  'make serve-up                    Validate Adapter and start vLLM' \
	  'make serve-down                  Stop vLLM only' \
	  'make serve-logs                  Follow vLLM logs' \
	  'make serve-ps                    Show vLLM status' \
	  'make serve-models                List models exposed by vLLM'

validate:
	@./scripts/validate.sh

training-build:
	docker compose -p qwen-sft -f compose.train.yaml build llamafactory

webui-up:
	docker compose -p qwen-sft -f compose.train.yaml up -d llamafactory

webui-down:
	docker compose -p qwen-sft -f compose.train.yaml stop llamafactory

webui-logs:
	docker compose -p qwen-sft -f compose.train.yaml logs -f llamafactory

webui-ps:
	docker compose -p qwen-sft -f compose.train.yaml ps llamafactory

build: training-build

up: webui-up

down: webui-down

logs: webui-logs

ps: webui-ps

train:
	@./scripts/train.sh "$(CONFIG)"

train-sft:
	@./scripts/train.sh configs/sft.yaml

train-dpo:
	@./scripts/train.sh configs/dpo.yaml

serve-check:
	@./scripts/serve-vllm.sh check

serve-up:
	@./scripts/serve-vllm.sh up

serve-down:
	@./scripts/serve-vllm.sh down

serve-logs:
	@./scripts/serve-vllm.sh logs

serve-ps:
	@./scripts/serve-vllm.sh ps

serve-models:
	@./scripts/serve-vllm.sh models
