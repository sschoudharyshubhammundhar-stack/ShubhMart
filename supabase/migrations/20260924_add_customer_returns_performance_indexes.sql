create index if not exists product_questions_answered_by_idx on public.product_questions(answered_by);
create index if not exists product_questions_customer_id_idx on public.product_questions(customer_id);
create index if not exists product_reviews_order_id_idx on public.product_reviews(order_id);
create index if not exists recently_viewed_product_id_idx on public.recently_viewed(product_id);
create index if not exists refunds_return_id_idx on public.refunds(return_id);
create index if not exists saved_for_later_product_id_idx on public.saved_for_later(product_id);
drop index if exists public.wishlist_customer_product_uidx;