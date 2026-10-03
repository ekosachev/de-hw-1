#!/bin/sh

set -e

LAKEKEEPER_URL="http://de-hw-1-lakekeeper:8181"

echo "Accepting Terms of Use..."

bootstrap_status=$(
  curl -sS -o /dev/null -w "%{http_code}" \
    -X POST \
    "$LAKEKEEPER_URL/management/v1/bootstrap" \
    -H "Content-Type: application/json" \
    -d '{"accept-terms-of-use":true}'
)

case "$bootstrap_status" in
  2*)
    echo "Bootstrap completed."
    ;;
  400)
    echo "Bootstrap already completed."
    ;;
  *)
    echo "Bootstrap failed with HTTP $bootstrap_status"
    exit 1
    ;;
esac

echo "Checking warehouse..."

warehouses=$(
  curl -fsS \
    "$LAKEKEEPER_URL/management/v1/warehouse"
)

if echo "$warehouses" \
  | tr -d '[:space:]' \
  | grep -q '"name":"demo"'; then

  echo "Warehouse 'demo' already exists."
  echo "Lakekeeper initialization complete."
  exit 0
fi

echo "Warehouse 'demo' does not exist. Creating..."

curl -f -X POST \
  "$LAKEKEEPER_URL/management/v1/warehouse" \
  -H "Content-Type: application/json" \
  -d @/create-warehouse.json

echo "Warehouse 'demo' created."
