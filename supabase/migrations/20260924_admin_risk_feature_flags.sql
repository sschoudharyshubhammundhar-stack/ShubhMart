create table if not exists public.risk_flags (
 id uuid primary key default gen_random_uuid(),
 entity_type text not null check(entity_type in ('order','seller','customer','payout','return')),
 entity_id uuid not null,
 risk_level text not null default 'Review' check(risk_level in ('Low','Review','High','Blocked')),
 reason text not null,
 status text not null default 'Open' check(status in ('Open','Investigating','Resolved','Dismissed')),
 metadata jsonb not null default '{}'::jsonb,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists risk_flags_status_level_created_idx on public.risk_flags(status,risk_level,created_at desc);
alter table public.risk_flags enable row level security;
drop policy if exists admins_read_risk_flags on public.risk_flags;
create policy admins_read_risk_flags on public.risk_flags for select to authenticated using (private.is_admin());

create table if not exists public.feature_flags (
 key text primary key,
 enabled boolean not null default false,
 description text,
 updated_at timestamptz not null default now(),
 updated_by uuid
);
alter table public.feature_flags enable row level security;
drop policy if exists admins_manage_feature_flags on public.feature_flags;
create policy admins_manage_feature_flags on public.feature_flags for all to authenticated using(private.is_admin()) with check(private.is_admin());
insert into public.feature_flags(key,enabled,description) values
('retailMarketplace',true,'Retail marketplace'),
('wholesaleMarketplace',true,'Wholesale marketplace'),
('aiListing',true,'AI listing drafts'),
('aiShopping',true,'AI shopping assistant'),
('shubhCoins',true,'ShubhCoins'),
('realOtp',false,'Real OTP integration'),
('realPayments',false,'Real payment integration'),
('shubhCredit',false,'ShubhCredit production integration')
on conflict(key) do nothing;

create or replace function public.admin_set_risk_flag_status(p_id uuid,p_status text)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Open','Investigating','Resolved','Dismissed') then raise exception 'Invalid risk status'; end if;
 update public.risk_flags set status=p_status,updated_at=now() where id=p_id;
 if not found then raise exception 'Risk flag not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata)
 values(auth.uid(),'risk_status','risk_flag',p_id,jsonb_build_object('status',p_status));
 return true;
end $$;
revoke all on function public.admin_set_risk_flag_status(uuid,text) from public,anon,authenticated;
grant execute on function public.admin_set_risk_flag_status(uuid,text) to authenticated;

create or replace function public.admin_set_feature_flag(p_key text,p_enabled boolean)
returns boolean language plpgsql security definer set search_path=public as $$
begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 update public.feature_flags set enabled=p_enabled,updated_at=now(),updated_by=auth.uid() where key=p_key;
 if not found then raise exception 'Feature flag not found'; end if;
 insert into public.admin_audit_logs(admin_id,action,entity_type,entity_id,metadata)
 select auth.uid(),'feature_flag','feature_flag',gen_random_uuid(),jsonb_build_object('key',p_key,'enabled',p_enabled);
 return true;
end $$;
revoke all on function public.admin_set_feature_flag(text,boolean) from public,anon,authenticated;
grant execute on function public.admin_set_feature_flag(text,boolean) to authenticated;