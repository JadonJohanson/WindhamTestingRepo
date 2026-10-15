#!/usr/bin/env bash
# Create the tables and load demo data in the DEVELOPMENT or STAGING database (issue #30).
#
#   scripts/db-setup.sh development
#   scripts/db-setup.sh staging
#
# Reads the connection strings the owner shares privately from .env.environments (git-ignored,
# see issue #28), which must define:
#   DEV_DATABASE_URL_UNPOOLED       STAGING_DATABASE_URL_UNPOOLED
#   SEED_STAFF_PASSWORD             (12+ characters; the demo staff password)
#
# It only accepts "development" or "staging", so it cannot be pointed at production by name,
# and it refuses to run if the chosen database is the same one as production's.
# Both steps are safe to re-run: migrations only apply what is pending and the seed only adds
# what is missing.
set -euo pipefail

cd "$(dirname "$0")/.."

env_name="${1:-}"
case "$env_name" in
  development) var="DEV_DATABASE_URL_UNPOOLED" ;;
  staging) var="STAGING_DATABASE_URL_UNPOOLED" ;;
  *)
    echo "Usage: $0 development|staging" >&2
    echo "Production is never set up with this script." >&2
    exit 2
    ;;
esac

if [ ! -f .env.environments ]; then
  echo "Missing .env.environments. Ask the repo owner for the connection strings (issue #28)." >&2
  exit 1
fi
# shellcheck disable=SC1091
set -a; . ./.env.environments; set +a

url="${!var:-}"
if [ -z "$url" ]; then
  echo "$var is not set in .env.environments." >&2
  exit 1
fi
seed_pw="${SEED_STAFF_PASSWORD:-}"
if [ "${#seed_pw}" -lt 12 ]; then
  echo "Set SEED_STAFF_PASSWORD (12+ characters) in .env.environments." >&2
  exit 1
fi

# Show where we are about to write, without the password.
host="$(printf '%s' "$url" | sed -E 's#^[a-z]+://[^@]*@([^/?:]+).*#\1#')"
db="$(printf '%s' "$url" | sed -E 's#^[a-z]+://[^/]+/([^?]+).*#\1#')"

# Production guard: if production's direct URL is also in the file, never match it.
if [ -n "${PROD_DATABASE_URL_UNPOOLED:-}" ] && [ "$url" = "$PROD_DATABASE_URL_UNPOOLED" ]; then
  echo "Refusing: $var is the same database as production." >&2
  exit 1
fi
# Neon branches share a project but have their own endpoint host; two environments on one host
# is almost certainly a copy-paste mistake.
if [ "$var" = "STAGING_DATABASE_URL_UNPOOLED" ] && [ "$url" = "${DEV_DATABASE_URL_UNPOOLED:-}" ]; then
  echo "Refusing: staging and development point at the same database." >&2
  exit 1
fi

echo "About to run migrations and seed the $env_name database:"
echo "  host:     $host"
echo "  database: $db"
printf 'Type "%s" to continue: ' "$env_name"
read -r answer
if [ "$answer" != "$env_name" ]; then
  echo "Cancelled." >&2
  exit 1
fi

# prisma.config.ts and prisma/seed.ts both prefer DIRECT_URL, so this overrides any other URL.
export DIRECT_URL="$url"

npx prisma migrate deploy
npx prisma db seed
echo "Done: $env_name now has tables and demo data."
