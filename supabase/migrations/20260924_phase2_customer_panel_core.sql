-- Phase 2: Customer panel core
-- Wishlist uniqueness + secure recently viewed history.
create unique index if not exists wishlist_customer_product_uidx on public.wishlist(customer_id,product_id);
create table if not exists public.recently_viewed (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 viewed_at timestamptz not null default now(),
 unique(customer_id,product_id)
);
create index if not exists recently_viewed_customer_viewed_idx on public.recently_viewed(customer_id,viewed_at desc);
alter table public.recently_viewed enable row level security;
drop policy if exists "customers view own recently viewed" on public.recently_viewed;
create policy "customers view own recently viewed" on public.recently_viewed for select to authenticated using (customer_id=(select auth.uid()));
drop policy if exists "customers add own recently viewed" on public.recently_viewed;
create policy "customers add own recently viewed" on public.recently_viewed for insert to authenticated with check (customer_id=(select auth.uid()));
drop policy if exists "customers update own recently viewed" on public.recently_viewed;
create policy "customers update own recently viewed" on public.recently_viewed for update to authenticated using (customer_id=(select auth.uid())) with check (customer_id=(select auth.uid()));
drop policy if exists "customers delete own recently viewed" on public.recently_viewed;
create policy "customers delete own recently viewed" on public.recently_viewed for delete to authenticated using (customer_id=(select auth.uid()));
