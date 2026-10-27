# Verification evidence

## 27 October 2026: fee insights dashboard

- New `GET /api/v1/analytics/fees/` returns stated delivery, handling, packaging and other fees for this month, last month and all time, by fee type, by platform (average per order), by month, small "heavy" baskets (fees at least half the item value) and the worst order. Orders without fee details are counted as unknown, never zero; the fee share uses only orders with both fees and item value known.
- Flutter home shows a "cost of convenience" card linking to a Fee insights screen with plain-language observations and bar breakdowns.
- 43 backend tests pass natively and in Docker (PostgreSQL); 12 Flutter tests pass and analyze is clean. Debug APK installed on the USB tablet; the on-device screen was not observed by the developer tooling.

## 27 October 2026: bill summary screenshots, other fees, category shortcuts

- New `parsers/bill_summary.py` reads app "Bill Summary" screenshots (Item Total, fees, To Pay). Images get three OCR passes that vote per row; a rupee glyph misread as a leading 2/7 is resolved only when exactly one reading reconciles with the total, otherwise the field stays unknown.
- One user-uploaded bill summary screenshot was reprocessed in Docker with real Tesseract 5.5: item total, handling, delivery, other fees and total now match the image and reconcile. It has no product rows; no order was created. This is one layout, not general screenshot compatibility.
- `Order.other_fees` added (migration `orders.0002`), exposed in the API, the confirm flow, reconciliation (only when stated) and analytics overview. OpenAPI regenerated with `--fail-on-warn`.
- 40 backend tests pass natively (SQLite) and in Docker (PostgreSQL). Synthetic bill-summary fixtures cover voting, ambiguous readings left blank, missing total and mismatch warnings.
- Flutter analyze clean; 8 tests pass, including quick-add category chips and other fees in the editor. Debug APK installed on a USB Android tablet; manual on-device flow not yet observed.

## 26 October 2026: Docker, invoice recovery and UI redesign

- Docker Compose builds and starts successfully with PostgreSQL, Redis AOF storage, API, receipt worker and scheduler. API and worker readiness checks pass; existing database and uploaded-file volumes are preserved.
- All 33 backend tests pass inside Docker against PostgreSQL, including real Tesseract image/scanned-PDF tests and synthetic tax-table regressions. Migration checks report no changes, and OpenAPI generation passes with `--fail-on-warn`.
- The live Flutter test passes against the Docker API and Redis-backed worker with eager mode disabled. It exercises registration, token refresh, PDF upload, asynchronous extraction, review, explicit confirmation and the dashboard, then deletes its own synthetic account.
- Flutter analysis reports no issues. The ordinary suite passes seven tests, with the opt-in live test skipped in that run and passed separately. New tests cover a narrow login with the keyboard open, dashboard layout, scan controls, unreadable-invoice recovery and API error messages.
- Login, dashboard, scan and empty-extraction review screenshots were rendered and visually inspected. In-app browser checks could not start because the browser tool failed to initialize.
- One existing user-uploaded grid invoice was reprocessed after the fix. It now yields one product and a total, currency and order identifier; before the fix these were absent. Its source-file hash is unchanged and no order was confirmed or created. Order date and order status remain unknown for user review. This establishes recovery for that image, not general merchant-format compatibility.
- The Android USB launcher establishes port forwarding, builds with the phone's loopback API URL, and updates with `adb install -r`. It stops on an installation failure without uninstalling the app.

S3, SMTP delivery, iOS, broad receipt-layout coverage, physical-device camera/share flows and production infrastructure remain outside these checks.

## Initial implementation verification (historical)

Verified locally on Windows, Python 3.12, Flutter 3.35.1 / Dart 3.9, PostgreSQL 16 and Tesseract 5.4. The Windows package installer placed Tesseract at `C:/Program Files/Tesseract-OCR`; native verification selected it with `TESSERACT_CMD`.

- PostgreSQL migrations applied successfully; no missing model migrations.
- 25 backend tests pass against PostgreSQL, covering native PDF parsing, synthetic variants for all five parsers, missing evidence, reconciliation, upload limits/unsafe contents, exact and potential duplicates, refresh-token rotation, per-user isolation, refunds/cancellations and bank-payment linking without double counting.
- Real Tesseract executed successfully on both a synthetic receipt image and a raster-only scanned PDF. The separate mocked adapter test establishes only boundary behavior.
- Live Flutter test uses the production Dio API client and a running Django/PostgreSQL backend. It registers a synthetic account, uploads the sample PDF, reads extraction, enters the missing date in the actual receipt editor, explicitly reviews/confirms, and asserts the real app dashboard renders ₹286 and Instamart. It deletes its test account. Only OS keychain storage is substituted for the desktop test runner; HTTP, parsing and the database are real.
- Two local widget/unit tests pass; the opt-in live test also passes separately, including real refresh-token rotation and multipart replay after an intentionally expired access token. Receipt editor tests verify that required offscreen fields still validate and explicit review is required. INR formatting includes Indian digit grouping. Final `flutter analyze` reports no issues.
- OpenAPI generation passes with `--fail-on-warn`.
- Android release-mode APK and local-emulator debug APK built. Release uses a development signing identity and placeholder HTTPS host for build verification, requiring a real endpoint and signing key before distribution. Debug targets host port 8000 via emulator `10.0.2.2`.

The live API test used explicitly enabled Celery eager mode. Redis-backed asynchronous worker/beat deployment and Docker Compose have not been executed here because Docker/Redis runtimes are unavailable. S3 has not been exercised against an actual bucket. SMTP delivery, iOS builds/share extension, physical-device camera/gallery/share intents, production encryption infrastructure and real merchant invoice formats remain unverified. In-app browser verification was unavailable due a browser runtime connection error; the actual Flutter app was rendered and inspected using the live widget test instead.

Earlier failures found and fixed: changing PDF fixture metadata, ambiguous test scrolling, offscreen form validation, PDFium context-manager compatibility, Kotlin plugin JVM targets and cross-drive incremental caches. Passing tests are not evidence of broad OCR accuracy or general compatibility with real merchant layouts.
