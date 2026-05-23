# Formulaar1 Docker

Unofficial Docker packaging of [Jimmy062006/Formulaar1](https://github.com/Jimmy062006/Formulaar1) for use on Unraid (or any Docker host).

Formulaar1 sits between AutoBrr and Sonarr. AutoBrr thinks it's pushing to a
Sonarr instance; really it's pushing to Formulaar1, which translates the
F1Carreras per-session release naming into the correct TVDB episode (via
f1api.dev, with a built-in circuit-name fallback for COTA / Imola / UAE /
British etc.) and then hands off to your real Sonarr with proper metadata.

Pipeline: `AutoBrr → Formulaar1 → Sonarr`

## Image

Published to Docker Hub as **`healzangels/formulaar1`** — multi-arch
(`linux/amd64`, `linux/arm64`), built from upstream tagged source by the
GitHub Actions workflow in `.github/workflows/docker-publish.yml`.

Tags:
- `healzangels/formulaar1:v0.5.0` — built from upstream `v0.5.0`
- `healzangels/formulaar1:latest` — tip of `main` here (whatever upstream ref `DEFAULT_FORMULAAR1_REF` points at in the workflow)

## Quick start (Unraid)

### 1. Place the config
```bash
mkdir -p /mnt/user/appdata/formulaar1
cp appsettings.example.json /mnt/user/appdata/formulaar1/appsettings.json
```

Edit `/mnt/user/appdata/formulaar1/appsettings.json` and fill in:
- `APICredentials.Sonarr.ApiKey` — Sonarr → Settings → General → API Key
- `APICredentials.Sonarr.BasePath` — e.g. `http://10.0.1.98:8989`
- `APICredentials.qBittorrentClient.Username` / `Password`
- `APICredentials.qBittorrentClient.BasePath` — **double-check the port.** Earlier seasonpackarr debugging found 8585 was wrong and the real qBit WebUI was on 8080. If first-run login fails, try 8080 before debugging anything else.
- `Hardlinkpath` — path inside the container where Formulaar1 places hardlinks. Must be on the same mount as your downloads. `/data` here maps to `/mnt/user/data` on the host (identical to qBittorrent and Sonarr).

### 2. Start it

```bash
docker compose pull
docker compose up -d
docker logs -f formulaar1
```

On startup you should see:
```
Detected qBittorrent Client, attempting to login
Logged in to <version>
Now listening on: http://0.0.0.0:5000
```

If qBit login fails: (a) wrong port — try 8080, (b) WebUI creds, or
(c) qBittorrent's "Bypass authentication" whitelist doesn't cover the docker
bridge subnet (`cmacproxy` is `172.18.0.0/16`). Formulaar1 will arrive at qBit
as a `172.18.x.x` source IP, not the host LAN IP.

### 3. Wire AutoBrr

In AutoBrr → Settings → Clients → Add:
- **Type:** Sonarr
- **Name:** Formulaar1
- **Host:** `http://10.0.1.98:5000` (or `http://formulaar1:5000` if AutoBrr is on `cmacproxy`)
- **API Key:** your **normal Sonarr API key** (Formulaar1 forwards it)

Click Test → expect green. Then point your F1 filter's action at this client instead of your real Sonarr.

### 4. Filter design tips (F1Carreras)

- Match: `Formula1`, `F1TV`, your resolution (e.g. `1080p` or `2160p`)
- Match the session(s) you want: `Qualifying` / `Race` / `Sprint` / `FP1` ...
- **Reject Spanish dupes:** `Castellano`, `es-ES` — F1Carreras posts International English + Castellano for every session
- Decide all-7-sessions vs Quali+Race only, or it'll pull a lot per weekend

## Building / publishing

### Trigger a publish

Push to `main` → builds and publishes `:latest`.
Tag the repo `vX.Y.Z` → builds upstream Formulaar1 `vX.Y.Z` and publishes that tag.

```bash
git tag v0.5.0
git push --tags
```

You can also run the workflow manually from the Actions tab and pass any upstream ref.

### One-time secret setup

The workflow needs Docker Hub creds. In GitHub → Settings → Secrets and variables → Actions:
- `DOCKERHUB_USERNAME` = `healzangels`
- `DOCKERHUB_TOKEN` = a Docker Hub access token (Docker Hub → Account Settings → Personal access tokens → Generate, with **Read/Write** scope on the `healzangels/formulaar1` repo)

### Building locally instead

If you'd rather skip the registry and build on the Unraid box, comment out
`image:` in `docker-compose.yml` and uncomment the `build:` block, then:

```bash
docker compose build
docker compose up -d
```

## Notes

- Upstream is .NET 10. Base images: `mcr.microsoft.com/dotnet/sdk:10.0` and `mcr.microsoft.com/dotnet/aspnet:10.0`.
- v0.5.0, single maintainer, small project. Expect rough edges — check the [upstream issues](https://github.com/Jimmy062006/Formulaar1/issues) if behaviour is odd.
- Bump `DEFAULT_FORMULAAR1_REF` in the workflow (or just push a new git tag) when a new upstream release lands.
