-- Phase 2: product reviews + customer Q&A foundation
create table if not exists public.product_reviews (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 order_id uuid references public."Orders"(id) on delete set null,
 rating integer not null check(rating between 1 and 5),
 review_text text,
 media_urls text[] not null default '{}',
 status text not null default 'Pending' check(status in ('Pending','Published','Rejected')),
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now(),
 unique(customer_id,product_id,order_id)
);
create index if not exists product_reviews_product_status_idx on public.product_reviews(product_id,status,created_at desc);
create table if not exists public.product_questions (
 id uuid primary key default gen_random_uuid(),
 product_id uuid not null references public.products(id) on delete cascade,
 customer_id uuid not null references auth.users(id) on delete cascade,
 question text not null check(length(trim(question)) between 3 and 1000),
 answer text,
 answered_by uuid references auth.users(id) on delete set null,
 status text not null default 'Pending' check(status in ('Pending','Answered','Rejected')),
 created_at timestamptz not null default now(),
 answered_at timestamptz
);
create index if not exists product_questions_product_status_idx on public.product_questions(product_id,status,created_at desc);
alter table public.product_reviews enable row level security;
alter table public.product_questions enable row level security;
create policy "public view published product reviews" on public.product_reviews for select to anon,authenticated using(status='Published');
create policy "customers create own product reviews" on public.product_reviews for insert to authenticated with check(customer_id=(select auth.uid()));
create policy "customers view own product reviews" on public.product_reviews for select to authenticated using(customer_id=(select auth.uid()));
create policy "customers update own pending reviews" on public.product_reviews for update to authenticated using(customer_id=(select auth.uid()) and status='Pending') with check(customer_id=(select auth.uid()) and status='Pending');
create policy "public view answered product questions" on public.product_questions for select to anon,authenticated using(status='Answered');
create policy "customers create own product questions" on public.product_questions for insert to authenticated with check(customer_id=(select auth.uid()));
create policy "customers view own product questions" on public.product_questions for select to authenticated using(customer_id=(select auth.uid()));
create policy "customers update own pending questions" on public.product_questions for update to authenticated using(customer_id=(select auth.uid()) and status='Pending') with check(customer_id=(select auth.uid()) and status='Pending');