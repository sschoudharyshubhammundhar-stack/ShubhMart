# Security Policy

## Reporting a vulnerability

Please do not publish exploitable security details, access tokens, passwords, API keys, customer data, or payment information in public issues.

Use GitHub's **Security** tab and private vulnerability reporting if it is enabled for this repository. If private reporting is unavailable, contact the repository owner privately before disclosing technical details.

Include the affected area, impact, reproduction steps, and any safe proof of concept. Do not access, modify, or download other users' data while testing.

## Project safety rules

- Never commit secrets or service-role credentials.
- Keep Supabase Row Level Security enabled on tables exposed through the Data API.
- Do not run production SQL migrations, payment tests, or destructive operations without explicit approval.
- Treat a successful CI run as a signal, not as proof that production behavior is correct.
