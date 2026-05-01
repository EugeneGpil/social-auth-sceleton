#!/bin/bash
set -e

GREEN='\033[0;32m'
NC='\033[0m'

echo ""
echo "=============================="
echo "  Forest App — Project Setup  "
echo "=============================="
echo ""

# Check Docker
if ! docker info > /dev/null 2>&1; then
    echo "Docker is not running. Please start Docker first."
    exit 1
fi

# Root .env
if [ ! -f .env ]; then
    cp .env.example .env
    echo -e "${GREEN}Created .env from .env.example${NC}"
fi

# Build images
echo "Building Docker images..."
docker compose build

# Start postgres first
docker compose up -d postgres
echo "Waiting for PostgreSQL to be ready..."
until docker compose exec postgres pg_isready -U forest > /dev/null 2>&1; do
    sleep 1
done
echo -e "${GREEN}PostgreSQL ready.${NC}"

# Configure back/.env
if [ ! -f back/.env ]; then
    cp back/.env.example back/.env
fi

configure_env() {
    local file="back/.env"
    sed -i "s|^APP_URL=.*|APP_URL=http://localhost:8000|" "$file"
    sed -i "s|^DB_CONNECTION=.*|DB_CONNECTION=pgsql|" "$file"
    sed -i "s|^# DB_HOST=.*|DB_HOST=postgres|" "$file"
    sed -i "s|^DB_HOST=.*|DB_HOST=postgres|" "$file"
    sed -i "s|^# DB_PORT=.*|DB_PORT=5432|" "$file"
    sed -i "s|^DB_PORT=.*|DB_PORT=5432|" "$file"
    sed -i "s|^# DB_DATABASE=.*|DB_DATABASE=forest|" "$file"
    sed -i "s|^DB_DATABASE=.*|DB_DATABASE=forest|" "$file"
    sed -i "s|^# DB_USERNAME=.*|DB_USERNAME=forest|" "$file"
    sed -i "s|^DB_USERNAME=.*|DB_USERNAME=forest|" "$file"
    sed -i "s|^# DB_PASSWORD=.*|DB_PASSWORD=secret|" "$file"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=secret|" "$file"
    sed -i "s|^MAIL_MAILER=.*|MAIL_MAILER=smtp|" "$file"
    sed -i "s|^MAIL_HOST=.*|MAIL_HOST=mailpit|" "$file"
    sed -i "s|^MAIL_PORT=.*|MAIL_PORT=1025|" "$file"
    sed -i "s|^QUEUE_CONNECTION=.*|QUEUE_CONNECTION=database|" "$file"
    sed -i "s|^SESSION_DRIVER=.*|SESSION_DRIVER=database|" "$file"
}

configure_env
echo -e "${GREEN}back/.env configured.${NC}"

# Generate app key if not set
docker compose run --rm --no-deps php php artisan key:generate --no-interaction

# Start all services and run migrations
docker compose up -d
echo "Running migrations..."
docker compose exec php php artisan migrate

echo ""
echo -e "${GREEN}=============================="
echo "  Setup complete!"
echo "==============================${NC}"
echo ""