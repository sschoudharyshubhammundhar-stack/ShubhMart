-- Phase 1 performance hardening: evaluate auth helper functions once per statement
-- instead of once per row in public RLS policies.
do $$
declare
  p record;
  u text;
  c text;
  stmt text;
begin
  for p in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname='public'
      and (coalesce(qual,'') ~* 'auth\.' or coalesce(with_check,'') ~* 'auth\.')
  loop
    u := p.qual;
    c := p.with_check;
    if u is not null then
      u := regexp_replace(u, 'auth\\.(uid|role|jwt|email)\\s*\\(\\s*\\)', '(select auth.\1())', 'gi');
      execute format('alter policy %I on %I.%I using (%s)', p.policyname, p.schemaname, p.tablename, u);
    end if;
    if c is not null then
      c := regexp_replace(c, 'auth\\.(uid|role|jwt|email)\\s*\\(\\s*\\)', '(select auth.\1())', 'gi');
      execute format('alter policy %I on %I.%I with check (%s)', p.policyname, p.schemaname, p.tablename, c);
    end if;
  end loop;
end $$;
