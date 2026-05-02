.DEFAULT_GOAL := help

.PHONY: help up down restart dev logs backup update setup

help:
	@echo "Self-Hosted Automation Stack"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "  setup     Interactive first-run setup (writes .env, starts stack)"
	@echo "  up        Start the production stack"
	@echo "  down      Stop and remove containers"
	@echo "  restart   Restart all services"
	@echo "  dev       Start in dev mode (direct ports, no Caddy)"
	@echo "  logs      Follow logs for all services"
	@echo "  backup    Back up all volumes to ./backups/"
	@echo "  update    Pull latest images and redeploy"

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
