#!/bin/sh

set -e

echo "Running Superset migrations..."
superset db upgrade

echo "Creating admin user..."
superset fab create-admin \
    --username admin \
    --firstname Egor \
    --lastname Kosachev \
    --email admin@example.com \
    --password admin \
    || true

echo "Initializing Superset"
superset init

echo "Importing Superset objects..."
superset import-dashboards \
    --username admin \
    --path /exports/bronze-dashboard.zip
echo "Superset initialization complete."
