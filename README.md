# Poruch

Poruch — memorial care service for people abroad who need someone trustworthy to look after a grave in Ukraine (cleanup, flowers, candles, an honest photo report).

## Structure

- `poruch/` — marketing site (static HTML/CSS/JS). Deploy: `bash poruch/deploy.sh` (rsync to the VPS, `/opt/poruch-static/`, served by nginx). Live: https://poruch.munister.com.ua
- `poruch-app/` — the live customer/executor app (Node.js/Express + Postgres, Docker). Deploy: `bash poruch-app/deploy.sh` (rsync excluding `.env`/`uploads`, then `docker compose up -d --build` on the VPS, `/opt/poruch-app/`). Live: https://app.munister.com.ua

Both deploy directly to the VPS and do not depend on GitHub Pages — this repo exists purely for version control and history, not hosting.

## History

Moved out of the `munister-v/munister-v.github.io` monorepo on 2026-07-18 — that repo is the source for dozens of unrelated GitHub Pages sites, and poruch's live backend (real user accounts, orders, Postgres data) had no reason to share history/visibility with them.
