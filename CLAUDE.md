# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A small Alpine-based Docker image that, on a cron schedule, downloads a JPEG snapshot from an IP webcam and uploads it via FTP to Ambient Weather (`ftp2.ambientweather.net`). All logic is POSIX `/bin/sh` — there is no compiled code, package manager, or test suite.

## Common commands

Build and run via compose (requires `.env` derived from `example.env`):
```bash
cp example.env .env       # then edit .env
docker compose up -d --build
docker compose logs -f
```

Build the image directly:
```bash
docker build -t ams-cam-upload .
```

Run the upload once inside a running container (useful for verifying credentials/URL without waiting for cron):
```bash
docker exec -it ams-cam-upload /usr/local/bin/ams-cam-upload.sh
```

Inspect health (the container's HEALTHCHECK runs `healthcheck.sh` every 2 minutes):
```bash
docker inspect --format='{{.State.Health.Status}}' ams-cam-upload
```

CI (`.github/workflows/ci.yml`) builds multi-arch (`linux/amd64,linux/arm64`) on push to `main`/`develop` and pushes `:latest` to Docker Hub. There are no lint/test steps — local shell-script changes should be sanity-checked with `sh -n <file>` and ideally `shellcheck`.

## Architecture

Three shell scripts cooperate inside the container; understanding their split is the whole picture:

1. **`entrypoint.sh`** (PID 1) — runs once at container start. Validates required env vars (`INPUT_IP_ADDRESS`, `SERVER`, `PORT`, `USERNAME`, `PASSWORD`) plus format checks for `CRON_SCHEDULE`, `INPUT_IP_ADDRESS` (must be `http(s)://`), `PORT`, `SERVER`, and the optional `IMAGE_RESIZE` / `IMAGE_QUALITY`. Then writes a quoted, mode-600 `/etc/environment` (because cron jobs run with an empty environment), runs the upload once immediately, installs two crontab entries (the upload job and a 6-hourly logrotate), and execs `crond -f`. Note: only a specific allowlist of variables is forwarded to `/etc/environment` — adding a new tunable means editing the `grep -E` allowlist here.

2. **`ams-cam-upload.sh`** — the per-tick worker invoked by cron. Pipeline: `cleanup_old_images` → `download_image` (wget with retries, validates size + MIME) → `process_image` (optional ImageMagick resize/quality, **non-fatal** — failure uploads the original) → `upload_image` (curl FTP with retries, archives a timestamped copy on success). Credentials are passed to curl via a temp `.netrc` (mode 600) so they never appear in the process list. The script uses `set -e` plus an EXIT/INT/TERM trap that cleans up `NETRC_FILE` and `PROCESS_TEMP_FILE`.

3. **`healthcheck.sh`** — invoked by Docker's HEALTHCHECK. Reports unhealthy if `crond` is not running, if `/home/root/image.jpg` is missing, if it's older than `HEALTHCHECK_MAX_AGE` (default 300s), or if the last 10 log lines contain >5 errors and zero successes.

Working image lives at `/home/root/image.jpg`; archived copies at `/home/root/archive/image_<timestamp>.jpg` (last `KEEP_IMAGES` retained, default 5). Logs go to `/var/log/ams-cam-upload.log` with logrotate at 5 MB × 3 (`logrotate.conf`). The compose file mounts `./data/archive` and `./data/logs` for persistence.

**Status web page.** Optional, on by default. `entrypoint.sh` starts `busybox httpd -h /var/www` on `STATUS_PORT` (default 8080) before launching `crond`, after symlinking `/home/root/image.jpg` into `/var/www/image.jpg` so the live snapshot is served. `ams-cam-upload.sh` maintains counters in `/home/root/stats` (key=value, sourced via `.`) and re-renders `/var/www/index.html` at the end of every run via `update_stats` and `render_status_page`. Both calls are guarded with `|| true` so a status-rendering failure never breaks the upload pipeline. Disable entirely with `STATUS_ENABLED=false`.

**Brand assets.** `static/status.css` and `static/favicon.svg` are copied into `/var/www/` by the Dockerfile. The CSS implements michael's brand (see `/Volumes/MacMicroSD/Github/michaels-branding/BRAND.md` and `AGENTS.md`) — light-mode default, Inter + JetBrains Mono via Google Fonts (with `system-ui` fallback for offline), Pine + Signal + Ember anchors, Aqua (Pine→Cyan) primary gradient on the hero, `mj/cam` lockup. The rendered HTML in `render_status_page` only emits class names — restyling means editing `static/status.css`, not the shell script. **Do not** inline styles in the rendered HTML, drift the palette to non-anchor hexes, swap the typeface, or remove the `mj` mark — those are brand invariants.

## Conventions and gotchas

- **POSIX `sh` only** (Alpine BusyBox). No bashisms — no `[[ ]]`, no arrays, no `local` outside functions where it's already used. Stick to what BusyBox provides.
- **Env-var name mismatch**: the user-facing variable in `example.env` and `docker-compose.yml` is `INPUT_IP`, but inside the container it must be `INPUT_IP_ADDRESS`. The compose file maps it. README §"Required Environment Variables" already calls this out — don't "fix" the apparent inconsistency.
- **Adding a new env var** requires touching three places: declare/default in `docker-compose.yml`, document in `example.env` and `README.md`, and add to the `grep -E '^(...)='` allowlist in `entrypoint.sh` so cron jobs can see it. The status page also surfaces `CRON_SCHEDULE` / `SERVER` / `PORT`, so any var you want shown there must be in that allowlist.
- **Container hardening** (`docker-compose.yml`): runs with `cap_drop: ALL`, only `SETGID`/`SETUID` added back (needed by crond), `no-new-privileges`. Don't add capabilities without a real reason.
- **ImageMagick** is invoked via `magick` (IM7) with `convert` as fallback (IM6); processing writes to `${IMAGE_PATH}.processing` and atomic-`mv`s on success — don't change to in-place processing. The `>` suffix on `-resize "${IMAGE_RESIZE}>"` means "shrink only, never enlarge" and is intentional.
- **Custom webcam auth**: the wget call sends `Cookie: allow-download=1` by default (works for some camera models). Additional headers go alongside it in `ams-cam-upload.sh` around line 48.
- **`variables.sh`** is a debug helper for printing env vars — not part of the runtime path. Don't wire it into the image.
