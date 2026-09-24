create table if not exists public.support_tickets (
 id uuid primary key default gen_random_uuid(),
 user_id uuid not null references auth.users(id) on delete cascade,
 order_id uuid references public."Orders"(id) on delete set null,
 subject text not null check(length(trim(subject)) between 3 and 200),
 category text not null default 'General' check(category in ('General','Order','Payment','Return','Refund','Delivery','Seller','Account','Service','Wholesale')),
 message text not null check(length(trim(message)) between 3 and 5000),
 status text not null default 'Open' check(status in ('Open','In Progress','Waiting for Customer','Resolved','Closed')),
 priority text not null default 'Normal' check(priority in ('Low','Normal','High','Urgent')),
 admin_note text,
 created_at timestamptz not null default now(),
 updated_at timestamptz not null default now()
);
create index if not exists support_tickets_user_created_idx on public.support_tickets(user_id,created_at desc);
create index if not exists support_tickets_status_created_idx on public.support_tickets(status,created_at desc);
create index if not exists support_tickets_order_idx on public.support_tickets(order_id);
alter table public.support_tickets enable row level security;
create policy "customers read own support tickets" on public.support_tickets for select to authenticated using(user_id=(select auth.uid()));
create policy "customers create own support tickets" on public.support_tickets for insert to authenticated with check(user_id=(select auth.uid()));
create policy "customers update own open tickets" on public.support_tickets for update to authenticated using(user_id=(select auth.uid()) and status in ('Open','Waiting for Customer')) with check(user_id=(select auth.uid()));
create policy "admin manage support tickets" on public.support_tickets for all to authenticated using((select private.is_admin())) with check((select private.is_admin()));
create or replace function public.create_support_ticket(p_subject text,p_category text,p_message text,p_order_id uuid default null,p_priority text default 'Normal')
returns uuid language plpgsql security definer set search_path=public as $$ declare tid uuid; begin
 if auth.uid() is null then raise exception 'Authentication required'; end if;
 if length(trim(coalesce(p_subject,''))) not between 3 and 200 then raise exception 'Invalid subject'; end if;
 if length(trim(coalesce(p_message,''))) not between 3 and 5000 then raise exception 'Invalid message'; end if;
 if p_category not in ('General','Order','Payment','Return','Refund','Delivery','Seller','Account','Service','Wholesale') then raise exception 'Invalid category'; end if;
 if p_priority not in ('Low','Normal','High','Urgent') then raise exception 'Invalid priority'; end if;
 if p_order_id is not null and not exists(select 1 from public."Orders" where id=p_order_id and customer_id=auth.uid()) then raise exception 'Order does not belong to customer'; end if;
 insert into public.support_tickets(user_id,order_id,subject,category,message,priority) values(auth.uid(),p_order_id,trim(p_subject),p_category,trim(p_message),p_priority) returning id into tid; return tid;
end $$;
revoke all on function public.create_support_ticket(text,text,text,uuid,text) from public,anon;
grant execute on function public.create_support_ticket(text,text,text,uuid,text) to authenticated;
create or replace function public.admin_update_support_ticket(p_ticket_id uuid,p_status text,p_priority text default null,p_admin_note text default null)
returns boolean language plpgsql security definer set search_path=public as $$ begin
 if not private.is_admin() then raise exception 'Admin access required'; end if;
 if p_status not in ('Open','In Progress','Waiting for Customer','Resolved','Closed') then raise exception 'Invalid status'; end if;
 if p_priority is not null and p_priority not in ('Low','Normal','High','Urgent') then raise exception 'Invalid priority'; end if;
 update public.support_tickets set status=p_status,priority=coalesce(p_priority,priority),admin_note=left(coalesce(p_admin_note,admin_note),5000),updated_at=now() where id=p_ticket_id;
 if not found then raise exception 'Ticket not found'; end if; return true;
end $$;
revoke all on function public.admin_update_support_ticket(uuid,text,text,text) from public,anon,authenticated;
grant execute on function public.admin_update_support_ticket(uuid,text,text,text) to authenticated;
create index if not exists notifications_user_created_idx on public.notifications(user_id,created_at desc);
create index if not exists notifications_user_unread_idx on public.notifications(user_id,created_at desc) where is_read=false;
create policy "customers insert own notifications" on public.notifications for insert to authenticated with check(user_id=(select auth.uid()));