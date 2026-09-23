#!/usr/bin/env bash
# Escribe recetas en la collection recipes de la Firestore REAL
# (bank-storage-bamx). No crea usuarios, familias ni despensa.
#
# Uso:
#   ./scripts/seed_catalog.sh

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

echo "Esto ESCRIBE recetas en recipes/ del proyecto REAL bank-storage-bamx."
read -r -p "Escribe SI para continuar: " confirm
if [[ "$confirm" != "SI" ]]; then
  echo "Cancelado."
  exit 1
fi

node "$ROOT/tool/seed_catalog.mjs"
