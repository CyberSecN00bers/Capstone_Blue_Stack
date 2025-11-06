#!/bin/bash
# Exit immediately if a command exits with a non-zero status
set -e

# Create a directory for logs
mkdir -p /var/log/modsecurity

# Set permissions
chown -R www-data:www-data /var/log/modsecurity
chmod -R 775 /var/log/modsecurity

# Tên network
NETWORK_NAME="capstone-network"

echo "=== [1] Checking Docker network: $NETWORK_NAME ==="
if ! docker network ls --format '{{.Name}}' | grep -q "^${NETWORK_NAME}$"; then
    echo "Network not found. Creating..."
    docker network create "$NETWORK_NAME"
else
    echo "Network already exists."
fi

echo "=== [2] Generating certificates ==="
docker compose -f generate-indexer-certs.yml run --rm generator

echo "=== [3] Starting Docker services ==="
docker compose up -d

echo "=== ✅ All steps completed successfully ==="
