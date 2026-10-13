#!/usr/bin/env bash
# Escribe las despensas estándar (tool/standard_baskets.mjs) en la collection
# standardBaskets de la Firestore REAL (bank-storage-bamx).
#
# Uso:
#   ./scripts/seed_standard_baskets.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Esto ESCRIBE despensas en standardBaskets/ del proyecto REAL bank-storage-bamx."
read -r -p "Escribe SI para continuar: " confirm
if [[ "$confirm" != "SI" ]]; then
  echo "Cancelado."
  exit 1
fi

node "$ROOT/tool/seed_standard_baskets.mjs"
