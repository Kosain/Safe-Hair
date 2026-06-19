#!/usr/bin/env bash
# Vercel build: install Flutter SDK and compile the Safe Hair web app.
set -euo pipefail

FLUTTER_HOME="${FLUTTER_HOME:-/vercel/flutter}"
if [ ! -d "$FLUTTER_HOME" ]; then
  git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_HOME" --depth 1
fi
export PATH="$FLUTTER_HOME/bin:$PATH"

flutter config --no-analytics
flutter precache --web
flutter --version

cd mobile_app
flutter pub get

# Set API_BASE_URL in Vercel → Settings → Environment Variables.
# Point it at your hosted FastAPI backend (e.g. Render/Railway).
# If unset, defaults to this deployment's URL (same-origin /api when proxied).
if [ -z "${API_BASE_URL:-}" ]; then
  if [ -n "${VERCEL_URL:-}" ]; then
    API_BASE_URL="https://${VERCEL_URL}"
  else
    API_BASE_URL="http://localhost:8000"
  fi
fi

echo "Building Safe Hair web with API_BASE_URL=${API_BASE_URL}"
flutter build web --release \
  --dart-define=API_BASE_URL="${API_BASE_URL}" \
  --no-wasm-dry-run
