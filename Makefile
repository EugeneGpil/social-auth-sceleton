.PHONY: help setup build up down restart logs php node migrate fresh artisan composer \
	capacitor capacitor-shell capacitor-install capacitor-sync capacitor-debug capacitor-check

help:
	@echo ""
	@echo "  make setup      First-time project setup"
	@echo "  make build      Build all services"
	@echo "  make up         Start all services"
	@echo "  make down       Stop all services"
	@echo "  make restart    Restart all services"
	@echo "  make logs       Tail all logs"
	@echo "  make php        Shell into PHP container"
	@echo "  make node       Shell into Node container"
	@echo "  make migrate    Run migrations"
	@echo "  make fresh      Fresh migrate + seed"
	@echo "  make artisan    Run artisan (make artisan CMD='route:list')"
	@echo "  make composer   Run composer (make composer CMD='require ...')"
	@echo ""
	@echo "  Android app (docs/android_capacitor.md):"
	@echo "  make capacitor-install   npm install in src-capacitor (Gradle needs it)"
	@echo "  make capacitor-sync      Copy config + web assets into the Android project"
	@echo "  make capacitor-debug     Build the debug APK to sideload"
	@echo "  make capacitor CMD='...' Run any command in the Capacitor container"
	@echo "  make capacitor-shell     Shell into the Capacitor toolchain container"
	@echo ""

setup:
	@chmod +x setup.sh && ./setup.sh

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

php:
	docker compose exec php bash

node:
	docker compose exec node bash

migrate:
	docker compose exec php php artisan migrate

fresh:
	docker compose exec php php artisan migrate:fresh --seed

artisan:
	docker compose exec php php artisan $(CMD)

composer:
	docker compose exec php composer $(CMD)

# The Android app build — a Capacitor WebView shell around the deployed PWA
# (docs/android_capacitor.md). One-shot `run --rm` in its own container
# (docker/capacitor/Dockerfile), so none of it depends on a JDK or an Android SDK on the host.
#
# `front/src-capacitor` is mounted at /work, so everything below acts on the generated Android
# project in place. Order for a first build from a clean checkout:
#
#   make capacitor-install   # once, and after any dependency change
#   make capacitor-sync      # after any edit to capacitor.config.json
#   make capacitor-debug     # the APK
CAP_RUN = USER_ID=$(shell id -u) GROUP_ID=$(shell id -g) \
	docker compose --profile capacitor run --rm capacitor

CAP_CONFIG = front/src-capacitor/capacitor.config.json

capacitor:
	$(CAP_RUN) $(CMD)

capacitor-shell:
	$(CAP_RUN) bash

# Gradle cannot even configure the project without this: `capacitor.settings.gradle` declares
# the plugin subprojects as directories inside ../node_modules, so a missing install fails at
# settings evaluation with a path error rather than anything mentioning npm.
capacitor-install:
	$(CAP_RUN) npm install
	@echo "Installed. Next: make capacitor-sync"

# `cap sync` copies capacitor.config.json into app/src/main/assets/, which is where the app
# reads `server.url` from at runtime — so an edit to that file does nothing until this runs.
#
# It also copies `webDir` into the APK, and refuses to run when that directory is missing. The
# app loads the deployed site (server.url), so those assets are never rendered; a placeholder is
# enough to keep the copy step happy, and is created rather than assumed because
# src-capacitor/www is gitignored. A real bundle is only needed if server.url is ever dropped
# — that is `quasar build -m capacitor` in the node container.
capacitor-sync: capacitor-check
	$(CAP_RUN) sh -c 'mkdir -p www \
		&& [ -f www/index.html ] || echo "<!doctype html><title>App</title>" > www/index.html; \
		exec npx cap sync android'

# Signs with the Android debug key from docker/volumes/android_home. No secrets needed, and not
# installable on Play.
#
# `sh -c` with an explicit cd rather than a bare `./gradlew`: a relative program name is
# resolved by runc against the container's cwd, and the failure when it cannot be reads like a
# broken image rather than a missing file.
capacitor-debug: capacitor-check
	$(CAP_RUN) sh -c 'cd /work/android && exec ./gradlew --no-daemon assembleDebug'
	@echo "APK: front/src-capacitor/android/app/build/outputs/apk/debug/app-debug.apk"
	@echo "Install: adb install -r front/src-capacitor/android/app/build/outputs/apk/debug/app-debug.apk"

# This skeleton ships placeholders for the two values that cannot be guessed — the app id and
# the URL the app renders. Both produce a *build that succeeds* and an app that is wrong: a
# `com.example.app` APK is refused by Play only at upload time, and an app pointed at
# example.com shows an error page rather than anything about configuration. Hence a warning
# here, at the point where somebody is actually making one.
#
# A warning and not an error: building the placeholder APK is a reasonable thing to do once,
# to check the toolchain works before there is a domain to point it at.
capacitor-check:
	@grep -q 'example\.com\|com\.example\.app' $(CAP_CONFIG) \
		&& echo "" \
		&& echo "  WARNING: $(CAP_CONFIG) still has placeholders." \
		&& echo "  Set appId and server.url for this project — docs/android_capacitor.md section 2." \
		&& echo "" \
		|| true
