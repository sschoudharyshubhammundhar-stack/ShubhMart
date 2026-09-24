create table if not exists public.wholesale_buyer_profiles(
 buyer_id uuid primary key references auth.users(id) on delete cascade,
 business_name text not null,
 gstin text,
 updated_at timestamptz not null default now()
);
alter table public.wholesale_buyer_profiles enable row level security;
drop policy if exists "buyers_manage_own_wholesale_profile" on public.wholesale_buyer_profiles;
create policy "buyers_manage_own_wholesale_profile" on public.wholesale_buyer_profiles for all to authenticated using((select auth.uid())=buyer_id) with check((select auth.uid())=buyer_id);
create or replace function public.save_wholesale_buyer_profile(p_business_name text,p_gstin text default null)
returns boolean language plpgsql security invoker set search_path=public as $$
begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if nullif(trim(p_business_name),'') is null then raise exception 'Business name required'; end if;
 insert into public.wholesale_buyer_profiles(buyer_id,business_name,gstin) values(auth.uid(),trim(p_business_name),nullif(trim(p_gstin),''))
 on conflict(buyer_id) do update set business_name=excluded.business_name,gstin=excluded.gstin,updated_at=now();
 return true;
end $$;
revoke all on function public.save_wholesale_buyer_profile(text,text) from public,anon;
grant execute on function public.save_wholesale_buyer_profile(text,text) to authenticated;