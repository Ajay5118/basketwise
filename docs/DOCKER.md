# Docker development

Start Docker Desktop, then run these commands from the repository root:

```powershell
# First setup only: copy the example and replace the placeholder secrets.
if (-not (Test-Path .env)) { Copy-Item .env.example .env }
docker compose up -d --build --wait --wait-timeout 180
docker compose ps
```

If `.env` already exists, preserve it. It contains the database password for the existing PostgreSQL volume. Changing that value does not change the password of an initialized database.

Quote `SECRET_KEY` and `POSTGRES_PASSWORD` if they contain `+`, `/` or `=`. Compose refuses to start when either value is missing; that is expected. Run commands from the folder that contains both `compose.yaml` and `.env`.

The backend listens on `http://localhost:8000`. Open `http://localhost:8000/api/docs/` to browse the API. Container health checks use `http://127.0.0.1:8000/api/health/` (not throttled); do not point external monitors at `/api/docs/` because anonymous rate limits apply there. The root path and `/api/v1/` do not have index pages; a 404 there does not indicate the backend is down.

This Compose file is for local development with `DEBUG=1`, as supplied by `.env.example`. Its API health check uses local HTTP. Setting `DEBUG=0` enables Django's HTTPS redirect and requires an HTTPS deployment configuration and an adjusted readiness probe; changing that flag alone is not a production deployment.

Compose runs PostgreSQL, Redis, the Django API, a Celery receipt worker, and Celery Beat for scheduled cleanup. The API, worker and Beat share one image, `basketwise-backend`, so a rebuild always updates all three together. The worker and scheduler start after the API health check passes, following migrations. PostgreSQL, Redis, API and worker expose health checks in `docker compose ps`; Beat is a long-running scheduler without a separate health probe. Health checks show readiness; Docker restart policies restart exited services, not services that remain running but unhealthy.

PostgreSQL data, private uploaded receipts, and the Redis task queue use separate named volumes. Redis enables append-only persistence; its default policy may still lose roughly the last second of writes during an abrupt failure. A worker receives up to 150 seconds to stop, allowing an active extraction to finish. Receipt files are shared between the API and worker and are not served as public files.

For phone and emulator API addresses, including Android USB forwarding, see the [Flutter instructions](../README.md#run-flutter). `10.0.2.2` reaches the host only from the Android emulator. A physical phone needs USB forwarding with a loopback API address or an appropriate LAN address. USB forwarding must be re-established after disconnecting or restarting the phone.

## Diagnose an upload

```powershell
docker compose ps
docker compose logs --tail 100 api worker
docker compose exec -T api celery -A config inspect ping --timeout 5
docker compose exec -T redis redis-cli ping
docker compose exec -T api python manage.py check
```

An API that accepts an upload still needs a reachable worker to process it. A receipt awaiting review has completed background processing; open it in the app to review and correct the extracted fields. OCR and parsing cannot guarantee that every invoice layout is recognized.

The Docker build uses locked Python dependencies, a fixed pip version, longer connection timeouts and resumable download retries to tolerate interrupted downloads. Retry `docker compose up -d --build --wait --wait-timeout 180` if an external package host is unavailable. Completed image layers are reused.

## Build fails with `additional privileges requested: pass "--allow=fs.read=..."`

Recent Docker Desktop builds use Buildx 0.37.2+, which enforces filesystem entitlements during `docker compose build`. That can fail when the project directory is a symlink or when Compose does not pass `fs.read` for the Dockerfile path.

**Workaround (local development only):** in the same PowerShell session before `docker compose up`:

```powershell
$env:BUILDX_BAKE_ENTITLEMENTS_FS = '0'
docker compose up -d --build --wait --wait-timeout 180
```

To make it persistent for your user account:

```powershell
[System.Environment]::SetEnvironmentVariable('BUILDX_BAKE_ENTITLEMENTS_FS', '0', 'User')
```

Restart the terminal (and Docker Desktop if needed), then run Compose again.

Also prefer opening the repo from its real folder (for example `D:\BasketWise`) instead of a symlinked path, which triggers `project has been loaded without an explicit name from a symlink`.

Remove `BUILDX_BAKE_ENTITLEMENTS_FS` after upgrading Docker Compose to a release that includes the entitlement fix for Compose builds.

## API failed to start (`SECRET_KEY`, Postgres password, or `/api/health/` 404)

These three log lines are related:

- `Set SECRET_KEY to a unique random value` — the API container did not receive `SECRET_KEY`.
- `Database is uninitialized and superuser password is not specified` — Postgres did not receive `POSTGRES_PASSWORD`.
- `Not Found: /api/health/` — the running image is older than the health endpoint, or Gunicorn never stayed up.

From the repository root (the folder with `compose.yaml` and `.env`):

```powershell
$env:BUILDX_BAKE_ENTITLEMENTS_FS = '0'
docker compose down
docker compose up -d --build --wait --wait-timeout 180
```

If Postgres still says the password is missing after that, the database volume was created during a failed first start. This **deletes local database data**:

```powershell
docker compose down -v
docker compose up -d --build --wait --wait-timeout 180
```

Confirm `http://localhost:8000/api/health/` returns `{"status":"ok"}`.

## Stop and restart

```powershell
docker compose stop
docker compose up -d --wait --wait-timeout 180
```

Services use `restart: unless-stopped`, so they recover after unexpected process exits and Docker restarts unless explicitly stopped. Docker Desktop must itself be running. `docker compose down` removes containers but preserves named volumes; `docker compose down -v` deletes the database, receipts and persisted queue and should not be used for normal troubleshooting.

When enabling Redis persistence for an existing installation, first ensure no extraction tasks are active or queued. Recreating the previous Redis container cannot recover messages that were stored only in that container's memory. This change preserves the PostgreSQL and receipt volumes.
