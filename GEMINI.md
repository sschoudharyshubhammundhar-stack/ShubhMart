# Gemini / AI Assistant Guidance

Canonical instructions: read `AGENTS.md`, `MEMORY.md`, and `docs/security/README.md` before changing code or security documentation.

Follow all approval boundaries and test/reporting rules in `AGENTS.md`. Audit first; do not touch production SQL, RLS, grants, policies, triggers, RPCs, Edge Functions, payment settings, production deployments, merges, or paid resources without explicit approval. Never use production for tests or expose secrets/PII. Verify the exact commit and environment before reporting a test result. Keep unresolved controls BLOCKED/UNVERIFIED and synchronize security docs.