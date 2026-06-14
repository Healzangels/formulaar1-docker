# Formulaar1 Operations Reference

Day-to-day reference for running this container. The README covers what
Formulaar1 is and how to deploy it; this document covers what every config
option does, what every log line means, and what to do when something
breaks.

---

## Architecture (one paragraph)

AutoBrr pushes a release to Formulaar1 (which it thinks is a Sonarr
instance). Formulaar1 parses the release filename, queries an external
round/circuit lookup API, maps that to the TVDB episode number for the
year-season, **rewrites the release title to include the correct
`SxxExx`**, and forwards to the real Sonarr's `/api/v3/release/push`.
Sonarr accepts it and tells qBit to download. While qBit downloads,
Formulaar1's monitor polls qBit every 10s for completion. When the
torrent finishes, Formulaar1 hardlinks the file into Sonarr's library
path with a Sonarr-friendly filename, then triggers the import via
Sonarr's command bus. Smart queue cleanup mops up any stuck queue entry
afterward.

The whole reason this exists: Sonarr's parser can't reconcile some
sources' per-session sequential numbering with TVDB's canonical episode
numbering. Without the title rewrite + hardlink-with-renamed-file,
Sonarr would either reject the release or import it to the wrong
episode.

---

## Configuration reference

Edit `/mnt/user/appdata/formulaar1/appsettings.json`. Restart the
container to apply (no hot-reload).

### Required

| Key | Description |
|---|---|
| `APICredentials.Sonarr.ApiKey` | Sonarr's API key (Sonarr → Settings → General → API Key) |
| `APICredentials.Sonarr.BasePath` | URL Sonarr can be reached at from inside the container, e.g. `http://<host>:8989` |
| `APICredentials.qBittorrentClient.Username` | qBit WebUI username |
| `APICredentials.qBittorrentClient.Password` | qBit WebUI password |
| `APICredentials.qBittorrentClient.BasePath` | qBit WebUI URL, e.g. `http://<host>:8080` (verify the port matches qBittorrent → Options → Web UI) |
| `TorrentClient` | `"qBittorrent"` — only client supported |
| `Hardlinkpath` | Inside-container path to the relevant Sonarr series root for hardlinks, e.g. `/data/media/tv/<your series>`. Must be on the same filesystem mount as qBit's download path. |
| `EnableHardlinking` | `true` — required for this tool to function (see note below) |

### Optional

| Key | Default | Values | Description |
|---|---|---|---|
| `AllowBugSnag` | `false` | bool | Master kill switch for BugSnag telemetry. Must be `true` **and** the nested `bugsnag.enabled` for telemetry to actually fire |
| `APICredentials.bugsnag.enabled` | `false` | bool | Nested BugSnag toggle (paired with `AllowBugSnag`) |
| `APICredentials.bugsnag.apiKey` | `""` | string | BugSnag API key (irrelevant unless both toggles above are true) |
| `Logging.LogLevel.Default` | `"Information"` | `"Trace"` / `"Debug"` / `"Information"` / `"Warning"` / `"Error"` | Standard ASP.NET log level |

### Environment variables (set on the container, not in appsettings)

| Env var | Default | Description |
|---|---|---|
| `PUID` | `99` | User ID the app runs as. `99` = Unraid `nobody`. Must match the UID that owns files Sonarr/qBit produce |
| `PGID` | `100` | Group ID. `100` = Unraid `users` |
| `TZ` | `America/New_York` | IANA timezone. Affects log timestamps. Note: history-matching in code uses UTC internally regardless |

### About `EnableHardlinking`

This flag gates Formulaar1's entire monitor + import pipeline. With it
`false`, you're left with just the release-rewrite layer — AutoBrr pushes,
Formulaar1 rewrites the title, Sonarr accepts and starts the download…
and then Sonarr's Completed Download Handler tries to import the
original filename. For releases that use year-as-season naming, Sonarr
interprets the year as a season number followed by part of an episode
number, fails the parse, and leaves the file in qBit's complete folder
forever. **For the releases this tool handles, keep this `true`.**

The flag exists in upstream Formulaar1 for use cases where Sonarr's
parser would have worked fine on its own.

### Import flow

After qBit finishes the download, Formulaar1's monitor:

1. Hardlinks the file under `Hardlinkpath/<Series> - SxxExx/` with a renamed filename containing the SxxExx prefix so Sonarr's parser can map it
2. Sends a `DownloadedEpisodesScan` command to Sonarr (`/api/v3/command`)
3. Waits 30 seconds for Sonarr's CDH to do its thing
4. Checks the Sonarr queue for entries matching this `downloadId` (qBit InfoHash):
   - If status is `warning`/`error`, or `errorMessage` is set → DELETEs the entry (CDH got stuck; our scan already imported the file)
   - If healthy → leaves it alone, Sonarr will manage it
   - If gone → logs "cleared naturally" and exits

This goes through Sonarr's full CDH pipeline, which handles file relocation
to `Season YYYY/` and Sonarr-side renaming per your Media Management
template.

---

## The `/health` endpoint

`GET http://<host>:5000/health` returns:

```json
{
  "status": "ok",
  "version": "v1.0.2",
  "uptimeSeconds": 12345,
  "torrentClient": "qBittorrent",
  "sonarrConfigured": true,
  "hardlinkingEnabled": true,
  "releasesInQueue": 0
}
```

Safe for Docker healthchecks, Uptime Kuma, etc. — no URLs, API keys, file
paths, or grab history leak through.

---

## Log line catalog

Look for these prefixes when reading logs:

- `[QBit]` — qBit login / version diagnostics
- `[F1API]` — external round/circuit lookup (loaded once at startup)
- `[Sonarr]` — release-push decisions (accept/reject)
- `[Hardlinking]` — monitor ticks, hardlink operations, scan dispatch, queue cleanup

### Startup

| Line | Meaning |
|---|---|
| `Detected qBittorrent Client, attempting to login` | About to call qBit auth API |
| `[QBit] Login OK, got session cookie 'QBT_SID_8080' (32 chars)` | qBit auth succeeded |
| `Logged in to v5.2.0` | qBit version reachable via authenticated request |
| `[F1API] Loaded N circuits for current season` | External lookup API returned the season's circuit list; name-based fallback is now armed |
| `[Hardlinking] Enabled — timer will start when a release is queued.` | Monitor timer registered (idle until a release arrives) |
| `[Hardlinking] Disabled — Sonarr will handle file management.` | `EnableHardlinking: false`. **Imports won't actually complete for the releases this tool handles.** |

### Login failures

| Line | Meaning | Fix |
|---|---|---|
| `[QBit] Login refused: HTTP 401 Unauthorized` | qBit rejected the connection at auth | Check creds; verify the qBittorrent → Options → Web UI "Bypass authentication for clients in whitelisted IP subnets" covers your docker bridge subnet (typically `172.18.0.0/16` or `172.17.0.0/16`). Formulaar1 arrives from the bridge IP range, not your host LAN IP |
| `[QBit] Login refused: HTTP 403 Forbidden` | IP banned (too many failed logins?) or Referer mismatch | Check qBit logs; clear the IP ban in qBit settings; restart qBit if needed |
| `[QBit] Login failed (bad credentials?): body='Fails.'` | qBit's standard "wrong username/password" response | Verify `Username` and `Password` in appsettings.json |
| `[QBit] Login response had Set-Cookie headers but none matched 'SID=' or 'QBT_SID_'` | qBit returned a cookie we don't recognize (future qBit version with new naming?) | Open an issue — would need a shim update |
| `[QBit] Login succeeded ... but NO Set-Cookie header in response` | HttpClient is consuming cookies before we can read them | Indicates a regression in our HttpClient construction — open an issue |

### Per-release lifecycle

| Line | Meaning |
|---|---|
| `Processing` | Release pushed in from AutoBrr |
| `ShowType: Race` | Series detection + session type |
| `[Sonarr] Resolved series '<name>' for tvdbId <N> -> seriesId <N>` | Sonarr's seriesId lookup succeeded |
| `[Sonarr] Push response: 1 decision(s)` | Sonarr's release-push endpoint returned a verdict |
| `[Sonarr] ACCEPTED: <title>` | Release accepted into Sonarr's queue |
| `[Sonarr] REJECTED: <title> -- <reason>` | Sonarr declined. Common reasons: "Existing file on disk has an equal or higher Custom Format score", "Episode does not exist". The reason is Sonarr's own text |
| `[Hardlinking] Release queued — starting download monitor.` | Monitor timer kicked off |
| `Pushing to Sonarr: <title>` | Logged twice per push (once before, once after — upstream quirk) |

### Monitor ticks (every 10s while there are releases in flight)

| Line | Meaning |
|---|---|
| `[Hardlinking] Monitor tick: N release(s) in queue` | Beginning of a tick |
| `[Hardlinking] Processing release '<title>' (InfoHash=<hash>)` | Working on a specific release |
| `[Hardlinking] qBit returned 1 torrent(s) for hash <hash>: name='...' completionOn=<null, still downloading>` | qBit confirms the torrent exists and is still grabbing |
| `[Hardlinking] qBit returned 1 torrent(s) for hash <hash>: name='...' completionOn=2026-05-26 04:48:03Z` | Torrent has finished — `completionOn` is populated |
| `[Hardlinking] qBit has no torrent with hash <hash> -- still being added? Will retry next tick.` | Hash mismatch (case? wrong client?) or qBit hasn't registered the torrent yet |
| `[Hardlinking] Evicting stuck release after >24h` | Safety eviction: a release was queued >24h ago and never resolved. Indicates qBit/Sonarr connectivity issues or a dropped torrent |

### Import (post-download)

| Line | Meaning |
|---|---|
| `Hard Linking <src> to <dst>` | File hardlinked into Sonarr's library path with SxxExx-bearing name |
| `Sending Command:DownloadedEpisodesScan Mode:Auto Torrent:<name> for path "..."` | Scan command dispatched to Sonarr |

### Queue cleanup (30s after scan)

| Line | Meaning |
|---|---|
| `[Hardlinking] No queue item left for <hash> -- Sonarr cleared it naturally` | Queue was empty when smart cleanup ran (Sonarr's CDH must have resolved it) |
| `[Hardlinking] Removed stuck Sonarr queue item N (status: warning, err: <msg>). File already imported via scan.` | Stuck entry found and removed (CDH got confused parsing the qBit filename, but our scan already imported the file) |
| `[Hardlinking] Queue item N for <hash> looks healthy (status: ok/...); leaving for Sonarr to manage` | Entry was healthy, not stuck — Sonarr will handle it |
| `[Hardlinking] Queue empty — monitor idle.` | All releases processed, timer stops |

---

## Troubleshooting matrix

| Symptom | Most likely cause | Where to look |
|---|---|---|
| `[QBit] Login refused / failed` at startup | Wrong creds, wrong port, IP not whitelisted | Compare to "Login failures" table above |
| `[Sonarr] REJECTED: ... Episode does not exist` | TVDB doesn't have that episode for the year. External lookup → TVDB episode mapping needs an update | Look at the external API's data for that round/year; may need to refresh the circuit cache (restart container) |
| `[Sonarr] REJECTED: ... Existing file on disk has a equal or higher CF score` | Already imported a version with equal/better Custom Format score | Normal — Sonarr's dedup. Delete the existing file in Sonarr if you genuinely want to replace it |
| `[Hardlinking] qBit has no torrent with hash <hash>` for many ticks | qBit didn't accept the torrent, or the torrent's category/path was never set | Check qBit's UI for the torrent; check if AutoBrr's filter is configured to category-tag correctly |
| `[Hardlinking] Evicting stuck release after >24h` | Something genuinely wrong — qBit lost the torrent, hash mismatch we can't fix, or Sonarr/qBit became unreachable mid-flight | Check qBit + Sonarr connectivity from the container |
| Hardlink fails / "Hard link failed (code -1)" | qBit downloads and Sonarr library are on different filesystems | Both must be on the same mount inside the container. Verify `/data` mapping is identical across qBit, Sonarr, and Formulaar1 |
| File imports but Sonarr UI doesn't reflect the new episode without a manual refresh | SignalR/WebSocket layer is broken end-to-end. Common cause: reverse proxy missing WebSocket upgrade headers, or Authentik proxy provider misconfigured | Browser DevTools → Network → filter "WS"; should see `wss://...signalr/messages` with status `101 Switching Protocols`. If missing, fix the proxy chain |
| Series page doesn't show file at all (even after refresh) | Import path didn't actually run. Check the per-release log lines | Look for `Sending Command:DownloadedEpisodesScan` — if it's missing, hardlink didn't fire or qBit completion wasn't detected |
| Queue stuck on a `warning` state forever | Smart cleanup didn't run, or qBit returned 0 torrents for the hash | Manually delete the queue entry in Sonarr's UI (it's safe — the file is on disk). Check log for `[Hardlinking] qBit returned 1 torrent(s) for hash ... completionOn=...` |

---

## Operational recipes

### Pin to a specific version

In your Unraid template / docker-compose, set the image tag to a specific version like `healzangels/formulaar1:v1.0.2` instead of `:latest`. The image is then immutable — no surprise updates.

### See what's currently in flight

```
curl http://<host>:5000/health | jq
```

Look at `releasesInQueue`. If `0`, the monitor is idle. Otherwise that many releases are mid-flight.

### Re-test a release after deleting it from Sonarr

If you push the same release from AutoBrr twice while the first import is still in progress, Sonarr's queue dedup will reject the second one with `"Existing file on disk has ..."` or `"Episode already grabbed"`. To re-test cleanly:

1. In Sonarr, delete the queue entry (and the file if Sonarr imported it)
2. Push the release again from AutoBrr

### Roll back to a previous version

Each version is its own immutable Docker tag. To roll back, change the tag in your Unraid template (or docker-compose) to a prior `:vX.Y.Z` and restart the container. No state to migrate; `appsettings.json` is forward/backward compatible across versions.

---

## Project layout

```
formulaar1/                    # this repo (docker packaging)
├── Dockerfile                 # multi-stage build; pulls source from the fork
├── docker-compose.yml         # deployment example
├── appsettings.example.json   # config template (real one with secrets at /mnt/user/appdata/formulaar1/)
├── entrypoint.sh              # PUID/PGID drop-privs via setpriv
├── unraid-template.xml        # Unraid Community Applications template
├── unraid/icon.png
└── .github/workflows/docker-publish.yml   # multi-arch GHA build

Healzangels/Formulaar1         # fork repo (the actual app code)
├── Formulaar1/
│   ├── Program.cs                       # main app
│   ├── Helpers.cs                       # series detection, country lookup
│   ├── F1ApiClient.cs                   # external lookup API integration
│   ├── SonarrSeriesShim.cs              # direct-HTTP Sonarr series API (bypasses broken SDK)
│   ├── SonarrEpisodeShim.cs             # direct-HTTP Sonarr episode API
│   ├── SonarrHistoryShim.cs             # direct-HTTP Sonarr history API
│   ├── SonarrQueueShim.cs               # direct-HTTP Sonarr queue API
│   └── QBittorrentShim.cs               # direct-HTTP qBit auth + torrent info
└── appsettings.example.json
```

The "shim" pattern exists because the bundled `APIv3SonarrDotcore` (last
updated 2023) and `QBittorrent.Client` (last updated 2023) NuGet packages
have rigid enum deserializers that crash on data shapes added in newer
Sonarr/qBit versions (e.g. `clearlogo` MediaCoverType, `stoppedDL`
TorrentState, `QBT_SID_<port>` cookie name). The shims model only the
fields we read and use string fields where the SDKs used enums, sidestepping
the breakage class entirely.

---

## When something breaks

1. Get a clean log dump: `docker logs formulaar1 --since 5m`
2. Match the symptom against the Troubleshooting matrix above
3. If it's a clear bug, open an issue at <https://github.com/Healzangels/formulaar1-docker/issues> and include:
   - `/health` output
   - The relevant log lines
   - The release title that triggered it (sanitized if needed)
   - Sonarr + qBit versions
