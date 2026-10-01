#!/usr/bin/env bash
# copies the pages in this repo into the live site folders on server-of-love
set -euo pipefail
cd "$(dirname "$0")"
LIVE="$HOME/373_hosting/runtime/sites"
for site in sites/*/; do
  name="$(basename "$site")"
  if [ -d "$LIVE/$name" ]; then
    cp -r "$site". "$LIVE/$name/"
    echo "updated $name"
  else
    echo "skipped $name (no live folder yet; add it to hosting.json first)"
  fi
done
