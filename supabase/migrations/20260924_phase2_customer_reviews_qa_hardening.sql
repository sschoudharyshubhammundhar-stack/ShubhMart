-- Harden product reviews/Q&A moderation and seller answering.
create policy "admin manage product reviews" on public.product_reviews for all to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "admin manage product questions" on public.product_questions for all to authenticated using ((select private.is_admin())) with check ((select private.is_admin()));
create policy "sellers answer product questions" on public.product_questions for update to authenticated
using (exists(select 1 from public.products p join public."Sellers" s on s.id=p.seller_id where p.id=product_id and s.user_id=(select auth.uid()) and s.status='Approved'))
with check (exists(select 1 from public.products p join public."Sellers" s on s.id=p.seller_id where p.id=product_id and s.user_id=(select auth.uid()) and s.status='Approved') and status in ('Answered','Rejected'));
create index if not exists products_seller_status_idx on public.products(seller_id,status);