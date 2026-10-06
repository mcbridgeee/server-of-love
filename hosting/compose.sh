#!/bin/sh
# Run docker compose on the 373_hosting stack WITH the security overlay, so the
# dashboard password can't be dropped by forgetting the second -f file.
#
#   sudo ~/server-of-love/hosting/compose.sh up -d
#   sudo ~/server-of-love/hosting/compose.sh ps
#
# HOSTING_DIR defaults to ~/373_hosting (the instructor's repo on the droplet).
set -eu
HERE=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
HOSTING_DIR=${HOSTING_DIR:-$HOME/373_hosting}
[ -f "$HOSTING_DIR/runtime/compose.yaml" ] || { echo "no $HOSTING_DIR/runtime/compose.yaml (set HOSTING_DIR)" >&2; exit 1; }
[ -f "$HOSTING_DIR/runtime/secrets/dashboard.htpasswd" ] || { echo "missing runtime/secrets/dashboard.htpasswd: create it first (security/README.md step 3)" >&2; exit 1; }
exec docker compose -f "$HOSTING_DIR/runtime/compose.yaml" -f "$HERE/compose.security.yaml" "$@"
