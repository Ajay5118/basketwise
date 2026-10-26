# Verification evidence

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
