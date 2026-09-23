create table if not exists public.ai_listing_drafts (
  id uuid primary key default gen_random_uuid(),
  seller_id uuid not null references public."Sellers"(id) on delete cascade,
  product_id uuid null references public.products(id) on delete set null,
  input_text text,
  output jsonb not null default '{}'::jsonb,
  status text not null default 'Draft' check (status in ('Draft','Applied','Discarded')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists ai_listing_drafts_seller_created_idx on public.ai_listing_drafts(seller_id,created_at desc);
create index if not exists ai_listing_drafts_product_idx on public.ai_listing_drafts(product_id);
alter table public.ai_listing_drafts enable row level security;
drop policy if exists ai_listing_seller_select on public.ai_listing_drafts;
create policy ai_listing_seller_select on public.ai_listing_drafts for select to authenticated using (seller_id in (select s.id from public."Sellers" s where s.user_id=(select auth.uid())));
drop policy if exists ai_listing_seller_insert on public.ai_listing_drafts;
create policy ai_listing_seller_insert on public.ai_listing_drafts for insert to authenticated with check (seller_id in (select s.id from public."Sellers" s where s.user_id=(select auth.uid())));
drop policy if exists ai_listing_seller_update on public.ai_listing_drafts;
create policy ai_listing_seller_update on public.ai_listing_drafts for update to authenticated using (seller_id in (select s.id from public."Sellers" s where s.user_id=(select auth.uid()))) with check (seller_id in (select s.id from public."Sellers" s where s.user_id=(select auth.uid())));
