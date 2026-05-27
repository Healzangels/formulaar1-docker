# Formulaar1 Docker

[![Build and publish Docker image](https://github.com/Healzangels/formulaar1-docker/actions/workflows/docker-publish.yml/badge.svg)](https://github.com/Healzangels/formulaar1-docker/actions/workflows/docker-publish.yml)

Unofficial Docker packaging of [Jimmy062006/Formulaar1](https://github.com/Jimmy062006/Formulaar1) with patches for current Sonarr v4 and qBittorrent 5.x. Intended for use on Unraid or any Docker host.

Formulaar1 sits between AutoBrr and Sonarr. AutoBrr thinks it's pushing to a Sonarr instance; really it's pushing to Formulaar1, which translates releases that use non-standard episode numbering into the correct TVDB episode (via an external round/circuit lookup API, with a built-in name fallback) and hands off to your real Sonarr with the correct metadata.

Pipeline: `AutoBrr → Formulaar1 → Sonarr`

## Image

Published to Docker Hub as **`healzangels/formulaar1`** — multi-arch (`linux/amd64`, `linux/arm64`), built from the [`Healzangels/Formulaar1` fork](https://github.com/Healzangels/Formulaar1) by the GitHub Actions workflow in `.github/workflows/docker-publish.yml`.

The fork patches upstream v0.5.0 for current Sonarr v4 and qBittorrent 5.x compatibility (the bundled NuGet SDKs are abandoned and break on the newer schemas).

Tags:
- `healzangels/formulaar1:vX.Y.Z` — specific version, immutable. Current stable is `:v1.0.0`. **Recommended for homelab deploys.**
- `healzangels/formulaar1:latest` — rolling tag pointing at the most recent stable version

For day-to-day operation, log line meaning, config reference, and troubleshooting, see [OPERATIONS.md](OPERATIONS.md).

## Quick start (Unraid)

### 1. Place the config

```bash
mkdir -p /mnt/user/appdata/formulaar1
cp appsettings.example.json /mnt/user/appdata/formulaar1/appsettings.json
```

Edit `/mnt/user/appdata/formulaar1/appsettings.json` and fill in:

- `APICredentials.Sonarr.ApiKey` — Sonarr → Settings → General → API Key
- `APICredentials.Sonarr.BasePath` — your Sonarr URL, e.g. `http://<unraid-host>:8989`
- `APICredentials.qBittorrentClient.Username` / `Password` — qBit WebUI credentials
- `APICredentials.qBittorrentClient.BasePath` — qBit WebUI URL, e.g. `http://<unraid-host>:8080`
- `EnableHardlinking` — **must be `true`** for the tool to function; see OPERATIONS.md for why
- `Hardlinkpath` — inside-container path where Formulaar1 places renamed hardlinks before triggering Sonarr's import. Typically points at the relevant Sonarr series root, e.g. `/data/media/tv/<your series>`. Must be on the same filesystem mount as qBit's download path.

### 2. Start it

```bash
docker compose pull
docker compose up -d
docker logs -f formulaar1
```

On startup you should see:

```
Detected qBittorrent Client, attempting to login
[QBit] Login OK, got session cookie 'QBT_SID_8080' (32 chars)
Logged in to <qBittorrent version>
[F1API] Loaded 24 circuits for current season.
[Hardlinking] Enabled — timer will start when a release is queued.
Now listening on: http://0.0.0.0:5000
```

If you see `[Hardlinking] Disabled — Sonarr will handle file management.` instead of `Enabled`, your `appsettings.json` has `"EnableHardlinking": false`. This won't work for the release naming this tool handles — Sonarr's parser can't reconcile year-as-season releases. Set it to `true`. See OPERATIONS.md for the full explanation.

If qBit login fails, the log identifies the specific cause:

- `[QBit] Login refused: HTTP 401/403 ...` — wrong creds, or qBit's auth-bypass whitelist doesn't cover the docker bridge subnet (Formulaar1 arrives from the bridge IP range, not the host LAN IP). Add the bridge subnet to qBittorrent → Options → Web UI → "Bypass authentication for clients in whitelisted IP subnets."
- `[QBit] Login failed (bad credentials?)` — wrong username/password
- Wrong port — the qBit WebUI port is whatever you configured in qBittorrent → Options → Web UI; verify it matches `BasePath` in your config

See [OPERATIONS.md](OPERATIONS.md) for the full log line catalog and troubleshooting matrix.

### 3. Wire AutoBrr

In AutoBrr → Settings → Clients → Add:

- **Type:** Sonarr
- **Name:** Formulaar1
- **Host:** `http://<host>:5000` (or container DNS name if AutoBrr is on the same docker network)
- **API Key:** your **normal Sonarr API key** (Formulaar1 forwards it)

Click Test → expect green. Then point your AutoBrr filter's action at this client instead of your real Sonarr.

### 4. Filter design tips (AutoBrr)

Route releases through Formulaar1 when the release naming uses year-as-season (e.g. `<year>.Round<NN>.<session>`) rather than `SxxExx`. Sonarr's parser can't determine the episode otherwise.

If your source already publishes releases with an `SxxExx` pattern in the filename, those parse cleanly in Sonarr directly — you can optionally bypass Formulaar1 and point the AutoBrr action straight at Sonarr. Or keep them routed through Formulaar1 for consistency; the hardlink step is redundant but harmless.

General filter tuning:

- Match the session(s) you want: `Qualifying`, `Race`, `Sprint`, `FP1`, etc. — most weekends carry 5-7 sessions; pulling all of them adds up
- Limit to a single resolution to avoid getting both 1080p and 2160p variants
- Reject foreign-language dupes if your source publishes multiple language variants per session

## Notes

- This is an unofficial packaging. Upstream is a small, single-maintainer project — this fork adds the patches needed for current Sonarr v4 and qBit 5.x.
- Issues with the underlying tool: <https://github.com/Jimmy062006/Formulaar1/issues>
- Issues with this fork or Docker packaging: <https://github.com/Healzangels/formulaar1-docker/issues>
- Build/publish is automated by `.github/workflows/docker-publish.yml` — pushes to `main` rebuild `:latest`, version tags rebuild the corresponding version tag. Read the workflow if you want to fork or self-host this packaging.

## License

GPL-3.0 — same as upstream Formulaar1. See [LICENSE](LICENSE).
