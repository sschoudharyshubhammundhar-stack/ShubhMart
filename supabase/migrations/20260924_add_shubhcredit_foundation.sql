create table if not exists public.shubhcredit_profiles (
customer_id uuid primary key references auth.users(id) on delete cascade,
status text not null default 'Not Applied' check(status in ('Not Applied','Applied','Under Review','Approved','Rejected','Suspended')),
credit_limit numeric not null default 0 check(credit_limit>=0),
available_limit numeric not null default 0 check(available_limit>=0 and available_limit<=credit_limit),
outstanding numeric not null default 0 check(outstanding>=0),
score integer not null default 0 check(score between 0 and 900),
partner text, updated_at timestamptz not null default now());
create table if not exists public.shubhcredit_applications (
id uuid primary key default gen_random_uuid(), customer_id uuid not null references auth.users(id) on delete cascade,
requested_limit numeric not null check(requested_limit>0), monthly_income numeric check(monthly_income is null or monthly_income>=0),
employment_type text, note text, status text not null default 'Applied' check(status in ('Applied','Under Review','Approved','Rejected','Cancelled')),
created_at timestamptz not null default now(),updated_at timestamptz not null default now());
create table if not exists public.shubhcredit_transactions (
id uuid primary key default gen_random_uuid(),customer_id uuid not null references auth.users(id) on delete cascade,
type text not null check(type in ('Purchase','Repayment','Refund','Adjustment')),amount numeric not null check(amount>0),
reference_id text,note text,created_at timestamptz not null default now(),unique(customer_id,type,reference_id));
create index if not exists shubhcredit_app_customer_idx on public.shubhcredit_applications(customer_id,created_at desc);
create index if not exists shubhcredit_tx_customer_idx on public.shubhcredit_transactions(customer_id,created_at desc);
alter table public.shubhcredit_profiles enable row level security;alter table public.shubhcredit_applications enable row level security;alter table public.shubhcredit_transactions enable row level security;
create policy "credit profile own read" on public.shubhcredit_profiles for select to authenticated using(customer_id=(select auth.uid()));
create policy "credit application own read" on public.shubhcredit_applications for select to authenticated using(customer_id=(select auth.uid()));
create policy "credit application own insert" on public.shubhcredit_applications for insert to authenticated with check(customer_id=(select auth.uid()) and status='Applied');
create policy "credit transaction own read" on public.shubhcredit_transactions for select to authenticated using(customer_id=(select auth.uid()));
create policy "admin manage credit profiles" on public.shubhcredit_profiles for all to authenticated using(private.is_admin()) with check(private.is_admin());
create policy "admin manage credit applications" on public.shubhcredit_applications for all to authenticated using(private.is_admin()) with check(private.is_admin());
create policy "admin manage credit transactions" on public.shubhcredit_transactions for all to authenticated using(private.is_admin()) with check(private.is_admin());
create or replace function public.ensure_shubhcredit_profile() returns public.shubhcredit_profiles language plpgsql security invoker set search_path=public as $$
declare r public.shubhcredit_profiles; begin if (select auth.uid()) is null then raise exception 'Authentication required'; end if;
insert into public.shubhcredit_profiles(customer_id) values((select auth.uid())) on conflict(customer_id) do nothing;
select * into r from public.shubhcredit_profiles where customer_id=(select auth.uid()); return r; end $$;
revoke all on function public.ensure_shubhcredit_profile() from public,anon;grant execute on function public.ensure_shubhcredit_profile() to authenticated;