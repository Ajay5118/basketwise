# BasketWise — implementation notes and next-step handover

Last updated: 25 October 2026.

This document records the work completed in the initial implementation session. It distinguishes implemented code, verified behavior, local runtime details and unfinished rollout work. Read it before continuing development; it does not replace the setup instructions in [README.md](README.md).

## 1. Starting point and current status

- The repository initially contained only `.git`; there was no existing application code.
- Created a monorepo containing a Flutter client, Django backend, migrations, receipt processing, tests, deployment configuration and documentation.
- Implemented and verified the first complete vertical slice: upload the synthetic Instamart PDF → extract products and totals → enter the missing date in the Flutter review UI → explicitly confirm → save to real PostgreSQL → render INR 286.00 on the Flutter dashboard.
- Implemented additional order tracking, analytics, refunds, bank-alert imports, profile settings, exports and account deletion.
- Built both Android debug and release-mode APKs.
- This is a working core MVP, not a fully validated production deployment or a claim of compatibility with arbitrary merchant receipts.
- No Git commit was created during implementation. At the time of this note, the new project files were still untracked. An `.idea/` directory was also visible during handover inspection; it was not created or changed as part of writing this note.

## 2. Documents created

The first four documents were created before implementation, as requested.

| File | Purpose |
| --- | --- |
| [docs/PRD.md](docs/PRD.md) | Product scope and first acceptance flow |
| [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) | Components, data flow and privacy boundaries |
| [docs/IMPLEMENTATION_PLAN.md](docs/IMPLEMENTATION_PLAN.md) | Implementation milestones |
| [docs/API_SPEC.md](docs/API_SPEC.md) | Human-readable API contract |
| [docs/openapi.yaml](docs/openapi.yaml) | Generated OpenAPI contract |
| [docs/PRIVACY.md](docs/PRIVACY.md) | MVP data handling and operational privacy requirements |
| [docs/VALIDATION.md](docs/VALIDATION.md) | Checks actually completed and their limits |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Remaining rollout work |
| [README.md](README.md) | Setup, testing, Android builds and known limitations |

## 3. Repository structure

```text
BasketWise/
  backend/
    apps/
      accounts/       User, authentication, profile, export, deletion, audit
      orders/         Orders, items, corrections, refunds, payments, budgets
      receipts/       Uploads, storage, PDF/OCR pipeline, parsers, tasks
      analytics/      Central Decimal-based financial calculations and API
      integrations/   Disabled abstract email integration interface
    config/           Settings, URLs, Celery, WSGI, schema and test settings
    scripts/          Synthetic sample PDF generator
    tests/            Backend and real OCR tests; synthetic fixtures
    manage.py
    requirements.txt
    requirements.lock.txt
    Dockerfile
    .dockerignore
  mobile/
    lib/              Flutter application source
    test/             Widget/unit tests and opt-in live API flow
    android/          Generated Android project plus application configuration
    ios/              Generated iOS project plus permission descriptions
    web/              Generated Flutter web project
    pubspec.yaml
    pubspec.lock
  docs/
  .github/workflows/ci.yaml
  .env.example
  .gitignore
  compose.yaml
  PROJECT_HANDOVER.md
```

Generated dependency caches, `.venv`, `.runtime`, private media, local databases and build outputs are excluded from Git by ignore rules. They are local artifacts, not portable source dependencies.

## 4. Backend foundation

### Framework and configuration

- Django 5.2, Django REST Framework, Simple JWT and drf-spectacular.
- PostgreSQL is the default database. `USE_SQLITE=1` is an explicit local fallback; locking guarantees require PostgreSQL.
- Celery configuration uses Redis by default. Tasks have time limits, and a daily Beat schedule invokes source-retention cleanup.
- `CELERY_TASK_ALWAYS_EAGER=1` explicitly enables synchronous diagnostic execution. It was used for the live local verification; it is not the intended background-processing deployment.
- Required `SECRET_KEY`; environment-driven database, storage, host, CORS, mail and retention settings.
- Authentication permissions, pagination and request throttling configured globally.
- `CACHE_REDIS_URL` enables a shared Redis cache for throttling across API workers. Without it, local development uses Django's default local-memory cache.
- Versioned API under `/api/v1/`, schema at `/api/schema/`, interactive documentation at `/api/docs/`.

### Models and migrations

Created models for:

- `User`: unique email, authentication fields, consent timestamp, theme, notification preference and monthly budget.
- `AuditEvent`: user, mutation method, endpoint class and timestamp; no financial payloads.
- `Platform`: platform name, slug and logo reference.
- `Order`: platform identifier, external ID, date/status, INR monetary fields, source, verification and timestamps.
- `OrderItem`: product name, quantity, unit price, derived-price flag, line total and category.
- `Correction`: previous serialized order state and correction timestamp.
- `Refund`: amount, date and pending/confirmed status.
- `PaymentTransaction`: merchant, amount, date, source identifier, payment method, status and linked order.
- `ImportEvent`: receipt import identity and processing status.
- `UserBudget`: monthly limit and alert threshold.
- `Receipt`: private file, user-scoped hash, MIME type, extraction state/JSON, parser version, safe error and linked order.

Added initial migrations for accounts, orders and receipts; subsequent migrations add audit/email normalization constraints and allow multiple receipt files to reference the same exact order.

Constraints/indexes include case-insensitive email uniqueness, user/platform/external-order-ID uniqueness, user/receipt-hash uniqueness, user/payment-source uniqueness, import identity uniqueness, nonnegative order totals and order lookup indexes.

Implementation details to preserve: `Order.platform` currently stores a validated platform slug string; it is not a foreign key to `Platform`. Profile budget updates synchronize the user budget field and `UserBudget` record. Do not assume these are different implementations without checking the code.

## 5. Authentication, privacy and account features

- Email registration/login and password validation.
- Registration requires explicit receipt-processing consent.
- JWT access tokens, refresh rotation and refresh-token blacklisting.
- Logout requests refresh revocation and clears local credentials even if the request fails because the device is offline or the session expired.
- Password-reset request and confirmation endpoints, backed by genuine Django reset tokens and configurable SMTP.
- Profile read/update for theme, notification preference and monthly budget.
- Password-confirmed account deletion, including private receipt files and structured records.
- User-scoped JSON export includes profile, orders, products, refunds, correction history, payments, receipt extraction metadata and audit records. Private storage paths are not exported.
- Audit middleware records successful authenticated mutations without logging request bodies, receipt text or amounts.
- HTTPS/security settings are enabled when `DEBUG=0`; production still needs correct TLS proxy and encrypted storage infrastructure.

SMTP delivery has not been verified. Email changes, email-address verification and social sign-in are not implemented. Notification preferences are stored, but there is no push-delivery service.

## 6. Receipt upload and extraction

Main implementation files are under `backend/apps/receipts/`.

### File handling

- Multipart PDF, PNG and JPEG uploads.
- Content inspection rather than trusting a filename or client MIME declaration.
- Default limits: 10 MB, 10 PDF pages and 25 million image pixels.
- Reject encrypted/invalid PDFs and recognized active or embedded PDF payload markers.
- UUID-based private object names and per-user SHA-256 deduplication.
- Private filesystem storage by default; uploaded sources are not served through public HTTP media routes.
- Optional private S3 adapter via `S3_BUCKET`, `AWS_DEFAULT_REGION` and the AWS default credential chain. It requests AES256 server-side encryption and signed access. Bucket public-access blocking is an operational requirement.
- Extraction uses the storage API and a temporary local copy, which is removed after processing; it does not require a filesystem-only `.path` implementation.
- Configurable retention cleanup removes old source files while preserving confirmed order data.

S3 has not been tested against a real bucket. Upload defenses are an MVP baseline, not a completed hostile-document security assessment or antivirus service.

### Processing pipeline

1. Try native PDF text extraction using pypdf.
2. Render scanned PDF pages using PDFium and run local Tesseract OCR.
3. Run local Tesseract for receipt images.
4. Identify a likely platform and select its parser through the registry.
5. Produce a nullable structured draft with provenance, derived-price flags and warnings.
6. Check line totals and financial reconciliation where the required components are available.
7. Find possible existing orders for review.
8. Wait for explicit user confirmation; extraction itself does not create an order.

Raster dimensions are bounded for scanned-PDF OCR. OCR subprocesses have timeouts. Failed extraction returns a safe error and supports retry. Queue-dispatch failure is surfaced as a retriable processing failure.

### Parser behavior and limits

- Modules exist for Instamart, Blinkit, Zepto, BigBasket and generic receipts.
- Platform wrappers currently reuse a conservative deterministic grammar; they are independently callable/testable, not independently proven real-platform implementations.
- The tested product layout uses product name, `Quantity:` and `Line total:` rows.
- Missing monetary values remain null. Unstated fees are not replaced with verified zero values.
- Unit price is derived using Decimal arithmetic when quantity and line total are available, and marked as derived.
- Correcting quantity/line total recomputes a price marked as derived on the backend.
- Order dates require an `Order date:` label in the supported grammar; arbitrary dates elsewhere are not assumed to be the order date.
- Currency is inferred as INR only when a supported currency marker is present; missing currency remains unknown in the draft.
- Status parsing requires a standalone supported status or an explicit order-status label, rather than any casual mention of a delivered/cancelled item.
- No external AI extraction is enabled; documents are not transmitted to an AI provider.

All merchant-format coverage is synthetic. Real-world format support must not be claimed until representative, consented/redacted samples pass tests.

### Synthetic Instamart example

Fixture: `backend/tests/fixtures/instamart.txt`.

Generated uploadable PDF: `backend/tests/fixtures/instamart.synthetic.pdf`.

Expected extraction:

- Heritage Pouch Curd: quantity 2, line INR 94.00, derived unit INR 47.00.
- Diet Coke Can: quantity 4, line INR 180.00, derived unit INR 45.00.
- Item subtotal INR 274.00; handling INR 12.00; delivery INR 0.00.
- Grand total INR 286.00; delivered status.
- Order date, packaging fee, taxes and discount are unknown in this sample.

The review must supply the date. Missing components remain disclosed; the user acknowledges remaining warnings before confirmation. To see the purchase in the current-month dashboard card, choose its actual date within that month; other dates remain visible in history/date-range totals.

## 7. Confirmation, duplicates and order management

- Receipt status and preview endpoints, persisted draft listing and retry support.
- Explicit review and acknowledgement of financial/duplicate warnings before confirmation.
- Atomic confirmation with row locking and database uniqueness protections.
- Reconfirming a receipt returns its saved order instead of creating another.
- Same-user exact file hashes reuse a receipt.
- Same-user/platform/external-order-ID matches reuse the existing order.
- Same platform/date/amount candidates require review; they are not automatically merged.
- Bank-alert source identifiers or message hashes prevent repeated payment imports.
- Searchable, paginated and filterable order history.
- Order detail, correction with previous-state history, deletion and refund recording.
- Deleting an order returns its associated receipt drafts to review state rather than leaving a confirmed receipt with a broken order link.

Potential duplicate detection is currently a conservative platform/date/amount candidate lookup, not a sophisticated item-similarity scoring engine. Stale processing-task recovery and broker/worker failure operations still need rollout testing.

## 8. Financial calculations, analytics and payments

Central calculation service: `backend/apps/analytics/services.py`.

- Decimal arithmetic for server-side money; API money values are strings.
- Gross spending, confirmed refunds, net spending, order counts and average order value.
- Known item subtotals, delivery fees, handling fees and discounts, with explicit counts of unknown values.
- Monthly/weekly series, net platform comparisons, item-category totals and frequent-product summaries.
- Current/previous month comparisons with correct month boundaries; no percentage comparison is invented when the previous value is zero.
- Only confirmed delivered/refunded orders contribute to spending; pending, unknown-status and cancelled orders are excluded.
- Only confirmed refund records reduce net spending, and confirmed refunds cannot exceed the order total.
- Categories remain `Uncategorized` until supplied by the user. Category/product spending is before order-level fees/refunds; unsupported allocations are not estimated.

Manual bank-alert import extracts supported debit amount/date, likely merchant and UPI evidence. It creates a `payment_detected` payment, never a delivered order or fabricated product list. It discards the raw alert/account/VPA details, supports explicit matching to an owned order and never adds payments to order-spending totals.

## 9. Flutter client

### Foundation and files

- Flutter Material 3 with light/dark/system themes.
- Riverpod providers, GoRouter routes, Dio networking and secure refresh-token storage.
- `lib/main.dart`: application theme, session restoration, routing and five-destination shell.
- `lib/api.dart`: authenticated API client, token restoration/rotation, multipart upload progress and error formatting.
- `lib/screens.dart`: authentication/reset, home, orders, analytics, profile and bank-payment screens.
- `lib/receipt.dart`: upload, extraction status/retry, review editor, order detail/corrections and refunds.
- `lib/order_filters.dart`: date, amount and import-source filters.
- `lib/widgets.dart`: shared panels, responsive page layout, loading/error states, order rows and Indian currency formatting.

### Implemented screens and interactions

- Registration/login, consent/privacy information and password-reset UI.
- Home: current/previous month net spending, comparison, counts/averages, date-range selection, platform breakdown, known fees and recent orders.
- Orders: search, platform/status filters, additional date/amount/source filters, pagination and detail navigation.
- Scan: multiple file selection, camera, gallery, upload progress, persisted drafts and background-processing status.
- Review: editable product rows, quantities/prices/categories, fees, date, platform/status, missing-field warnings and explicit confirmation.
- Details: products, monetary breakdown, source/verification information, edits, correction history, refunds and deletion.
- Analytics: monthly/weekly charts using fl_chart, platform/category comparisons and frequent products.
- Profile: saved theme/budget/notification preferences, export/share, manual bank alerts, logout, deletion and an honestly disabled email-connection entry.
- Receipt forms keep offscreen fields mounted so scrolling cannot bypass required-field validation.
- Dio clones multipart data when replaying an upload after token refresh.

### Native configuration

- Generated Android, iOS and web projects.
- Android internet permission, display name, vector basket icon and incoming image/PDF share filters.
- Android debug-only cleartext HTTP for local development.
- iOS camera/photo-library usage descriptions and application display name.
- Android incoming-share handling is attached to Scan; after launching from a share sheet, open Scan.
- iOS incoming sharing still needs a genuine Xcode Share Extension. It is not enabled in the current project.

## 10. Deployment and build changes

- Added `compose.yaml` with PostgreSQL 16, Redis 7, API, Celery worker and Beat, plus persistent database/private-file volumes.
- Added a non-root backend Docker image with Tesseract and locked Python dependencies.
- Added `.env.example`, private/build/cache ignore rules and a backend Docker ignore file.
- Added backend and Flutter GitHub Actions checks. The workflow file is supplied but was not executed on GitHub during this session.
- Added Python and Dart dependency lock files.
- Fixed Android plugin JVM compatibility by matching each Kotlin target to its Android Java target after plugin configuration.
- Disabled Kotlin incremental compilation to avoid Windows C:/D: cross-drive cache failures.

Built artifacts, excluded from Git:

| Artifact | Configuration |
| --- | --- |
| `mobile/build/app/outputs/flutter-apk/app-debug.apk` | Local Android emulator API at `http://10.0.2.2:8000/api/v1/` |
| `mobile/build/app/outputs/flutter-apk/app-release.apk` | Release-mode build verification with placeholder `https://api.example.invalid/api/v1/` |
| `.runtime/dashboard.png` | Phone-sized screenshot rendered by the live Flutter test |

The release-mode APK uses the development signing identity. It must be rebuilt with a real HTTPS endpoint and production signing key before distribution. Build output also included legacy third-party Java/font warnings; successful compilation is not physical-device validation.

## 11. Verification actually completed

Latest completed checks from implementation:

| Check | Result and scope |
| --- | --- |
| PostgreSQL migrations | Applied successfully; migration drift check reported no changes |
| Backend suite | 25 tests passed against real PostgreSQL |
| Real OCR | Tesseract read a synthetic image and raster-only scanned PDF successfully |
| Flutter local tests | Two widget/unit tests passed |
| Flutter live flow | Passed separately against running Django/PostgreSQL, including expired-token refresh and multipart replay |
| Flutter analysis | No issues |
| OpenAPI | Generated successfully using `--fail-on-warn` |
| Compose file | YAML parsed; actual Docker services were not run |
| Android builds | Debug and release-mode APKs built successfully |
| Visual review | Inspected the actual themed, phone-sized Flutter dashboard showing INR 286.00 |

Backend tests cover parsing, missing/ambiguous evidence, financial reconciliation, PDF extraction, upload validation/limits, duplicates, authentication/refresh, cross-user isolation, refunds, pending/cancelled exclusions, bank payments, exports, queue failure/retry and derived-price corrections.

The live Flutter test uses the production Dio client and actual backend/database/extraction. Only OS keychain access is substituted because it runs in a desktop widget-test harness. It creates/deletes its own test account. Earlier failed-run synthetic accounts and their source files were cleaned up.

Important verification boundary: the live API used explicit Celery eager mode. Passing this test does not establish Redis-worker execution, responsive asynchronous extraction under load or deployed retry behavior.

## 12. Local environment and background tasks

Tools found/used:

- Python 3.12: `C:/Users/ajayr/AppData/Local/Programs/Python/Python312/python.exe`.
- The original PATH Python was Anaconda 3.6 and should not be used for this backend.
- Project virtual environment: `D:/BasketWise/.venv`.
- Flutter SDK: `C:/src/flutter`; verified Flutter 3.35.1 / Dart 3.9.
- PostgreSQL 16 tools: `C:/Program Files/PostgreSQL/16/bin`.
- Tesseract installed by the Windows package installer at `C:/Program Files/Tesseract-OCR/tesseract.exe`; select it using `TESSERACT_CMD` when needed.
- Android SDK was available locally.
- Docker and Redis runtimes were unavailable during implementation.

The isolated native PostgreSQL development cluster was created under `.runtime/postgres`, bound to `127.0.0.1:55432`, with database/user `basketwise` and local trust authentication. This is a disposable local-development configuration, not production security.

The last API process was started at `http://127.0.0.1:8000` with debug enabled, the isolated PostgreSQL port, Tesseract's explicit path, local/emulator allowed hosts and `CELERY_TASK_ALWAYS_EAGER=1`. Its schema endpoint returned HTTP 200 after the final restart. These servers were intentionally left running for local testing. Process availability is session-dependent: check it before assuming it is still running later.

The API and PostgreSQL server are long-running services, not unfinished builds. Earlier Flutter commands were checked after the user's background-task question and were no longer running. All Android build commands had completed.

Do not copy a diagnostic development secret into deployment. Native Django uses environment variables; copying `.env.example` alone does not load them into a native shell. Compose reads the `.env` file through its service configuration.

## 13. Useful commands for the next session

From the repository root, configure your own development environment variables first, including `SECRET_KEY`, `DEBUG`, database credentials/host/port and optionally `TESSERACT_CMD`. For the isolated cluster above, select port `55432`; standard installations may use `5432`.

```powershell
# Backend checks
cd backend
../.venv/Scripts/python.exe manage.py test --settings=config.test_settings -v 2
../.venv/Scripts/python.exe manage.py makemigrations --check --dry-run
../.venv/Scripts/python.exe manage.py spectacular --file ../docs/openapi.yaml --fail-on-warn

# Flutter checks
cd ../mobile
flutter analyze
flutter test

# Real API flow; requires the backend to be running
flutter test test/live_flow_test.dart --dart-define=LIVE_API=true --dart-define=API_URL=http://127.0.0.1:8000/api/v1/

# Local Android emulator
flutter run --dart-define=API_URL=http://10.0.2.2:8000/api/v1/
```

The default `flutter test` skips the opt-in live test. Read [README.md](README.md) for Docker setup, SMTP, native worker execution and release builds. Inspect [docs/VALIDATION.md](docs/VALIDATION.md) before describing anything as production-verified.

## 14. Issues found and fixed during implementation

1. Default Python was too old: selected Python 3.12 and created a project virtual environment.
2. Sandbox restrictions blocked dependency downloads and Flutter cache access: used explicit approved installation/build commands.
3. Duplicate-upload test generated changing PDF metadata: made test PDF generation deterministic.
4. Flutter scrolling made form fields disappear from validation: kept editor fields mounted and added a regression test.
5. Live widget tests needed correct real-network async handling and focus/scroll coordination: corrected the harness and verified against PostgreSQL.
6. PDFium's installed version did not implement a context manager: used explicit closing and verified real scanned-PDF OCR.
7. Android plugins used inconsistent JVM targets: aligned Kotlin with each plugin's Java target.
8. Kotlin incremental caches failed across C:/D: roots: disabled incremental compilation.
9. Receipt-to-order linkage initially allowed only one receipt per order: changed it to a foreign key for exact-order deduplication across files.
10. Added safe queue failure/retry behavior, persistent draft recovery, case-insensitive email uniqueness and payload-free audit events.
11. Fixed current-month boundaries and server-side derived-unit-price recalculation after corrections.
12. Added multipart cloning for upload replay after JWT refresh, plus local credential cleanup for offline/expired logout.

## 15. Remaining limitations and next steps

### Highest priority

1. Run the Linux Docker Compose stack with real Redis. Verify upload responsiveness, worker processing, restart/retry behavior, retention cleanup, shared throttling and multi-worker idempotency. Add operational health checks and stale-task recovery where required.
2. Test the debug APK on an emulator and physical Android device: registration, secure storage, camera/gallery, PDF selection, incoming sharing, review, refunds and export.
3. Obtain consented/redacted representative receipts from each platform. Add fixtures and parser-specific behavior before claiming real merchant compatibility. Current wrappers intentionally do not imply broad format support.
4. Configure a real deployment endpoint, SMTP, release signing, encrypted database/storage, backups, deletion policy and monitoring before onboarding real financial-data users.

### Additional unfinished work

- Verify the optional S3 adapter with a real private bucket and IAM policy.
- Build/test iOS on macOS and implement its Share Extension.
- Review app behavior under large histories, heavy uploads, poor networks and low-memory devices.
- Add a richer item-aware duplicate scoring system if real import evidence justifies it.
- Review schema/documentation detail and API security before public exposure.
- Budget thresholds/notification preferences exist, but actual alert delivery is not implemented.
- External AI is optional and currently disabled; no provider adapter/key or external model accuracy is claimed.
- Email integration is an abstract disabled interface only. No OAuth connection, Gmail synchronization, SMS reading or third-party credential collection exists.
- In-app browser verification failed at browser-runtime connection; use Flutter/device validation rather than claiming browser coverage from that attempt.
- Inspect and commit the source deliberately when ready; preserve unrelated user/editor files.

Future email and notification feasibility work should follow verification of the core deployed MVP. Do not turn the disabled settings entry into a fake working integration or relax the rule that unknown financial values stay unknown until the user verifies them.
