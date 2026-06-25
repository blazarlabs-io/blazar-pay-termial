#!/usr/bin/env bash
cd "$(dirname "$0")"
set -a
[ -f .env ] && . ./.env
set +a
exec npx nodemon src/index.js
