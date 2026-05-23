# Formulaar1 Docker — project context

## Goal
Containerize [Formulaar1](https://github.com/Jimmy062006/Formulaar1) and publish a
multi-arch image to Docker Hub (`healzangels/formulaar1`) so it can be deployed
on Unraid (or any Docker host) without building locally.

Formulaar1 sits between AutoBrr and Sonarr: AutoBrr pushes to it as if it were a
Sonarr client; Formulaar1 translates F1Carreras's per-session release naming
into the correct TVDB episode (via f1api.dev, with a built-in circuit-name
fallback for COTA / Imola / UAE / British etc.) and forwards to the real Sonarr
with proper metadata. This solves the episode-mapping wall where Sonarr's own
parser can't reconcile the release group's per-session sequential numbering
with TVDB.

Pipeline: `AutoBrr → Formulaar1 → Sonarr`

## Why this tool
F1Carreras numbers every session (FP1/FP2/FP3/SprintQuali/Sprint/Quali/Race) as
its own sequential episode (e.g. E30=FP1, E33=Quali for a given round). TVDB
numbers differently, so Sonarr's ID/episode-based search returns garbage
(wrong GP, wrong session, even F3 instead of F1). Category mapping and
Daily-vs-Standard series type were both ruled out as fixes. Formulaar1 does the
explicit translation.

## Repo layout
- `Dockerfile` — multi-stage build from upstream tagged source. Targets `.NET 10`.
- `docker-compose.yml` — pulls `healzangels/formulaar1:v0.5.0` by default; `build:` block commented for local-build mode.
- `appsettings.example.json` — schema mirrors upstream v0.5.0. The real config (with secrets) lives at `/mnt/user/appdata/formulaar1/appsettings.json` on the host and is bind-mounted in.
- `.github/workflows/docker-publish.yml` — multi-arch (amd64+arm64) build on `main` push and on `v*` tags; tag → builds that upstream ref.
- `.gitignore` — keeps real `appsettings.json` out of git.

## Build & publish flow
- Push to `main` → workflow builds upstream `DEFAULT_FORMULAAR1_REF` and pushes `:latest`.
- Tag `vX.Y.Z` here → workflow builds upstream `vX.Y.Z` and pushes that tag.
- Manual run from Actions tab → can override the upstream ref.

Required GH secrets: `DOCKERHUB_USERNAME`, `DOCKERHUB_TOKEN` (Docker Hub PAT with read/write on the repo).

## Open items / things to watch
1. **First image build.** Confirm the workflow run on first push succeeds end-to-end. .NET 10 base images (`mcr.microsoft.com/dotnet/sdk:10.0` / `aspnet:10.0`) should be GA by now — if a stage fails on pull, fall back to a `10.0-preview` tag.
2. **First-run validation on Unraid.** `docker logs -f formulaar1` should show:
   ```
   Detected qBittorrent Client, attempting to login
   Logged in to <version>
   Now listening on: http://0.0.0.0:5000
   ```
   If qBit login fails: wrong WebUI port, wrong creds, or qBit's auth-bypass whitelist doesn't cover the docker bridge subnet (Formulaar1 will arrive from the bridge's IP range, not the host LAN IP).
3. **AutoBrr wiring.** Add a Sonarr-type client pointing at `http://<unraid-host>:5000` (or the container DNS name if on the same bridge), using the **normal** Sonarr API key (Formulaar1 forwards it).
4. **AutoBrr filter design.** Match on title text:
   - Match: `Formula1`, `F1TV`, desired resolution
   - Match the session(s) wanted: Quali / Race / Sprint / FP1...
   - **Reject Spanish dupes:** `Castellano`, `es-ES`
   - Decide all-7-sessions vs Quali+Race only, or it pulls a lot per weekend.

## Caveats
- Upstream v0.5.0, single maintainer, small project. Expect rough edges — check [upstream issues](https://github.com/Jimmy062006/Formulaar1/issues) if behaviour is odd.
- No upstream Docker image; this build is self-maintained. Bump `DEFAULT_FORMULAAR1_REF` (or push a new git tag) when a new upstream release lands.
- Hardlinking is supported on Linux/macOS/Windows in v0.5.0 (was Linux-only earlier).
