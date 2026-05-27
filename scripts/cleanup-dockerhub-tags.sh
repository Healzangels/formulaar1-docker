#!/usr/bin/env bash
# Delete v0.5.0-fix* image tags from Docker Hub for healzangels/formulaar1.
#
# One-time cleanup script run as part of the v1.0.0 release. The 28-fix
# history is documented in commit messages; the old image tags are
# clutter on Docker Hub's tag list.
#
# Usage:
#   DOCKERHUB_USER=healzangels DOCKERHUB_PAT=<your-PAT> ./cleanup-dockerhub-tags.sh
#
# Get a Docker Hub PAT from:
#   https://app.docker.com/settings/personal-access-tokens
#   -> Generate new token
#   -> Permissions: "Read, Write, Delete" (Delete is required for this script)
#   -> Repository: limit to "healzangels/formulaar1" if you want to scope tightly
#
# Output: one line per tag, format "[HTTP-status] tag-name"
#   [204] = deleted successfully
#   [404] = tag didn't exist on Docker Hub (already deleted or never built)
#   [401/403] = auth problem; check your PAT
#   anything else = unexpected; raise an issue

set -e

USER="${DOCKERHUB_USER:?must set DOCKERHUB_USER (likely 'healzangels')}"
PAT="${DOCKERHUB_PAT:?must set DOCKERHUB_PAT (get from app.docker.com/settings/personal-access-tokens)}"
REPO="formulaar1"

echo "Logging in to Docker Hub as $USER..."
TOKEN=$(curl -s -H "Content-Type: application/json" \
  -d "{\"username\":\"$USER\",\"password\":\"$PAT\"}" \
  https://hub.docker.com/v2/users/login/ | jq -r .token)

if [ -z "$TOKEN" ] || [ "$TOKEN" = "null" ]; then
  echo "ERROR: Failed to get JWT from Docker Hub. Check DOCKERHUB_USER and DOCKERHUB_PAT."
  exit 1
fi

echo "OK, deleting old tags from $USER/$REPO..."
echo

TAGS=(
  v0.5.0-clearlogo-fix1
  v0.5.0-fix2 v0.5.0-fix3 v0.5.0-fix4 v0.5.0-fix5 v0.5.0-fix6
  v0.5.0-fix7 v0.5.0-fix8 v0.5.0-fix9 v0.5.0-fix10 v0.5.0-fix11
  v0.5.0-fix12 v0.5.0-fix13 v0.5.0-fix14 v0.5.0-fix15 v0.5.0-fix16
  v0.5.0-fix17 v0.5.0-fix18 v0.5.0-fix19 v0.5.0-fix19-debug
  v0.5.0-fix20 v0.5.0-fix21 v0.5.0-fix22 v0.5.0-fix23 v0.5.0-fix24
  v0.5.0-fix25 v0.5.0-fix26 v0.5.0-fix27 v0.5.0-fix28
)

for TAG in "${TAGS[@]}"; do
  HTTP=$(curl -s -o /dev/null -w "%{http_code}" -X DELETE \
    -H "Authorization: JWT $TOKEN" \
    "https://hub.docker.com/v2/repositories/$USER/$REPO/tags/$TAG/")
  echo "[$HTTP] $TAG"
done

echo
echo "Done. Remaining tags at https://hub.docker.com/r/$USER/$REPO/tags"
