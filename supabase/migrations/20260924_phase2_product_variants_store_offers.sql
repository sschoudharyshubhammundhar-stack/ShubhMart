-- Product variants, seller/store discovery and offers foundation
create table if not exists public.product_variants (
 id uuid primary key default gen_random_uuid(), product_id uuid not null references public.products(id) on delete cascade,
 sku text, variant_name text not null, option_value text, price numeric not null check(price>0), mrp numeric not null check(mrp>=price),
 stock integer not null default 0 check(stock>=0), image_url text,
 status text not null default 'Pending' check(status in ('Pending','Active','Rejected')),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now()
);
create index if not exists product_variants_product_status_idx on public.product_variants(product_id,status);
create table if not exists public.product_offers (
 id uuid primary key default gen_random_uuid(), product_id uuid references public.products(id) on delete cascade,
 seller_id uuid references public."Sellers"(id) on delete cascade, code text unique, title text not null,
 discount_type text not null check(discount_type in ('percent','flat')), discount_value numeric not null check(discount_value>0),
 min_order_amount numeric not null default 0 check(min_order_amount>=0), max_discount numeric,
 starts_at timestamptz not null default now(), ends_at timestamptz,
 status text not null default 'Pending' check(status in ('Pending','Active','Expired','Rejected')), created_at timestamptz not null default now()
);
create index if not exists product_offers_product_status_idx on public.product_offers(product_id,status);
create index if not exists product_offers_seller_status_idx on public.product_offers(seller_id,status);
alter table public.product_variants enable row level security;
alter table public.product_offers enable row level security;
create policy "public view active product variants" on public.product_variants for select to anon,authenticated using(status='Active');
create policy "sellers manage own variants" on public.product_variants for all to authenticated using(exists(select 1 from public.products p join public."Sellers" s on s.id=p.seller_id where p.id=product_id and s.user_id=(select auth.uid()))) with check(exists(select 1 from public.products p join public."Sellers" s on s.id=p.seller_id where p.id=product_id and s.user_id=(select auth.uid())));
create policy "public view active offers" on public.product_offers for select to anon,authenticated using(status='Active' and (ends_at is null or ends_at>now()) and starts_at<=now());
create policy "sellers manage own offers" on public.product_offers for all to authenticated using(exists(select 1 from public."Sellers" s where s.id=seller_id and s.user_id=(select auth.uid()))) with check(exists(select 1 from public."Sellers" s where s.id=seller_id and s.user_id=(select auth.uid())));
create policy "admin manage variants" on public.product_variants for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));
create policy "admin manage offers" on public.product_offers for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));