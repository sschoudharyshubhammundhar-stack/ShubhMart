# ShubhMart Integrations

## Connected and confirmed
- GitHub: source repository and version history.
- Supabase: database, Auth, RLS and Edge Functions.
- Cloudflare Workers: production deployment from the GitHub main branch.

## Present but intentionally not production-enabled
- Razorpay Edge Function exists in Supabase for later payment integration.

## Not connected yet by design
- Real SMTP provider
- Real SMS OTP provider
- Google OAuth
- WhatsApp API
- Logistics or courier API
- AI model API
- Credit bureau / regulated lending partner

## Development decision
Do not add another external tool unless a concrete ShubhMart feature requires it. Replit and Netlify are not required for the final development stack.
