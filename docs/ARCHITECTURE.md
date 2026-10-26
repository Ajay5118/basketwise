# Architecture

Flutter Material 3 client → versioned Django REST API → PostgreSQL. Redis brokers Celery extraction tasks. Files live in private storage outside public static assets. Uploads are content-validated, bounded and hashed per user. Native PDF text precedes Tesseract OCR. Deterministic parser registry yields nullable structured drafts with warnings and provenance. Confirmation is an atomic transaction with database uniqueness protections.

All financial calculations use Decimal on the server; API amounts are decimal strings. JWT refresh rotation and blacklist protect sessions. Every resource query is scoped to the authenticated user. Production requires TLS, encrypted database/storage volumes and secret provisioning. No bank alert body, account number or VPA is retained.

External AI is disabled. An optional adapter must validate structured output and obtain consent before sending documents. Email integration is an abstract interface only. Celery workers require bounded concurrency and task limits; retention cleanup deletes expired private sources.
