# API contract v1

Base `/api/v1/`. JWT Bearer authentication except registration, login and password reset. Monetary JSON values are decimal strings; unknown fields are null. Paginated collections return `count`, `next`, `previous`, `results`. Errors use HTTP status and DRF field errors/detail.

Auth POST: `auth/register/` (email,password,consent), `auth/login/`, `auth/refresh/`, `auth/logout/`, `auth/password-reset/`, `auth/password-reset/confirm/`.

Receipts: GET `receipts/` lists persisted drafts; POST `receipts/upload/` multipart `file`; GET `receipts/{id}/status/`, GET `receipts/{id}/preview/`; POST `receipts/{id}/retry/`; POST `receipts/{id}/confirm/` with corrected order fields and items. Confirmation requires date, nonnegative grand total, items, explicit review, and acknowledgement of reconciliation warnings. Repeated confirmation returns the same order.

Orders: GET list/detail, PATCH detail (creates correction history), DELETE detail; POST `orders/{id}/refunds/`.

Analytics GET: `analytics/overview/`, `monthly/`, `weekly/`, `platforms/`, `categories/`; optional ISO `start`/`end` dates. Confirmed, non-cancelled orders only.

Payments POST `payments/import/` (text,source_identifier); GET `payments/`; POST `payments/{id}/link-order/` (order). Payments never contribute to order spending.

User GET/PATCH `profile/`; GET `export/`; DELETE `account/` (password). OpenAPI at `/api/schema/`, interactive docs `/api/docs/`.
