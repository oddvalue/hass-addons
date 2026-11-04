# Sourced by the image's /start.sh before Vaultwarden launches.
#
# Sets DOMAIN from the add-on's "domain" option. Supervisor keeps options in
# this add-on's private /data/options.json, so the hostname stays out of this
# public repo.
OPTIONS=/data/options.json

DOMAIN=$(sed -n 's/.*"domain"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$OPTIONS" 2>/dev/null)
if [ -z "$DOMAIN" ]; then
    echo "domain: no domain option in $OPTIONS, refusing to start" >&2
    exit 1
fi
export DOMAIN
