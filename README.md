# BasketWise

For the complete implementation history, verified status, local runtime details and recommended next steps, read [PROJECT_HANDOVER.md](PROJECT_HANDOVER.md).

Flutter + Django quick-commerce expense tracking. Upload a private PDF/photo, review deterministic extraction, correct missing data, confirm an order, and track INR spending. No merchant API, SMS access, external AI credentials or email connection is required.

## Repository

- `mobile/`: Flutter Material 3, Riverpod, GoRouter, Dio, secure refresh-token storage, receipt editor, five navigation destinations, charts, JSON sharing/export.
- `backend/`: Django REST, PostgreSQL migrations, Celery pipeline, private sources, parsers, analytics, bank alerts, tests.
- `docs/`: [PRD](docs/PRD.md), [architecture](docs/ARCHITECTURE.md), [implementation plan](docs/IMPLEMENTATION_PLAN.md), [API contract](docs/API_SPEC.md), [generated OpenAPI](docs/openapi.yaml).

## Start the backend with Docker

Prerequisites: Docker Compose, Flutter 3.35+ / Dart 3.9+, Android SDK; macOS/Xcode for iOS.

```powershell
Copy-Item .env.example .env
# Edit .env: choose a unique SECRET_KEY and database password.
docker compose up --build
```

API: `http://localhost:8000/api/v1/`. Interactive documentation: `http://localhost:8000/api/docs/`. PostgreSQL and Redis are internal to Compose. Private files are not exposed by HTTP. The worker image includes Tesseract. Beat runs daily retention cleanup. Development uses HTTP; configure TLS before production.

```powershell
docker compose exec api python manage.py test --settings=config.test_settings
docker compose exec api python scripts/generate_sample.py
```

## Run Flutter

```powershell
cd mobile
flutter pub get
flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1/
```

Android emulator uses `10.0.2.2` to reach the host. For a physical device, use a reachable development-server address and add it to `ALLOWED_HOSTS`. Android debug builds allow HTTP; release builds require HTTPS. Browser development: `flutter run -d chrome --web-port=3000 --dart-define=API_URL=http://localhost:8000/api/v1/`. Keep the trailing slash. Secure storage on web requires localhost or HTTPS. Camera and sharing support depend on the device/browser. Android incoming sharing is wired to the Scan screen; open Scan after launching from the share sheet. iOS incoming sharing needs an Xcode Share Extension and is not enabled in this MVP; photo/file selection and outgoing exports are implemented.

Create an account and accept processing consent. Choose **Scan → Choose receipts**, select `backend/tests/fixtures/instamart.synthetic.pdf`, open its receipt row, enter the missing date as `YYYY-MM-DD`, review products and amounts, check the review box, and confirm. The synthetic receipt yields ₹274 items + ₹12 handling + ₹0 delivery = ₹286. Packaging/tax/discount remain unknown because the sample does not state them. Their absence is disclosed before confirmation. Use a date in the current month to see ₹286 in the monthly card. Other dates appear in the date-range total/history.

## Native backend development

Python 3.12 is recommended. The PATH Python may be older; explicitly select a supported interpreter.

```powershell
py -3.12 -m venv .venv
./.venv/Scripts/python.exe -m pip install -r backend/requirements.txt
$env:SECRET_KEY='replace-with-your-random-local-development-secret'
$env:DEBUG='1'
$env:POSTGRES_HOST='127.0.0.1'
$env:POSTGRES_DB='basketwise'
$env:POSTGRES_USER='basketwise'
$env:POSTGRES_PASSWORD='your-local-password'
cd backend
../.venv/Scripts/python.exe manage.py migrate
../.venv/Scripts/python.exe manage.py runserver 0.0.0.0:8000
```

Run Redis separately and `celery -A config worker --loglevel=warning --pool=solo` on Windows (prefork is intended for Linux containers). Set `REDIS_URL` as needed. Install Tesseract on PATH for images/scanned PDFs. Native PDF extraction does not require it. `CELERY_TASK_ALWAYS_EAGER=1` is an explicit local diagnostic mode that executes extraction in the request; the default uses the background worker. `USE_SQLITE=1` is an optional quick local-test fallback, not the production database. Tests can run against either database; PostgreSQL is necessary for locking/concurrency guarantees.

Password-reset email requires real SMTP configuration: `EMAIL_HOST`, `EMAIL_PORT`, `EMAIL_HOST_USER`, `EMAIL_HOST_PASSWORD`, `DEFAULT_FROM_EMAIL`. Without SMTP, password-reset delivery is unavailable. For local development only, set `EMAIL_BACKEND=django.core.mail.backends.console.EmailBackend` to inspect test reset messages. Never use that backend with real user data in production.

## Tests and contract

```powershell
cd backend
../.venv/Scripts/python.exe manage.py test --settings=config.test_settings -v 2
../.venv/Scripts/python.exe manage.py spectacular --file ../docs/openapi.yaml --fail-on-warn
cd ../mobile
flutter analyze
flutter test
# Requires a local running API; creates then deletes its own synthetic test account.
flutter test test/live_flow_test.dart --dart-define=LIVE_API=true --dart-define=API_URL=http://127.0.0.1:8000/api/v1/
```

The OCR adapter unit test substitutes Tesseract's output and verifies its boundary. Separate runtime tests execute real Tesseract on a synthetic image and scanned PDF; they explicitly skip if the binary is unavailable. Set `TESSERACT_CMD` to its full executable path when it is not on PATH. Parser platform variants use explicitly synthetic layouts; wrappers reuse a conservative grammar. No real Blinkit, Zepto, BigBasket or Instamart invoice corpus has been tested. Do not advertise general platform compatibility from these fixtures. See [verification evidence](docs/VALIDATION.md) for checks actually completed in this workspace.

## Android release

```powershell
cd mobile
flutter build apk --release --dart-define=API_URL=https://YOUR-API-HOST/api/v1/
flutter build appbundle --release --dart-define=API_URL=https://YOUR-API-HOST/api/v1/
```

Configure your own Android release signing key before store distribution. The generated development project initially uses a debug signing key for local build verification; it is not a store-ready release identity. Never commit a keystore or its passwords. iOS needs macOS, provisioning and Xcode.

## Privacy and operational limits

- Documents use a private filesystem volume by default. Optional S3 storage activates with `S3_BUCKET` and `AWS_DEFAULT_REGION`; the AWS default credential chain supplies credentials (prefer an IAM role). S3 objects request server-side AES256 encryption and signed access; the bucket must block public access. This adapter has not been tested against a real bucket. Production must place local volumes and PostgreSQL on encrypted disks, terminate TLS at a trusted proxy and provision secrets. Encryption-at-rest is infrastructure configuration, not a claim about an arbitrary developer machine.
- Native PDF text is tried before local OCR. No documents leave your deployment for AI. Unsupported rows remain absent/unknown; the editor requires products and a date before confirmation.
- Exact hashes are per-user idempotent; external merchant IDs are database-unique per user/platform. Amount/date candidates are warnings and never automatically merged. Linked payments never add to order spending.
- Delivered/refunded, confirmed orders contribute to spending. Cancelled, pending and unknown-status orders do not. Only confirmed refund records reduce net spending. Category spending is item spending before order-level fees, discounts and refunds; no unsupported allocation is invented.
- Unknown fees have explicit counts in analytics. No missing fee is presented as a verified zero. Unit prices derived from quantity and line total are marked.
- Retention removes source files after the configured days while keeping user-confirmed orders. Account deletion removes private files and structured data. Backups require a separate retention/deletion policy.
- Email integration is an abstract disabled interface. Push notifications are a stored opt-in preference only; no push service is configured. No automatic bank SMS reader exists.
- No external AI adapter is enabled. OCR quality depends on image readability. Manual correction is always available after successful text extraction; unreadable files can be retried or re-uploaded.
- Automated privacy/security checks are an MVP baseline; a deployment/security review, real-device camera/share tests, real receipt corpus and managed backups are required before public rollout.

## Engineering references

Refresh rotation follows [Simple JWT settings](https://django-rest-framework-simplejwt.readthedocs.io/en/latest/settings.html). PDF text extraction and scanned-page OCR are separate stages as described in [pypdf extraction documentation](https://github.com/py-pdf/pypdf/blob/main/docs/user/extract-text.md).
