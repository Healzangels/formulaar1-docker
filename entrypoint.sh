#!/bin/sh
# Drop privileges at container start so Formulaar1 runs as the *arr stack
# UID (Unraid's nobody:users = 99:100 by default) instead of root.
#
# Why: the upstream Dockerfile runs the app as root. Any directories the
# hardlink monitor creates land as root:root mode 755, and Sonarr (running
# as 99:100) can read but not WRITE -- so the import step that moves files
# out of the new directory fails with 'Access to the path is denied.'
# Honouring PUID/PGID here makes the container fit cleanly into the
# permission model the rest of the *arr stack already uses, without
# chmod 0777 workarounds inside the app.
#
# setpriv is part of util-linux, present in the .NET aspnet base image.
# --clear-groups drops supplemental groups (the app doesn't need any).

set -e

PUID="${PUID:-99}"
PGID="${PGID:-100}"

echo "[entrypoint] Starting Formulaar1 as ${PUID}:${PGID}"

exec setpriv --reuid="${PUID}" --regid="${PGID}" --clear-groups ./Formulaar1
