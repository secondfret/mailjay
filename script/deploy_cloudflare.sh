#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

if ! npx wrangler whoami >/dev/null 2>&1; then
  echo "Wrangler is not logged in. Run: npx wrangler login" >&2
  exit 1
fi

npx wrangler deploy
