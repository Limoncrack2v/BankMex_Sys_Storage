#!/usr/bin/env bash
# Borra SOLO recipes, mealPlans y consumptionLogs en la Firestore REAL
# (bank-storage-bamx). No toca users, families, members, pantryItems ni deliveries.
#
# Uso:
#   ./scripts/reset_catalog.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Esto BORRA recipes, mealPlans y consumptionLogs en el proyecto REAL bank-storage-bamx."
echo "No toca users ni families."
read -r -p "Escribe SI para continuar: " confirm
if [[ "$confirm" != "SI" ]]; then
  echo "Cancelado."
  exit 1
fi

node "$ROOT/tool/reset_catalog.mjs"
