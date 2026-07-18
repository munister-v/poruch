# Poruch

Poruch — memorial care service for people abroad who need someone trustworthy to look after a grave in Ukraine: cleanup, flowers, candles, and an honest photo report after every visit. Two sides use the same app: **customers** who order care, and **executors** who carry it out.

| | |
|---|---|
| Marketing site | https://poruch.munister.com.ua |
| Live app (customer/executor cabinet) | https://app.munister.com.ua |
| Server | VPS `173.242.49.73`, everything under `/opt/poruch-static/` and `/opt/poruch-app/` |

## Repository layout

```
poruch/          static marketing site — no build step
poruch-app/      the live app — Node.js/Express + PostgreSQL, runs in Docker
```

Both deploy straight to the VPS (rsync + Docker), independent of each other and independent of GitHub Pages. This repo is version control, not the hosting source.

---

## `poruch/` — marketing site

Plain HTML/CSS/JS, no build tooling, no framework. Each page loads a small stack of stylesheets in a fixed cascade order — later files override earlier ones by selector specificity/source order, nothing is ever edited in place once shipped, new rules are appended at the end of the relevant file.

| Page | Loads |
|---|---|
| `index.html` | `poruch.css` → `index-styles.css` → `editorial.css` |
| `executor.html` | `poruch.css` → `executor-styles.css` → `editorial.css` |
| `privacy.html`, `executor-terms.html` | `poruch.css` → `executor.css` (older, legacy) → `editorial.css` |
| `cabinet.html` | self-contained, its own `<style>` block |

`editorial.css` is the shared top layer across all four content pages — it currently carries the site's "EPRIS" visual system (Playfair Display headlines, Literata body copy, Orbit tracked-mono labels, flat hairline components, cream/ink/dusty-gold palette). Bump its `?v=` query string on every page that loads it whenever it changes, or browsers will keep serving a stale cached copy.

**Deploy:**
```sh
bash poruch/deploy.sh
```
rsync's the folder to the VPS at `/opt/poruch-static/`, served by nginx. No restart needed — static files only.

**Local preview:** any static file server pointed at `poruch/`, e.g. `python3 -m http.server` from inside the folder.

---

## `poruch-app/` — the live app

Single-file Express app (`server.js`) rendering server-side HTML via template literals — no client framework, no build step. PostgreSQL is the only datastore. Runs as two Docker Compose services: `app` (Node 22-alpine, read-only filesystem, all capabilities dropped) and `db` (Postgres 16, no port exposed outside the Docker network).

### Data model (`schema.sql`)

`users` · `sessions` · `orders` · `proposals` · `messages` · `reports` / `report_files` · `order_events` · `password_reset_tokens` · `notifications` · `verification_requests` · `disputes` · `reviews`

An order's lifecycle moves through `order_events` as an append-only log (assigned → in_progress → awaiting_review → completed, or → disputed/changes_requested along the way) — that log is what the order-detail timeline renders from.

### Routes

| Area | Routes |
|---|---|
| Auth | `GET/POST /login`, `/register`, `/logout`, `/forgot-password`, `/reset-password` |
| Dashboard | `GET /`, `/dashboard` |
| Orders | `GET/POST /orders`, `/orders/new`, `/orders/available`, `/orders/:id`, `/orders/:id/proposals`, `/orders/:id/assign`, `/orders/:id/messages`, `/orders/:id/actions`, `/orders/:id/report`, `/orders/:id/dispute`, `/orders/:id/review` |
| Profile | `GET/POST /profile`, `/profile/password`, `/sessions/revoke-others` |
| Executor verification | `GET/POST /verification` |
| Notifications | `GET /notifications`, `POST /notifications/read-all` |
| Files | `GET /files/:id` (report photos, ownership-checked) |
| Admin | `GET /admin`, `POST /admin/verifications/:id`, `/admin/disputes/:id` |
| Ops | `GET /livez`, `/readyz` |

### Security posture (audited 2026-07-18, see the security-review conversation for the full writeup)

- Every SQL query is parameterized — no string-built queries.
- Passwords: `scrypt` (N=16384, r=8, p=1), never plaintext, never reversible.
- CSRF: per-session token, timing-safe comparison (`crypto.timingSafeEqual`), required on every state-changing route reachable from an authenticated session.
- IDOR: `getOrderForUser()` is the single choke point every order-scoped route goes through — it checks the requesting user actually owns or is a legitimate participant in that order before returning anything.
- XSS: all user-supplied text is escaped at render time via `esc()`, including strings that pass through email/notification storage unescaped and only get escaped when displayed — escape-on-output, not escape-on-input.
- Uploaded report photos are verified by magic bytes (`detectImageMime`), not just by file extension or declared MIME type.
- Rate limiting on auth routes: 12 attempts / 15 minutes per key, in-memory.
- Docker: `read_only: true`, `cap_drop: ALL`, `no-new-privileges`, app bound to `127.0.0.1` only (nginx is the public TLS boundary), Postgres has no port exposed outside the compose network.
- `npm audit` is clean (0 vulnerabilities) as of the last dependency bump — check it again before any new dependency is added, and re-check on every `npm update`.

Known accepted tradeoff: the `pg.Pool` connection to Postgres isn't TLS-encrypted. Both containers share one Docker-internal network on the same host with no exposed DB port, so the traffic never leaves the host; adding unauthenticated TLS here (`rejectUnauthorized:false`) would add complexity without a real security gain.

### Environment (`.env`, see `.env.example`)

`NODE_ENV`, `PORT`, `APP_ORIGIN`, `DATABASE_URL`, `POSTGRES_DB`/`POSTGRES_USER`/`POSTGRES_PASSWORD`, `COOKIE_NAME`, `SUPPORT_EMAIL`, `SMTP_HOST`/`PORT`/`SECURE`/`USER`/`PASSWORD`/`FROM`. `NODE_ENV=production` matters functionally, not just cosmetically — it gates the `secure` cookie flag and suppresses stack traces from error responses.

`.env` lives only on the VPS, is never committed, and is explicitly excluded by both `.gitignore` and the deploy script's rsync (`--exclude=.env`).

### Deploy

```sh
bash poruch-app/deploy.sh
```
rsync's the folder to `/opt/poruch-app/` on the VPS (excluding `.env`, `uploads/`, `node_modules/`), then runs `docker compose up -d --build` and polls `/readyz` until healthy before reporting success.

### Backups

`ops/backup.sh`, run on a schedule by `ops/poruch-backup.timer` (systemd). One archive per run: `pg_dump` (custom format) + a tarball of the uploads volume + a `SHA256SUMS` file, kept for 14 days in `/var/backups/poruch/`. Restore steps are in `poruch-app/ops/README.md`.

### First administrator

There is no self-service way to become an admin — `isAdmin()` checks a plain `is_admin` boolean column, and no route ever sets it. Register normally through the UI, then grant it directly in Postgres:

```sh
docker compose exec -T db psql -U poruch -d poruch \
  -c "UPDATE users SET is_admin=TRUE WHERE email='operator@example.com';"
```

---

## History

Moved out of the `munister-v/munister-v.github.io` monorepo on 2026-07-18 — that repo is the GitHub Pages source for dozens of unrelated static sites, and this app's live backend (real user accounts, orders, Postgres data) had no reason to share history or visibility with them. It's public rather than private only because GitHub currently blocks new private repositories on this account ("U.S. trade controls law restrictions") — public repo creation is unaffected. Switch to private with `gh repo edit munister-v/poruch --visibility private` once that's lifted.
