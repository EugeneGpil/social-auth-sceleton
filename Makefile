.PHONY: help setup up down restart logs php migrate fresh artisan composer

help:
	@echo ""
	@echo "  make setup      First-time project setup"
	@echo "  make up         Start all services"
	@echo "  make down       Stop all services"
	@echo "  make restart    Restart all services"
	@echo "  make logs       Tail all logs"
	@echo "  make php        Shell into PHP container"
	@echo "  make migrate    Run migrations"
	@echo "  make fresh      Fresh migrate + seed"
	@echo "  make artisan    Run artisan (make artisan CMD='route:list')"
	@echo "  make composer   Run composer (make composer CMD='require ...')"
	@echo ""

setup:
	@chmod +x setup.sh && ./setup.sh

up:
	docke compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

php:
	docker compose exec php bash

migrate:
	docker compose exec php php artisan migrate

fresh:
	docker compose exec php php artisan migrate:fresh --seed

artisan:
	docker compose exec php php artisan $(CMD)

composer:
	docker compose exec php composer $(CMD)
