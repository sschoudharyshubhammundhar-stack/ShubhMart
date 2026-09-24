-- Save for Later + cart indexes
create table if not exists public.saved_for_later (
 id uuid primary key default gen_random_uuid(),
 customer_id uuid not null references auth.users(id) on delete cascade,
 product_id uuid not null references public.products(id) on delete cascade,
 quantity integer not null default 1 check(quantity>0),
 created_at timestamptz not null default now(), updated_at timestamptz not null default now(),
 unique(customer_id,product_id)
);
create index if not exists saved_for_later_customer_idx on public.saved_for_later(customer_id,updated_at desc);
alter table public.saved_for_later enable row level security;
create policy "customers manage own saved items" on public.saved_for_later for all to authenticated using(customer_id=(select auth.uid())) with check(customer_id=(select auth.uid()));
create index if not exists cart_customer_product_idx on public.cart(customer_id,product_id);
create index if not exists orders_customer_seller_created_idx on public."Orders"(customer_id,seller_id,created_at desc);