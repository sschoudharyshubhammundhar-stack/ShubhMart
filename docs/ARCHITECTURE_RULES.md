# ShubhMart Architecture Rules

## Source of truth
- GitHub: source code and version history.
- Supabase: database, Auth, storage and backend functions.
- Cloudflare Workers: deployment.
- ChatGPT: project planning, implementation guidance and review.

## Module boundaries
- customer/: customer-facing flows.
- seller/: retail seller flows.
- wholesale/: wholesaler and bulk-buyer flows.
- admin/: administration and moderation.
- shared/: reusable UI and utilities.
- config/: public application configuration only.
- supabase/: migrations, seed data and backend functions.
- assets/: brand and UI assets.
- docs/: product and technical documentation.

## Change policy
A feature should be isolated to the smallest reasonable module. Shared changes require extra testing because they can affect multiple panels.

## Security policy
Browser code may contain only publishable Supabase configuration. Secrets belong in server-side configuration.

## Database policy
New tables, columns, policies and functions must be versioned. Avoid ad-hoc production schema changes.

## Visual policy
The uploaded ShubhMart screenshots are the master visual reference. Preserve the logo, brand name, tagline, header, navigation language and marketplace feel while making the code responsive and modular.
