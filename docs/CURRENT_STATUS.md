# ShubhMart Current Status

## Connected
- GitHub repository: sschoudharyshubhammundhar-stack/ShubhMart
- Supabase project: yauveaexbpokhytqijae
- Cloudflare Worker: shubhmart
- Production branch: main
- Existing production customer site remains on main.

## Existing areas
- Customer marketplace page
- Customer email/password auth code
- Customer cart, address and order UI
- Seller registration, login, profile, KYC, products, orders and payouts
- Supabase marketplace tables and RLS
- Razorpay Edge Function exists for later payment use

## Known technical debt
- Customer checkout currently creates Orders, Order_items and payments directly from browser code.
- Supabase security advisor reports multiple permissive policies on several tables.
- Real email and OTP are not ready for production.
- Wholesale, B2B, delivery-speed, AI listing, rewards and credit modules are not implemented yet.
- Frontend is still largely monolithic and must be split carefully without changing behavior.

## Next step
Build the shared configuration and module boundaries first, then refactor the customer UI in small verified steps. Do not replace the working production page in one large rewrite.
