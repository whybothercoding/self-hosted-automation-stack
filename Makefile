.DEFAULT_GOAL := help

.PHONY: help up down restart dev logs backup update setup test restore backup-test security-scan

help:
	@echo "Self-Hosted Automation Stack"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "  setup          Interactive first-run setup (writes .env, starts stack)"
	@echo "  up             Start the production stack"
	@echo "  down           Stop and remove containers"
	@echo "  restart        Restart all services"
	@echo "  dev            Start in dev mode (direct ports, no Caddy)"
	@echo "  logs           Follow logs for all services"
	@echo "  backup         Back up all volumes to ./backups/"
	@echo "  update         Pull latest images and redeploy"
	@echo "  test           Boot the dev stack and verify health endpoints respond"
	@echo "  restore        Restore from a backup: make restore TIMESTAMP=20260823_140000"
	@echo "  backup-test    Full backup -> destroy -> restore -> verify drill (needs a running stack)"
	@echo "  security-scan  Scan the four pinned images with the Trivy CLI (must be installed locally)"

setup:
	bash scripts/setup.sh

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

dev:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up

logs:
	docker compose logs -f

backup:
	bash scripts/backup.sh

update:
	bash scripts/update.sh

test:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d
	bash scripts/wait-for-healthy.sh postgres n8n baserow
	curl -sf http://localhost:5678/healthz && echo "n8n: healthy"
	curl -sf http://localhost:8080/api/_health/ && echo "baserow: healthy"

restore:
	bash scripts/restore.sh $(TIMESTAMP)

backup-test:
	bash scripts/backup-drill.sh

security-scan:
	@for img in n8nio/n8n:2.35.7 baserow/baserow:2.3.3 postgres:15.19-alpine3.24 caddy:2.11.4-alpine; do \
		echo "--- $$img ---"; \
		trivy image --severity CRITICAL,HIGH --ignore-unfixed "$$img"; \
	done
