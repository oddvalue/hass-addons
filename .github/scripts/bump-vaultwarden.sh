#!/usr/bin/env bash
# Keeps vaultwarden/ pinned to an upstream release by tag and image digest.
#
# Each run:
#   1. Checks the pinned release still exists upstream and its image tag still
#      points at the pinned digest. If not, it rolls back a bump younger than
#      ROLLBACK_HOURS (before Supervisor's one-day hold lets it install) and
#      fails, so GitHub emails the repo owner. An older bump may already be
#      installed, and rolling back would make Supervisor downgrade the vault,
#      so then it only fails.
#   2. Bumps to the latest release once both the GitHub release and the image
#      push are SOAK_DAYS old, unless that tag was pinned before at a different
#      digest. The upstream release notes go into the add-on's CHANGELOG.md,
#      which Home Assistant shows on the update screen.
#
# DRY_RUN=1 prints the change instead of committing it.
set -euo pipefail

REPO=dani-garcia/vaultwarden
IMAGE=vaultwarden/server
DOCKERFILE=vaultwarden/Dockerfile
CONFIG=vaultwarden/config.yaml
CHANGELOG=vaultwarden/CHANGELOG.md
SOAK_DAYS=${SOAK_DAYS:-2}
ROLLBACK_HOURS=${ROLLBACK_HOURS:-24}
DRY_RUN=${DRY_RUN:-}

now=$(date +%s)

die() {
    echo "::error::$*" >&2
    exit 1
}

# Prints the body of a 200 response. Returns 4 on 404 so callers can tell
# "gone" from "couldn't check"; any other outcome aborts the run.
get() {
    local url=$1 out code
    local -a auth=()
    [[ $url == https://api.github.com/* && -n ${GITHUB_TOKEN:-} ]] &&
        auth=(-H "Authorization: Bearer $GITHUB_TOKEN")
    out=$(mktemp)
    code=$(curl -sS -o "$out" -w '%{http_code}' "${auth[@]}" "$url") || die "request failed: $url"
    case $code in
        200) cat "$out" ;;
        404) return 4 ;;
        *) die "HTTP $code from $url" ;;
    esac
}

days_since() {
    echo $(( (now - $(date -d "$1" +%s)) / 86400 ))
}

# Prepends an entry for add-on version $1 with the notes of upstream release
# JSON $2 and image digest $3. Upstream headings move down a level to sit
# under ours, and GitHub's CRLF line endings are dropped.
add_changelog() {
    local notes
    notes=$(jq -r '.body // ""' <<<"$2" | tr -d '\r' | sed 's/^#/##/')
    {
        printf '## %s\n\n' "$1"
        # shellcheck disable=SC2016 # Markdown backticks, not a command
        printf 'Vaultwarden [%s](%s), image `%s`.\n\n' \
            "$(jq -r .tag_name <<<"$2")" "$(jq -r .html_url <<<"$2")" "$3"
        printf '%s\n\n' "$notes"
        if [[ -f $CHANGELOG ]]; then cat "$CHANGELOG"; fi
    } >"$CHANGELOG.new"
    mv "$CHANGELOG.new" "$CHANGELOG"
}

commit() {
    git add -A vaultwarden
    if [[ -n $DRY_RUN ]]; then
        echo "Dry run, would commit: $1"
        git diff --cached
        return
    fi
    git config user.name "github-actions[bot]"
    git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
    git commit -qm "$1"
    git push -q
}

pin=$(sed -n "s|^FROM $IMAGE:||p" "$DOCKERFILE")
[[ $pin =~ ^[0-9]+\.[0-9]+\.[0-9]+@sha256:[0-9a-f]{64}$ ]] ||
    die "$DOCKERFILE pins '$pin', expected <tag>@sha256:<digest>"
current=${pin%@*}
pinned_digest=${pin#*@}

# 1. Is the pinned release still what we pinned?
problem=
release=$(get "https://api.github.com/repos/$REPO/releases/tags/$current") && rc=0 || rc=$?
case $rc in
    0) [[ $(jq -r '.draft or .prerelease' <<<"$release") == false ]] ||
        problem="release $current is no longer a full release upstream" ;;
    4) problem="release $current no longer exists upstream" ;;
    *) exit 1 ;;
esac
if [[ -z $problem ]]; then
    hub=$(get "https://hub.docker.com/v2/repositories/$IMAGE/tags/$current") && rc=0 || rc=$?
    case $rc in
        0) [[ $(jq -r .digest <<<"$hub") == "$pinned_digest" ]] ||
            problem="$IMAGE:$current now points at $(jq -r .digest <<<"$hub"), not the pinned $pinned_digest" ;;
        4) problem="$IMAGE:$current no longer exists on Docker Hub" ;;
        *) exit 1 ;;
    esac
fi

if [[ -n $problem ]]; then
    echo "::error::$problem"
    bump=$(git log -1 --format=%H -G"^FROM $IMAGE:" -- "$DOCKERFILE")
    hours=$(( (now - $(git log -1 --format=%ct "$bump")) / 3600 ))
    if (( hours >= ROLLBACK_HOURS )); then
        die "The pin is ${hours}h old, so Supervisor may have installed it. Not rolling back, since that would downgrade the vault. Check the add-on by hand."
    fi
    prev_from=$(git show "$bump^:$DOCKERFILE" | grep "^FROM $IMAGE:")
    prev_version=$(git show "$bump^:$CONFIG" | sed -n 's/^version: //p')
    sed -i "s|^FROM $IMAGE:.*|$prev_from|" "$DOCKERFILE"
    sed -i "s|^version: .*|version: $prev_version|" "$CONFIG"
    if git cat-file -e "$bump^:$CHANGELOG" 2>/dev/null; then
        git show "$bump^:$CHANGELOG" >"$CHANGELOG"
    fi
    commit "Roll back Vaultwarden to ${prev_from#"FROM $IMAGE:"}

$problem"
    die "Rolled back the ${hours}h old pin. Investigate before the next bump."
fi
echo "Pinned $current is intact"

# 2. Is there a release worth moving to?
release=$(get "https://api.github.com/repos/$REPO/releases/latest")
tag=$(jq -r .tag_name <<<"$release")
[[ $tag =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "Unexpected tag format: $tag"

if [[ $tag == "$current" ]]; then
    echo "Up to date"
    exit 0
fi
if [[ $(printf '%s\n%s\n' "$current" "$tag" | sort -V | tail -n1) != "$tag" ]]; then
    echo "$tag is older than $current, ignoring"
    exit 0
fi

age=$(days_since "$(jq -r .published_at <<<"$release")")
if (( age < SOAK_DAYS )); then
    echo "Release $tag is $age days old, waiting for $SOAK_DAYS"
    exit 0
fi

hub=$(get "https://hub.docker.com/v2/repositories/$IMAGE/tags/$tag") && rc=0 || rc=$?
case $rc in
    0) ;;
    4) echo "$IMAGE:$tag is not on Docker Hub yet"; exit 0 ;;
    *) exit 1 ;;
esac
digest=$(jq -r .digest <<<"$hub")
[[ $digest =~ ^sha256:[0-9a-f]{64}$ ]] || die "Unexpected digest for $IMAGE:$tag: $digest"
age=$(days_since "$(jq -r .tag_last_pushed <<<"$hub")")
if (( age < SOAK_DAYS )); then
    echo "$IMAGE:$tag was pushed $age days ago, waiting for $SOAK_DAYS"
    exit 0
fi

# Collected first: grep -q in a pipe can SIGPIPE git log, and pipefail would
# then read a match as a miss.
previous=$(git log -p -- "$DOCKERFILE" | grep -F "FROM $IMAGE:$tag@" || true)
if [[ -n $previous ]] && grep -qvF "@$digest" <<<"$previous"; then
    die "$IMAGE:$tag was pinned before at a different digest and now points at $digest. Refusing to adopt it."
fi

sed -i "s|^FROM $IMAGE:.*|FROM $IMAGE:$tag@$digest|" "$DOCKERFILE"
sed -i "s|^version: .*|version: \"$tag-1\"|" "$CONFIG"
add_changelog "$tag-1" "$release" "$digest"
commit "Bump Vaultwarden to $tag"
