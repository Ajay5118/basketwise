# CLAUDE.md

Guidance for Claude Code working in this repository. Read this first; deeper history lives in `PROJECT_HANDOVER.md`, setup detail in `README.md` and `docs/DOCKER.md`.

## What this is

BasketWise: privacy-first quick-commerce (Instamart/Blinkit/Zepto/BigBasket) expense tracker. A user uploads a receipt PDF/photo → backend extracts text (native PDF text first, Tesseract OCR fallback) → deterministic parsers produce a draft → user reviews/corrects in Flutter → explicit confirm creates an Order → analytics in INR.

No external AI, merchant API, SMS or email reading. Unknown values stay **unknown** (never invented as zero). Keep it that way.

## Layout

```
backend/                Django 5.2 + DRF + SimpleJWT + Celery (Python 3.12)
  config/               settings.py (env-driven), test_settings.py, urls.py, celery.py
  apps/accounts/        custom User, auth, profile, export, deletion, AuditMiddleware
  apps/orders/          Order, items, refunds, payments (bank alerts), serializers
  apps/receipts/        upload → tasks.process_receipt → extractor → parsers
    pdf_extractor.py    pypdf native text; image_ocr.py  Tesseract via pytesseract/pypdfium2
    platform_detector.py, parser_registry.py, parsers/{instamart,blinkit,zepto,bigbasket,generic,tax_invoice,bill_summary}.py
    image_ocr.extract_image_passes  3 OCR passes per image; bill_summary votes across them
    validators.py       upload limits/unsafe content + financial_warnings
    duplicate_detector.py
  apps/analytics/       Decimal-based spend calculations (services.py)
  tests/                Django TestCase suites + fixtures/instamart.synthetic.pdf
mobile/                 Flutter 3.35 / Dart 3.9, Riverpod, GoRouter, Dio
  lib/api.dart          Dio client, token refresh, providers, errorText()
  lib/main.dart         router, SessionGate, AppShell (5 tabs)
  lib/screens.dart      Auth/Reset/Home/Orders/Analytics/Profile/Payments
  lib/receipt.dart      Scan, Review, OrderEditor, Detail, Refund
  lib/design.dart       shared design components; widgets.dart  small helpers (rupees())
docs/                   PRD, ARCHITECTURE, API_SPEC, openapi.yaml (generated), VALIDATION, DOCKER
compose.yaml            db, redis, api, worker, beat
scripts/run-android-usb.ps1   build + install debug APK on a USB phone with adb reverse
```

## Environment facts (this machine)

- Windows 11. Real repo path is `D:\BasketWise` (opened as `D:\basketwise`). Use PowerShell or Git Bash.
- Python venv: `.venv/Scripts/python.exe` (3.12). PATH Python may be Anaconda; always use the venv explicitly.
- Flutter: `C:\src\flutter\bin`. adb: `%LOCALAPPDATA%\Android\Sdk\platform-tools`.
- Tesseract is **not** on PATH natively. The Docker image has it; native OCR tests skip unless `TESSERACT_CMD` is set.
- `.env` exists at the repo root and holds the Postgres password for the existing volume. **Never overwrite or regenerate `.env`.** Never print its values.

## Known runtime failures and fixes (read before debugging "it doesn't run")

1. **Docker build silently fails → stale image → API unhealthy → worker/beat never start.**
   Buildx ≥0.37 rejects the build with
   `additional privileges requested: pass "--allow=fs.read=backend\\Dockerfile"`,
   but `docker compose` still exits 0 and reuses the old image. Symptom: `Not Found: /api/health/` in api logs, api `(unhealthy)`, no worker/beat containers, uploads stuck in `queued`.
   Fix:
   ```powershell
   $env:BUILDX_BAKE_ENTITLEMENTS_FS = '0'
   docker compose up -d --build --wait --wait-timeout 240
   ```
   Persist with `[Environment]::SetEnvironmentVariable('BUILDX_BAKE_ENTITLEMENTS_FS','0','User')`.
   After any backend code change, **verify the image actually rebuilt** (`docker images basketwise-backend` timestamp, or `docker compose exec -T api grep -n health config/urls.py`).
2. api, worker and beat share one image, `basketwise-backend`, built by the api service (worker/beat use `pull_policy: never`). After a backend change, `docker compose up -d --build` rebuilds it once for all three. `scripts/run-android-usb.ps1` sets `BUILDX_BAKE_ENTITLEMENTS_FS=0` itself and fails if `/api/health/` doesn't answer.
3. `SECRET_KEY` missing or starting with `replace-with-` → `RuntimeError` at import. Compose also refuses to start without `POSTGRES_PASSWORD`.
4. Postgres "superuser password is not specified" after a failed first start: the volume was initialised without a password. `docker compose down -v` fixes it but **deletes all local data**. Ask the user first.
5. `/` and `/api/v1/` return 404 by design. Health is `/api/health/`; docs at `/api/docs/`. Anonymous throttle is 30/hour, so don't poll `/api/docs/`.
6. Upload accepted but never processed → the worker isn't running or can't reach Redis. Check `docker compose ps` and `docker compose logs --tail 100 api worker`.
7. Phone can't reach API: emulator uses `http://10.0.2.2:8000/api/v1/`; a USB phone needs `adb reverse tcp:8000 tcp:8000` + `API_URL=http://127.0.0.1:8000/api/v1/` (redo after replug). `API_URL` is compile-time, so a hot reload won't pick it up. Keep the trailing slash.
8. `DEBUG=0` turns on SSL redirect and secure cookies, which breaks the local HTTP health check. Keep `DEBUG=1` locally.

## Commands

Backend (native, fast, no Docker needed):
```bash
cd backend
SECRET_KEY=local-test-secret-key-that-is-long-enough-for-django-checks-1234 DEBUG=1 USE_SQLITE=1 \
  ../.venv/Scripts/python.exe manage.py test --settings=config.test_settings
# CI also runs:
../.venv/Scripts/python.exe manage.py makemigrations --check --dry-run
../.venv/Scripts/python.exe manage.py spectacular --file ../docs/openapi.yaml --fail-on-warn
```
Backend in Docker (Postgres + real Tesseract, authoritative):
```bash
docker compose exec -T api python manage.py test --settings=config.test_settings
docker compose exec -T api python manage.py check
docker compose exec -T api celery -A config inspect ping --timeout 5
```
Mobile:
```bash
cd mobile && flutter pub get && flutter analyze && flutter test
# live end-to-end against running API (creates + deletes its own account):
flutter test test/live_flow_test.dart --dart-define=LIVE_API=true --dart-define=API_URL=http://127.0.0.1:8000/api/v1/
```

Baseline as of 2026-10-27: 43 backend tests pass (2 OCR runtime tests skip natively), `flutter analyze` is clean, 12 Flutter tests pass, the Docker stack is healthy after the rebuild above.

## Conventions

- **Money**: `Decimal` only in the backend, never float. INR formatting via `rupees()` in Flutter.
- **Unknown ≠ zero**: missing fees/tax/discount/date stay `null`. Analytics counts unknowns explicitly. Don't "helpfully" default them.
- **Privacy**: never log receipt text, file paths or OCR exception payloads (see `tasks.process_receipt`). Uploaded files are private, never served over HTTP.
- **Per-user isolation**: every queryset filters by `request.user`. Add a test when touching views.
- **Parsers** are deterministic and conservative. Add a synthetic fixture + test for every new layout. Don't claim real-merchant compatibility from synthetic fixtures.
- **API contract**: after changing serializers or views, regenerate `docs/openapi.yaml` with `--fail-on-warn`, and keep `mobile/lib/api.dart` in sync.
- **Migrations**: commit them with model changes. `makemigrations --check` must be clean.
- Match existing style: the backend is terse (compact dict literals, few comments); Flutter uses Riverpod `StateProvider`s in `api.dart` and shared widgets in `design.dart`/`widgets.dart`.
- Record verification you actually ran in `docs/VALIDATION.md`. Don't overstate.
- Commit only when asked. The default branch is `main`; the current work is on `master`.

## Subagents

Project agents live in `.claude/agents/`:
| Agent | Use for |
|---|---|
| `devops-runtime` | Docker/Compose/Celery/env failures, "app won't start", health checks |
| `backend-django` | Django models, views, serializers, auth, analytics, migrations |
| `receipt-pipeline` | PDF/OCR extraction, platform detection, parsers, validators, fixtures |
| `flutter-mobile` | Flutter UI, Riverpod state, Dio API client, Android/USB runs |
| `qa-verifier` | Run the full verification matrix and report pass/fail honestly |
| `code-reviewer` | Read-only review of the current diff for bugs, privacy and money errors |

Typical flow: specialist agent makes the change → `qa-verifier` runs checks → `code-reviewer` reviews the diff.
