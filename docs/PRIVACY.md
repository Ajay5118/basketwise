# MVP privacy policy

BasketWise collects the email and hashed password needed for an account and the documents you explicitly choose to upload. Receipt processing extracts shopping products, dates and financial totals. The service does not ask for shopping credentials, OTPs, email access or SMS inbox permission.

Uploaded files stay in private deployment storage and are deleted after the configured retention period, 30 days by default. User-confirmed orders, corrections and payments remain until deleted by the user. Manual bank alerts are reduced to merchant, amount, date and source hash; the original message, account suffix and VPA are not retained. Source receipts may themselves contain personal details, which is why access and retention must be restricted.

Extraction runs locally using PDF text or Tesseract. External AI and email integrations are disabled. Audit records contain mutation type, endpoint class and timestamp, never receipt text or financial amounts.

Users can export their account information, correct or delete orders, delete their account and choose a theme, budget or notification preference. Notification delivery is not enabled. Account deletion removes live structured records and private files. Deployment operators must document a separate backup-expiry policy, hosting location and support contact before onboarding public users.

Production operators must provide TLS, encrypted disks, access-controlled backups and secure secrets. This repository is not a claim that an arbitrary developer environment already supplies those protections.
